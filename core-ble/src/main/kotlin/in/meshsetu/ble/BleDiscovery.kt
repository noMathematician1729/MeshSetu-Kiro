package `in`.meshsetu.ble

import android.annotation.SuppressLint
import android.bluetooth.BluetoothAdapter
import android.bluetooth.le.AdvertiseCallback
import android.bluetooth.le.AdvertiseData
import android.bluetooth.le.AdvertiseSettings
import android.bluetooth.le.BluetoothLeAdvertiser
import android.bluetooth.le.BluetoothLeScanner
import android.bluetooth.le.ScanCallback
import android.bluetooth.le.ScanFilter
import android.bluetooth.le.ScanResult
import android.bluetooth.le.ScanSettings
import android.os.Handler
import android.os.Looper
import android.os.ParcelUuid
import kotlinx.coroutines.suspendCancellableCoroutine
import kotlin.coroutines.resume
import kotlin.coroutines.resumeWithException

class MeshAdvertiser(private val adapter: BluetoothAdapter) {
    private var callback: AdvertiseCallback? = null

    @SuppressLint("MissingPermission")
    fun start(metadata: DiscoveryMetadata, onFailure: (Int) -> Unit = {}) {
        val advertiser: BluetoothLeAdvertiser = adapter.bluetoothLeAdvertiser ?: error("BLE advertising is unavailable")
        val primary = AdvertiseData.Builder().setIncludeDeviceName(false).addServiceUuid(MeshGatt.PARCEL_SERVICE).build()
        // A 128-bit service-data AD cannot fit this metadata in a legacy 31-byte response; use development manufacturer data.
        val response = AdvertiseData.Builder().setIncludeDeviceName(false).addManufacturerData(MeshGatt.DEVELOPMENT_MANUFACTURER_ID, metadata.encode()).build()
        val settings = AdvertiseSettings.Builder().setAdvertiseMode(AdvertiseSettings.ADVERTISE_MODE_LOW_LATENCY).setTxPowerLevel(AdvertiseSettings.ADVERTISE_TX_POWER_MEDIUM).setConnectable(true).build()
        callback = object : AdvertiseCallback() { override fun onStartFailure(errorCode: Int) = onFailure(errorCode) }
        advertiser.startAdvertising(settings, primary, response, callback)
    }

    @SuppressLint("MissingPermission")
    fun stop() { callback?.let { adapter.bluetoothLeAdvertiser?.stopAdvertising(it) }; callback = null }
}

data class DiscoveredPeer(val result: ScanResult, val metadata: DiscoveryMetadata)

class MeshScanner(private val scanner: BluetoothLeScanner) {
    @SuppressLint("MissingPermission")
    suspend fun scan(windowMs: Long = 4_000): Result<List<DiscoveredPeer>> = suspendCancellableCoroutine { continuation ->
        val found = linkedMapOf<String, DiscoveredPeer>()
        val callback = object : ScanCallback() {
            override fun onScanResult(type: Int, result: ScanResult) {
                val metadata = result.scanRecord?.getManufacturerSpecificData(MeshGatt.DEVELOPMENT_MANUFACTURER_ID)?.let(DiscoveryMetadata::decode) ?: return
                found[result.device.address] = DiscoveredPeer(result, metadata)
            }
            override fun onScanFailed(errorCode: Int) { if (continuation.isActive) continuation.resumeWithException(IllegalStateException("BLE scan failed: $errorCode")) }
        }
        val filter = ScanFilter.Builder().setServiceUuid(MeshGatt.PARCEL_SERVICE).build()
        val settings = ScanSettings.Builder().setScanMode(ScanSettings.SCAN_MODE_LOW_LATENCY).build()
        scanner.startScan(listOf(filter), settings, callback)
        val handler = Handler(Looper.getMainLooper())
        val stop = Runnable { scanner.stopScan(callback); if (continuation.isActive) continuation.resume(Result.success(found.values.toList())) }
        handler.postDelayed(stop, windowMs)
        continuation.invokeOnCancellation { handler.removeCallbacks(stop); scanner.stopScan(callback) }
    }
}
