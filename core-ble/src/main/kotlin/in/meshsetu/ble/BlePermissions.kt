package `in`.meshsetu.ble

import android.Manifest
import android.os.Build

object BlePermissions {
    fun runtimePermissions(sdk: Int = Build.VERSION.SDK_INT): Array<String> = if (sdk >= 31) {
        buildList {
            add(Manifest.permission.BLUETOOTH_SCAN)
            add(Manifest.permission.BLUETOOTH_ADVERTISE)
            add(Manifest.permission.BLUETOOTH_CONNECT)
            if (sdk >= 33) add(Manifest.permission.POST_NOTIFICATIONS)
        }.toTypedArray()
    } else {
        arrayOf(Manifest.permission.ACCESS_FINE_LOCATION)
    }
}
