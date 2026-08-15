package `in`.meshsetu.app

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Intent
import android.os.Build
import android.os.IBinder
import android.bluetooth.BluetoothManager
import android.bluetooth.BluetoothAdapter
import android.util.Log
import `in`.meshsetu.ble.DiscoveryMetadata
import `in`.meshsetu.ble.DeviceKeyStore
import `in`.meshsetu.ble.GattPeerSession
import `in`.meshsetu.ble.MeshAdvertiser
import `in`.meshsetu.ble.MeshGattServer
import `in`.meshsetu.ble.MeshGatt
import `in`.meshsetu.ble.MeshScanner
import `in`.meshsetu.ble.MeshTransportCoordinator
import `in`.meshsetu.model.MeshEnvelope
import `in`.meshsetu.model.PayloadType
import `in`.meshsetu.model.PriorityBand
import `in`.meshsetu.protocol.AeadEnvelope
import `in`.meshsetu.protocol.FileRelayStore
import `in`.meshsetu.protocol.Hello
import `in`.meshsetu.protocol.JsonLineMetricSink
import `in`.meshsetu.protocol.MeshRelayEngine
import `in`.meshsetu.protocol.ProtocolMetric
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import kotlinx.coroutines.withTimeout
import java.io.File
import java.io.FileWriter
import java.security.SecureRandom
import java.util.UUID

class MeshEventService : Service() {
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.IO)
    private var coordinator: MeshTransportCoordinator? = null
    private var advertiser: MeshAdvertiser? = null
    private var localToken = 0u
    private var metricWriter: FileWriter? = null

    override fun onCreate() {
        super.onCreate()
        val manager = getSystemService(NotificationManager::class.java)
        if (Build.VERSION.SDK_INT >= 26) manager.createNotificationChannel(NotificationChannel(CHANNEL, "MeshSetu event mode", NotificationManager.IMPORTANCE_LOW))
        val notification = Notification.Builder(this, CHANNEL).setSmallIcon(android.R.drawable.stat_sys_data_bluetooth).setContentTitle("MeshSetu event mode active").setContentText("BLE relay is listening for nearby peers").setContentIntent(PendingIntent.getActivity(this, 0, Intent(this, MainActivity::class.java), PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT)).setOngoing(true).build()
        startForeground(NOTIFICATION_ID, notification)
        startMesh()
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        if (intent?.action == ACTION_SEND_TEST) scope.launch { sendTestObject() }
        return START_STICKY
    }
    override fun onBind(intent: Intent?): IBinder? = null

    private fun startMesh() {
        runCatching {
            val manager = checkNotNull(getSystemService(BluetoothManager::class.java)) { "Bluetooth manager unavailable" }
            val adapter: BluetoothAdapter = checkNotNull(manager.adapter) { "Bluetooth unavailable" }
            val siteFingerprint = MeshGatt.siteFingerprint(SITE_ID, SITE_NAMESPACE)
            localToken = SecureRandom().nextInt().toUInt().coerceAtLeast(1u)
            metricWriter = FileWriter(File(filesDir, "mesh-metrics.ndjson"), true)
            val relay = MeshRelayEngine(SITE_ID, AeadEnvelope(DeviceKeyStore.getOrCreateSiteKey(this, SITE_ID, `in`.meshsetu.ble.SiteKeyProvisioning.demoKey(SITE_ID))), FileRelayStore(File(filesDir, "mesh-relay")), System::currentTimeMillis)
            val server = MeshGattServer(this, manager)
            val transport = MeshTransportCoordinator(
                server,
                relay,
                scope,
                Hello(siteFingerprint, localToken.toULong(), CAPABILITY_RELAY or CAPABILITY_VOICE, nowEpochSec = System.currentTimeMillis() / 1_000),
            ) { metrics ->
                metricWriter?.let { writer ->
                    val sink = JsonLineMetricSink(writer)
                    metrics.forEach { metric -> sink.write(ProtocolMetric(System.currentTimeMillis(), peer = metric.peerId, kind = metric.kind, value = metric.value, detail = metric.objectId?.toString())) }
                }
            }
            transport.start().getOrThrow()
            coordinator = transport
            advertiser = MeshAdvertiser(adapter).also { it.start(DiscoveryMetadata(siteFingerprint, localToken, 1u)) { error -> Log.e(TAG, "BLE advertising failed: $error") } }
            val scanner = checkNotNull(adapter.bluetoothLeScanner) { "BLE scanner unavailable" }
            scope.launch {
                while (true) {
                    MeshScanner(scanner).scan(expectedFingerprint = siteFingerprint).getOrThrow().forEach { peer ->
                        if (!`in`.meshsetu.ble.shouldInitiate(localToken, peer.metadata.connectionToken)) return@forEach
                        if (transport.hasPeer(peer.result.device.address)) return@forEach
                        var session: GattPeerSession? = null
                        runCatching {
                            session = GattPeerSession.open(this@MeshEventService, peer.result.device)
                            val activeSession = checkNotNull(session)
                            withTimeout(8_000) { activeSession.awaitReady() }
                            transport.attach(peer.result.device.address, activeSession, peer.metadata.fingerprint, peer.result.rssi)
                        }.onFailure { error -> session?.close(); Log.w(TAG, "BLE peer session failed", error) }
                    }
                    transport.tick()
                    delay(2_000)
                }
            }
        }.onFailure { error -> Log.e(TAG, "Mesh startup failed", error); stopSelf() }
    }

    private suspend fun sendTestObject() {
        repeat(100) {
            val transport = coordinator
            if (transport != null) {
                val now = System.currentTimeMillis()
                transport.send(MeshEnvelope(
                    objectId = SecureRandom().nextLong().toULong().coerceAtLeast(1u),
                    eventId = UUID.randomUUID().toString(),
                    siteId = SITE_ID,
                    roomId = "public",
                    createdAtMs = now,
                    expiresAtMs = now + 60_000,
                    hopCount = 0,
                    hopLimit = 4,
                    priority = PriorityBand.P0_CRITICAL,
                    payloadType = PayloadType.STRUCTURED_SOS,
                    payload = ByteArray(100) { it.toByte() },
                    originEphemeralId = localToken.toULong(),
                ))
                return
            }
            delay(100)
        }
    }

    override fun onDestroy() {
        advertiser?.stop()
        coordinator?.stop()
        metricWriter?.close()
        scope.cancel()
        super.onDestroy()
    }

    companion object {
        const val ACTION_SEND_TEST = "in.meshsetu.app.SEND_TEST"
        private const val CHANNEL = "meshsetu-event"
        private const val NOTIFICATION_ID = 1001
        private const val TAG = "MeshSetu"
        private const val SITE_ID = "demo-site"
        private const val SITE_NAMESPACE = "demo"
        private const val CAPABILITY_RELAY = 1
        private const val CAPABILITY_VOICE = 1 shl 3
    }
}
