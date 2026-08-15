package `in`.meshsetu.app

import android.Manifest
import android.app.Activity
import android.content.Intent
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
                requestPermissions(BlePermissions.runtimePermissions(), 7)
                startForegroundService(Intent(this@MainActivity, MeshEventService::class.java))
                status.text = "MeshSetu\nEvent mode active\nBLE relay service running"
            }
        }
        setContentView(LinearLayout(this).apply { orientation = LinearLayout.VERTICAL; addView(status); addView(start) })
    }
}

