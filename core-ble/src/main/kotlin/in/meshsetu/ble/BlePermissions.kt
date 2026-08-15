package `in`.meshsetu.ble

import android.Manifest
import android.os.Build

object BlePermissions {
    fun runtimePermissions(sdk: Int = Build.VERSION.SDK_INT): Array<String> = if (sdk >= 31) {
        arrayOf(Manifest.permission.BLUETOOTH_SCAN, Manifest.permission.BLUETOOTH_ADVERTISE, Manifest.permission.BLUETOOTH_CONNECT, Manifest.permission.RECORD_AUDIO)
    } else {
        arrayOf(Manifest.permission.ACCESS_FINE_LOCATION, Manifest.permission.RECORD_AUDIO)
    }
}

