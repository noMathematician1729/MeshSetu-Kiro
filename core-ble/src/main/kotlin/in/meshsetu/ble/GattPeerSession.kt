package `in`.meshsetu.ble

import android.annotation.SuppressLint
import android.bluetooth.BluetoothDevice
import android.bluetooth.BluetoothGatt
import android.bluetooth.BluetoothGattCallback
import android.bluetooth.BluetoothGattCharacteristic
import android.bluetooth.BluetoothGattDescriptor
import android.bluetooth.BluetoothProfile
import android.bluetooth.BluetoothStatusCodes
import android.content.Context
import android.os.Build
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.MutableSharedFlow
import kotlinx.coroutines.flow.SharedFlow
import kotlinx.coroutines.suspendCancellableCoroutine
import kotlin.coroutines.resume
import kotlin.coroutines.resumeWithException

enum class PeerSessionState { CONNECTING, NEGOTIATING, READY, DISCONNECTED, FAILED }

class GattPeerSession private constructor(private val context: Context, val device: BluetoothDevice) : BluetoothGattCallback() {
    private val operationLock = Mutex()
    private val ready = CompletableDeferred<Unit>()
    private val stateMutable = MutableStateFlow(PeerSessionState.CONNECTING)
    private val incomingMutable = MutableSharedFlow<ByteArray>(extraBufferCapacity = 64)
    val state: StateFlow<PeerSessionState> = stateMutable
    val incoming: SharedFlow<ByteArray> = incomingMutable
    var mtu: Int = 23
        private set
    private var gatt: BluetoothGatt? = null
    private var rx: BluetoothGattCharacteristic? = null

    @SuppressLint("MissingPermission")
    fun connect() {
        gatt = device.connectGatt(context, false, this, BluetoothDevice.TRANSPORT_LE)
    }

    suspend fun awaitReady() { ready.await() }

    @SuppressLint("MissingPermission")
    @Suppress("DEPRECATION")
    suspend fun send(bytes: ByteArray, withResponse: Boolean = true): Result<Unit> = operationLock.withLock {
        runCatching {
            awaitReady()
            val characteristic = checkNotNull(rx)
            if (Build.VERSION.SDK_INT >= 33) {
                val status = gatt!!.writeCharacteristic(characteristic, bytes, if (withResponse) BluetoothGattCharacteristic.WRITE_TYPE_DEFAULT else BluetoothGattCharacteristic.WRITE_TYPE_NO_RESPONSE)
                check(status == BluetoothStatusCodes.SUCCESS) { "GATT write failed: $status" }
            } else {
                characteristic.writeType = if (withResponse) BluetoothGattCharacteristic.WRITE_TYPE_DEFAULT else BluetoothGattCharacteristic.WRITE_TYPE_NO_RESPONSE
                characteristic.value = bytes
                check(gatt!!.writeCharacteristic(characteristic)) { "GATT write failed" }
            }
        }
    }

    override fun onConnectionStateChange(gatt: BluetoothGatt, status: Int, newState: Int) {
        if (status != BluetoothGatt.GATT_SUCCESS) {
            stateMutable.value = PeerSessionState.FAILED
            if (!ready.isCompleted) ready.completeExceptionally(IllegalStateException("GATT connection failed: $status"))
            gatt.close()
            return
        }
        if (newState == BluetoothProfile.STATE_CONNECTED) {
            stateMutable.value = PeerSessionState.NEGOTIATING
            @SuppressLint("MissingPermission") val requested = gatt.requestMtu(517)
            if (!requested) discover(gatt)
        } else if (newState == BluetoothProfile.STATE_DISCONNECTED) {
            stateMutable.value = PeerSessionState.DISCONNECTED
            if (!ready.isCompleted) ready.completeExceptionally(IllegalStateException("GATT disconnected"))
            gatt.close()
        }
    }

    override fun onMtuChanged(gatt: BluetoothGatt, mtu: Int, status: Int) {
        this.mtu = if (status == BluetoothGatt.GATT_SUCCESS) mtu else 23
        discover(gatt)
    }

    @SuppressLint("MissingPermission")
    private fun discover(gatt: BluetoothGatt) { if (!gatt.discoverServices()) fail("service discovery could not start") }

    @SuppressLint("MissingPermission")
    @Suppress("DEPRECATION")
    override fun onServicesDiscovered(gatt: BluetoothGatt, status: Int) {
        if (status != BluetoothGatt.GATT_SUCCESS) return fail("service discovery failed: $status")
        val service = gatt.getService(MeshGatt.SERVICE) ?: return fail("mesh service missing")
        rx = service.getCharacteristic(MeshGatt.RX) ?: return fail("RX characteristic missing")
        val tx = service.getCharacteristic(MeshGatt.TX) ?: return fail("TX characteristic missing")
        if (!gatt.setCharacteristicNotification(tx, true)) return fail("notification setup failed")
        val descriptor = tx.getDescriptor(MeshGatt.CCCD) ?: return fail("CCCD missing")
        if (Build.VERSION.SDK_INT >= 33) {
            if (gatt.writeDescriptor(descriptor, BluetoothGattDescriptor.ENABLE_NOTIFICATION_VALUE) != BluetoothStatusCodes.SUCCESS) return fail("CCCD write failed")
        } else {
            descriptor.value = BluetoothGattDescriptor.ENABLE_NOTIFICATION_VALUE
            if (!gatt.writeDescriptor(descriptor)) return fail("CCCD write failed")
        }
    }

    override fun onDescriptorWrite(gatt: BluetoothGatt, descriptor: BluetoothGattDescriptor, status: Int) {
        if (descriptor.uuid == MeshGatt.CCCD && status == BluetoothGatt.GATT_SUCCESS) {
            stateMutable.value = PeerSessionState.READY
            ready.complete(Unit)
        } else if (descriptor.uuid == MeshGatt.CCCD) fail("CCCD write failed: $status")
    }

    override fun onCharacteristicChanged(gatt: BluetoothGatt, characteristic: BluetoothGattCharacteristic, value: ByteArray) {
        if (characteristic.uuid == MeshGatt.TX) incomingMutable.tryEmit(value.copyOf())
    }

    @Suppress("DEPRECATION")
    override fun onCharacteristicChanged(gatt: BluetoothGatt, characteristic: BluetoothGattCharacteristic) {
        if (characteristic.uuid == MeshGatt.TX) incomingMutable.tryEmit(characteristic.value?.copyOf() ?: return)
    }

    private fun fail(message: String) {
        stateMutable.value = PeerSessionState.FAILED
        if (!ready.isCompleted) ready.completeExceptionally(IllegalStateException(message))
    }

    companion object {
        @SuppressLint("MissingPermission")
        fun open(context: Context, device: BluetoothDevice): GattPeerSession = GattPeerSession(context.applicationContext, device).also { it.connect() }
    }
}
