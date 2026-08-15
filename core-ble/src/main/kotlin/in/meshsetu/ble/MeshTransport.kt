package `in`.meshsetu.ble

import android.annotation.SuppressLint
import android.bluetooth.BluetoothDevice
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
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
import `in`.meshsetu.protocol.FrameCodec
import `in`.meshsetu.protocol.MeshRelayEngine
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
) : MeshTransport {
    private val receivedMutable = MutableSharedFlow<ReceivedObject>(extraBufferCapacity = 64)
    private val peersMutable = MutableStateFlow<List<PeerState>>(emptyList())
    private val sessions = linkedMapOf<String, GattPeerSession>()
    private val pumpLock = Mutex()
    private val jobs = mutableListOf<Job>()
    override val incoming: Flow<ReceivedObject> = receivedMutable
    override val peerState: StateFlow<List<PeerState>> = peersMutable.asStateFlow()

    init { relay.addPersistListener { envelope, peerId -> receivedMutable.tryEmit(ReceivedObject(envelope, peerId, System.currentTimeMillis())) } }

    fun start(): Result<Unit> = runCatching {
        server.start().getOrThrow()
        jobs += scope.launch(Dispatchers.IO) {
            server.incoming.collect { frame ->
                val result = relay.receive(frame.device.address, frame.bytes)
                result.controlFrames.forEach { server.notify(frame.device, it) }
                pump()
            }
        }
    }

    fun attach(peerId: String, session: GattPeerSession, fingerprint: Long, rssi: Int? = null) {
        sessions[peerId] = session
        peersMutable.value = peersMutable.value.filterNot { it.peerId == peerId } + PeerState(peerId, fingerprint, true, session.mtu, rssi, 0, System.currentTimeMillis())
        jobs += scope.launch(Dispatchers.IO) {
            session.incoming.collect { bytes ->
                val result = relay.receive(peerId, bytes)
                result.controlFrames.forEach { session.send(it, withResponse = true) }
                pump()
            }
        }
    }

    override suspend fun send(value: MeshEnvelope): SendTicket {
        relay.submit(value)
        pump()
        return SendTicket(value.objectId)
    }

    private suspend fun pump() = pumpLock.withLock {
        while (true) {
            val objectToSend = relay.nextOutbound() ?: return
            val peer = sessions.entries.firstOrNull() ?: return
            fragment(objectToSend.objectId, objectToSend.trafficClass.rank.toUByte(), objectToSend.bytes, peer.value.mtu).forEach { frame ->
                peer.value.send(FrameCodec.encode(frame), withResponse = objectToSend.trafficClass.rank <= 2)
            }
        }
    }

    fun stop() { jobs.forEach(Job::cancel); jobs.clear(); sessions.clear(); server.stop(); peersMutable.value = emptyList() }
}
