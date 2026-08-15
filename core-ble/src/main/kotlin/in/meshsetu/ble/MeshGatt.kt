package `in`.meshsetu.ble

import android.bluetooth.BluetoothGattCharacteristic
import android.bluetooth.BluetoothGattService
import android.os.ParcelUuid
import java.nio.ByteBuffer
import java.nio.ByteOrder
import java.security.MessageDigest
import java.util.UUID

object MeshGatt {
    // Project-specific UUIDs; do not replace these with a vendor UART service.
    val SERVICE: UUID = UUID.fromString("2a6f5f10-4f7b-4c46-8cc8-cf282e4f4c01")
    val RX: UUID = UUID.fromString("2a6f5f11-4f7b-4c46-8cc8-cf282e4f4c01")
    val TX: UUID = UUID.fromString("2a6f5f12-4f7b-4c46-8cc8-cf282e4f4c01")
    val CCCD: UUID = UUID.fromString("00002902-0000-1000-8000-00805f9b34fb")
    val PARCEL_SERVICE = ParcelUuid(SERVICE)
    const val DISCOVERY_VERSION: Byte = 1
    const val DEVELOPMENT_MANUFACTURER_ID: Int = 0xFFFF

    fun siteFingerprint(siteId: String, namespace: String = "demo"): Long = ByteBuffer.wrap(
        MessageDigest.getInstance("SHA-256").digest("$siteId|$namespace".toByteArray()).copyOfRange(0, 8)
    ).order(ByteOrder.BIG_ENDIAN).long

    fun service(): BluetoothGattService = BluetoothGattService(SERVICE, BluetoothGattService.SERVICE_TYPE_PRIMARY).apply {
        addCharacteristic(BluetoothGattCharacteristic(RX, BluetoothGattCharacteristic.PROPERTY_WRITE or BluetoothGattCharacteristic.PROPERTY_WRITE_NO_RESPONSE, BluetoothGattCharacteristic.PERMISSION_WRITE))
        addCharacteristic(BluetoothGattCharacteristic(TX, BluetoothGattCharacteristic.PROPERTY_NOTIFY, BluetoothGattCharacteristic.PERMISSION_READ).apply {
            addDescriptor(android.bluetooth.BluetoothGattDescriptor(CCCD, android.bluetooth.BluetoothGattDescriptor.PERMISSION_READ or android.bluetooth.BluetoothGattDescriptor.PERMISSION_WRITE))
        })
    }
}

data class DiscoveryMetadata(val fingerprint: Long, val connectionToken: UInt, val capabilities: UByte) {
    fun encode(): ByteArray = ByteBuffer.allocate(14).order(ByteOrder.BIG_ENDIAN).put(MeshGatt.DISCOVERY_VERSION).putLong(fingerprint).putInt(connectionToken.toInt()).put(capabilities.toByte()).array()

    companion object {
        fun decode(bytes: ByteArray): DiscoveryMetadata? {
            if (bytes.size != 14 || bytes[0] != MeshGatt.DISCOVERY_VERSION) return null
            val input = ByteBuffer.wrap(bytes).order(ByteOrder.BIG_ENDIAN)
            input.get()
            return DiscoveryMetadata(input.long, input.int.toUInt(), input.get().toUByte())
        }
    }
}

fun shouldInitiate(localToken: UInt, remoteToken: UInt): Boolean = when {
    localToken < remoteToken -> true
    localToken > remoteToken -> false
    else -> false // caller applies a randomized backoff on the vanishingly rare tie
}
