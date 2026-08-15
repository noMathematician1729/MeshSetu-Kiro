package `in`.meshsetu.ble

import android.annotation.SuppressLint
import android.bluetooth.BluetoothDevice
import android.bluetooth.BluetoothGatt
import android.bluetooth.BluetoothGattCharacteristic
import android.bluetooth.BluetoothGattDescriptor
import android.bluetooth.BluetoothGattServer
import android.bluetooth.BluetoothGattServerCallback
import android.bluetooth.BluetoothManager
import android.content.Context
import android.os.Build
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.withTimeoutOrNull
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import kotlinx.coroutines.channels.Channel
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.receiveAsFlow
import java.util.concurrent.ConcurrentHashMap

data class IncomingGattFrame(val device: BluetoothDevice, val bytes: ByteArray)

class MeshGattServer(private val context: Context, private val manager: BluetoothManager) {
    private val service = MeshGatt.service()
    private val frames = Channel<IncomingGattFrame>(capacity = 64)
    private val subscribers = ConcurrentHashMap.newKeySet<String>()
    private val notificationLock = Mutex()
    private var notificationCompletion: CompletableDeferred<Int>? = null
    private val callback = object : BluetoothGattServerCallback() {
        @SuppressLint("MissingPermission")
        override fun onCharacteristicWriteRequest(device: BluetoothDevice, requestId: Int, characteristic: BluetoothGattCharacteristic, preparedWrite: Boolean, responseNeeded: Boolean, offset: Int, value: ByteArray) {
            if (characteristic.uuid != MeshGatt.RX || preparedWrite || offset != 0) {
                if (responseNeeded) server?.sendResponse(device, requestId, BluetoothGatt.GATT_REQUEST_NOT_SUPPORTED, 0, null)
                return
            }
            val accepted = frames.trySend(IncomingGattFrame(device, value.copyOf())).isSuccess
            if (responseNeeded) server?.sendResponse(device, requestId, if (accepted) BluetoothGatt.GATT_SUCCESS else BluetoothGatt.GATT_FAILURE, 0, null)
        }

        @SuppressLint("MissingPermission")
        override fun onDescriptorWriteRequest(device: BluetoothDevice, requestId: Int, descriptor: BluetoothGattDescriptor, preparedWrite: Boolean, responseNeeded: Boolean, offset: Int, value: ByteArray) {
            val valid = !preparedWrite && offset == 0 && descriptor.uuid == MeshGatt.CCCD && when {
                value.contentEquals(BluetoothGattDescriptor.ENABLE_NOTIFICATION_VALUE) -> subscribers.add(device.address).let { true }
                value.contentEquals(BluetoothGattDescriptor.DISABLE_NOTIFICATION_VALUE) -> subscribers.remove(device.address).let { true }
                else -> false
            }
            if (responseNeeded) server?.sendResponse(device, requestId, if (valid) BluetoothGatt.GATT_SUCCESS else BluetoothGatt.GATT_REQUEST_NOT_SUPPORTED, 0, null)
        }

        override fun onConnectionStateChange(device: BluetoothDevice, status: Int, newState: Int) {
            if (newState != android.bluetooth.BluetoothProfile.STATE_CONNECTED) subscribers.remove(device.address)
        }

        override fun onNotificationSent(device: BluetoothDevice, status: Int) { notificationCompletion?.complete(status) }

        override fun onServiceAdded(status: Int, service: android.bluetooth.BluetoothGattService) { /* start() reports synchronous add failures */ }
    }
    private var server: BluetoothGattServer? = null
    val incoming: Flow<IncomingGattFrame> = frames.receiveAsFlow()

    @SuppressLint("MissingPermission")
    fun start(): Result<Unit> = runCatching {
        server = manager.openGattServer(context, callback) ?: error("GATT server unavailable")
        check(server!!.addService(service)) { "could not add mesh service" }
    }

    @SuppressLint("MissingPermission")
    @Suppress("DEPRECATION")
    suspend fun notifyAwait(device: BluetoothDevice, bytes: ByteArray): Boolean = notificationLock.withLock {
        if (!subscribers.contains(device.address)) return false
        val characteristic = service.getCharacteristic(MeshGatt.TX)
        val completion = CompletableDeferred<Int>().also { notificationCompletion = it }
        try {
            val started = if (Build.VERSION.SDK_INT >= 33) {
                server?.notifyCharacteristicChanged(device, characteristic, false, bytes) == android.bluetooth.BluetoothStatusCodes.SUCCESS
            } else {
                characteristic.value = bytes
                server?.notifyCharacteristicChanged(device, characteristic, false) == true
            }
            if (!started) return false
            withTimeoutOrNull(5_000) { completion.await() == BluetoothGatt.GATT_SUCCESS } ?: false
        } finally {
            if (notificationCompletion === completion) notificationCompletion = null
        }
    }

    @SuppressLint("MissingPermission")
    fun stop() { server?.clearServices(); server?.close(); server = null; subscribers.clear() }
}
