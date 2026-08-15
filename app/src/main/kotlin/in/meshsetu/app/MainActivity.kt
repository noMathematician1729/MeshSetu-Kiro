package `in`.meshsetu.app

import android.app.Activity
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Bundle
import android.widget.Button
import android.widget.LinearLayout
import android.widget.TextView
import `in`.meshsetu.ble.BlePermissions

class MainActivity : Activity() {
    override fun onCreate(state: Bundle?) {
        super.onCreate(state)
        val status = TextView(this).apply { text = "MeshSetu\nEvent mode is off"; textSize = 20f; setPadding(32, 64, 32, 32) }
        val start = Button(this).apply {
            text = "Start event mode"
            setOnClickListener {
                if (BlePermissions.runtimePermissions().any { checkSelfPermission(it) != PackageManager.PERMISSION_GRANTED }) requestPermissions(BlePermissions.runtimePermissions(), 7)
                else startEventService(status)
            }
        }
        setContentView(LinearLayout(this).apply { orientation = LinearLayout.VERTICAL; addView(status); addView(start) })
    }

    override fun onRequestPermissionsResult(requestCode: Int, permissions: Array<out String>, results: IntArray) {
        super.onRequestPermissionsResult(requestCode, permissions, results)
        if (requestCode == 7 && results.all { it == PackageManager.PERMISSION_GRANTED }) startEventService(null)
    }

    private fun startEventService(status: TextView?) {
        startForegroundService(Intent(this, MeshEventService::class.java))
        status?.text = "MeshSetu\nEvent mode active\nBLE relay service running"
    }
}
