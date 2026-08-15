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
import kotlinx.coroutines.flow.MutableSharedFlow
import kotlinx.coroutines.flow.SharedFlow
import java.util.concurrent.ConcurrentHashMap

data class IncomingGattFrame(val device: BluetoothDevice, val bytes: ByteArray)

class MeshGattServer(private val context: Context, private val manager: BluetoothManager) {
    private val service = MeshGatt.service()
    private val frames = MutableSharedFlow<IncomingGattFrame>(extraBufferCapacity = 64)
    private val subscribers = ConcurrentHashMap.newKeySet<String>()
    private val callback = object : BluetoothGattServerCallback() {
        @SuppressLint("MissingPermission")
        override fun onCharacteristicWriteRequest(device: BluetoothDevice, requestId: Int, characteristic: BluetoothGattCharacteristic, preparedWrite: Boolean, responseNeeded: Boolean, offset: Int, value: ByteArray) {
            if (characteristic.uuid != MeshGatt.RX || preparedWrite || offset != 0) {
                if (responseNeeded) server?.sendResponse(device, requestId, BluetoothGatt.GATT_REQUEST_NOT_SUPPORTED, 0, null)
                return
            }
            frames.tryEmit(IncomingGattFrame(device, value.copyOf()))
            if (responseNeeded) server?.sendResponse(device, requestId, BluetoothGatt.GATT_SUCCESS, 0, null)
        }

        @SuppressLint("MissingPermission")
        override fun onDescriptorWriteRequest(device: BluetoothDevice, requestId: Int, descriptor: BluetoothGattDescriptor, preparedWrite: Boolean, responseNeeded: Boolean, offset: Int, value: ByteArray) {
            if (descriptor.uuid == MeshGatt.CCCD && value.contentEquals(BluetoothGattDescriptor.ENABLE_NOTIFICATION_VALUE)) subscribers += device.address
            if (responseNeeded) server?.sendResponse(device, requestId, BluetoothGatt.GATT_SUCCESS, 0, null)
        }

        override fun onServiceAdded(status: Int, service: android.bluetooth.BluetoothGattService) { /* start() reports synchronous add failures */ }
    }
    private var server: BluetoothGattServer? = null
    val incoming: SharedFlow<IncomingGattFrame> = frames

    @SuppressLint("MissingPermission")
    fun start(): Result<Unit> = runCatching {
        server = manager.openGattServer(context, callback) ?: error("GATT server unavailable")
        check(server!!.addService(service)) { "could not add mesh service" }
    }

    @SuppressLint("MissingPermission")
    @Suppress("DEPRECATION")
    fun notify(device: BluetoothDevice, bytes: ByteArray): Boolean {
        if (!subscribers.contains(device.address)) return false
        val characteristic = service.getCharacteristic(MeshGatt.TX)
        return if (Build.VERSION.SDK_INT >= 33) server?.notifyCharacteristicChanged(device, characteristic, false, bytes) == android.bluetooth.BluetoothStatusCodes.SUCCESS else {
            characteristic.value = bytes
            server?.notifyCharacteristicChanged(device, characteristic, false) == true
        }
    }

    @SuppressLint("MissingPermission")
    fun stop() { server?.clearServices(); server?.close(); server = null; subscribers.clear() }
}
