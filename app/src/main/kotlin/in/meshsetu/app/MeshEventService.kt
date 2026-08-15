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
import `in`.meshsetu.ble.DiscoveryMetadata
import `in`.meshsetu.ble.GattPeerSession
import `in`.meshsetu.ble.MeshAdvertiser
import `in`.meshsetu.ble.MeshGattServer
import `in`.meshsetu.ble.MeshScanner
import `in`.meshsetu.ble.MeshTransportCoordinator
import `in`.meshsetu.ble.DeviceKeyStore
import `in`.meshsetu.model.MeshEnvelope
import `in`.meshsetu.protocol.AeadEnvelope
import `in`.meshsetu.protocol.MeshRelayEngine
import `in`.meshsetu.protocol.RelayStore
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import kotlinx.coroutines.withTimeout
import java.security.SecureRandom

class MeshEventService : Service() {
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.IO)
    private var coordinator: MeshTransportCoordinator? = null
    private var advertiser: MeshAdvertiser? = null
    private var localToken = 0u

    override fun onCreate() {
        super.onCreate()
        val manager = getSystemService(NotificationManager::class.java)
        if (Build.VERSION.SDK_INT >= 26) manager.createNotificationChannel(NotificationChannel(CHANNEL, "MeshSetu event mode", NotificationManager.IMPORTANCE_LOW))
        val notification = Notification.Builder(this, CHANNEL).setSmallIcon(android.R.drawable.stat_sys_data_bluetooth).setContentTitle("MeshSetu event mode active").setContentText("BLE relay is listening for nearby peers").setContentIntent(PendingIntent.getActivity(this, 0, Intent(this, MainActivity::class.java), PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT)).setOngoing(true).build()
        startForeground(NOTIFICATION_ID, notification)
        startMesh()
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int = START_STICKY
    override fun onBind(intent: Intent?): IBinder? = null

    private fun startMesh() {
        runCatching {
            val manager = checkNotNull(getSystemService(BluetoothManager::class.java)) { "Bluetooth manager unavailable" }
            val adapter: BluetoothAdapter = checkNotNull(manager.adapter) { "Bluetooth unavailable" }
            val relay = MeshRelayEngine("demo-site", AeadEnvelope(DeviceKeyStore.getOrCreate()), object : RelayStore {
                override fun persist(envelope: MeshEnvelope) { /* Room adapter attaches here. */ }
            }, System::currentTimeMillis)
            val server = MeshGattServer(this, manager)
            val transport = MeshTransportCoordinator(server, relay, scope)
            transport.start().getOrThrow()
            coordinator = transport
            localToken = SecureRandom().nextInt().toUInt()
            advertiser = MeshAdvertiser(adapter).also { it.start(DiscoveryMetadata(0x4d45534853455455, localToken, 1u)) }
            val scanner = adapter.bluetoothLeScanner ?: return
            scope.launch {
                while (true) {
                    MeshScanner(scanner).scan().getOrNull().orEmpty().forEach { peer ->
                        if (!`in`.meshsetu.ble.shouldInitiate(localToken, peer.metadata.connectionToken)) return@forEach
                        runCatching {
                            val session = GattPeerSession.open(this@MeshEventService, peer.result.device)
                            withTimeout(8_000) { session.awaitReady() }
                            transport.attach(peer.result.device.address, session, peer.metadata.fingerprint, peer.result.rssi)
                        }
                    }
                    delay(2_000)
                }
            }
        }.onFailure { stopSelf() }
    }

    override fun onDestroy() {
        advertiser?.stop()
        coordinator?.stop()
        scope.cancel()
        super.onDestroy()
    }

    companion object { private const val CHANNEL = "meshsetu-event"; private const val NOTIFICATION_ID = 1001 }
}
