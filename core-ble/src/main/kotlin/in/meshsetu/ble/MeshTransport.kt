package `in`.meshsetu.ble

import android.annotation.SuppressLint
import android.bluetooth.BluetoothDevice
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.coroutineScope
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.MutableSharedFlow
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import `in`.meshsetu.model.MeshEnvelope
import `in`.meshsetu.model.PeerState
import `in`.meshsetu.model.ReceivedObject
import `in`.meshsetu.model.TrafficClass
import `in`.meshsetu.protocol.FrameCodec
import `in`.meshsetu.protocol.FrameType
import `in`.meshsetu.protocol.Hello
import `in`.meshsetu.protocol.HelloCodec
import `in`.meshsetu.protocol.MeshRelayEngine
import `in`.meshsetu.protocol.RelayMetric
import `in`.meshsetu.protocol.fragment

data class SendTicket(val objectId: ULong)

interface MeshTransport {
    val incoming: Flow<ReceivedObject>
    val peerState: StateFlow<List<PeerState>>
    suspend fun send(value: MeshEnvelope): SendTicket
}

class MeshTransportCoordinator(
    private val server: MeshGattServer,
    private val relay: MeshRelayEngine,
    private val scope: CoroutineScope,
    private val localHello: Hello? = null,
    private val onMetrics: (List<RelayMetric>) -> Unit = {},
) : MeshTransport {
    private val receivedMutable = MutableSharedFlow<ReceivedObject>(extraBufferCapacity = 64)
    private val peersMutable = MutableStateFlow<List<PeerState>>(emptyList())
    private val sessions = linkedMapOf<String, GattPeerSession>()
    private val pumpLock = Mutex()
    private val sessionJobs = mutableMapOf<String, Job>()
    private var serverJob: Job? = null
    override val incoming: Flow<ReceivedObject> = receivedMutable
    override val peerState: StateFlow<List<PeerState>> = peersMutable.asStateFlow()

    init { relay.addPersistListener { envelope, peerId -> receivedMutable.tryEmit(ReceivedObject(envelope, peerId, System.currentTimeMillis())) } }

    fun start(): Result<Unit> = runCatching {
        server.start().getOrThrow()
        serverJob = scope.launch(Dispatchers.IO) {
            server.incoming.collect { frame ->
                if (!acceptsHello(frame.bytes)) return@collect
                val result = relay.receive(frame.device.address, frame.bytes)
                onMetrics(result.metrics)
                result.controlFrames.forEach { server.notifyAwait(frame.device, it) }
                pump()
            }
        }
    }

    fun attach(peerId: String, session: GattPeerSession, fingerprint: Long, rssi: Int? = null) {
        synchronized(sessions) {
            sessions.remove(peerId)?.close()
            sessionJobs.remove(peerId)?.cancel()
            sessions[peerId] = session
        }
        peersMutable.value = peersMutable.value.filterNot { it.peerId == peerId } + PeerState(peerId, fingerprint, true, session.mtu, rssi, 0, System.currentTimeMillis())
        sessionJobs[peerId] = scope.launch(Dispatchers.IO) {
            coroutineScope {
                launch {
                    session.state.collect { state ->
                        if (state == PeerSessionState.DISCONNECTED || state == PeerSessionState.FAILED) {
                            synchronized(sessions) {
                                if (sessions[peerId] === session) sessions.remove(peerId)
                                sessionJobs.remove(peerId)?.cancel()
                            }
                            peersMutable.value = peersMutable.value.filterNot { it.peerId == peerId }
                        }
                    }
                }
                launch {
                    localHello?.let { hello ->
                        session.send(FrameCodec.encode(`in`.meshsetu.protocol.MeshFrame(FrameType.HELLO, 0u, 0u, hello.ephemeralNodeId, 0u, 1u, HelloCodec.encode(hello))))
                    }
                    session.incoming.collect { bytes ->
                        if (!acceptsHello(bytes)) {
                            session.close()
                            return@collect
                        }
                        val result = relay.receive(peerId, bytes)
                        onMetrics(result.metrics)
                        result.controlFrames.forEach { session.send(it, withResponse = true) }
                        pump()
                    }
                }
            }
        }
    }

    override suspend fun send(value: MeshEnvelope): SendTicket {
        relay.submit(value)
        pump()
        return SendTicket(value.objectId)
    }

    fun hasPeer(peerId: String): Boolean = synchronized(sessions) { sessions.containsKey(peerId) }

    suspend fun tick() {
        val peers = synchronized(sessions) { sessions.entries.toList() }
        peers.forEach { (peerId, session) ->
            relay.missingForPeer(peerId).forEach { session.send(it, withResponse = true) }
        }
        pump()
        onMetrics(relay.drainMetrics())
    }

    private suspend fun pump() = pumpLock.withLock {
        relay.retryExpired()
        val peers = synchronized(sessions) { sessions.entries.toList().take(MAX_REPLICATION_PEERS) }
        if (peers.isEmpty()) return
        while (true) {
            val objectToSend = relay.nextOutbound() ?: return
            var sent = false
            var deferred = false
            peers.forEach { peer ->
                runCatching {
                    fragment(objectToSend.objectId, objectToSend.trafficClass.rank.toUByte(), objectToSend.bytes, peer.value.mtu).forEach { frame ->
                        check(peer.value.send(FrameCodec.encode(frame), withResponse = true).isSuccess)
                    }
                    relay.markSent(objectToSend, peer.key)
                    sent = true
                }.onFailure { error ->
                    if (objectToSend.trafficClass == TrafficClass.VOICE_EVIDENCE && error is IllegalArgumentException) {
                        relay.defer(objectToSend)
                        deferred = true
                        onMetrics(listOf(RelayMetric("deferred_mtu", objectToSend.objectId, peer.key)))
                    }
                }
            }
            if (!sent) {
                if (!deferred) relay.requeue(objectToSend)
                return
            }
        }
    }

    fun stop() {
        serverJob?.cancel()
        serverJob = null
        synchronized(sessions) {
            sessionJobs.values.forEach(Job::cancel)
            sessionJobs.clear()
            sessions.values.forEach(GattPeerSession::close)
            sessions.clear()
        }
        server.stop()
        peersMutable.value = emptyList()
    }

    private companion object {
        const val MAX_REPLICATION_PEERS = 2
    }

    private fun acceptsHello(bytes: ByteArray): Boolean {
        val hello = runCatching { FrameCodec.decode(bytes) }.getOrNull()?.takeIf { it.type == FrameType.HELLO } ?: return true
        val remote = HelloCodec.decode(hello.payload) ?: return false
        return localHello == null || remote.siteFingerprint == localHello.siteFingerprint
    }
}
