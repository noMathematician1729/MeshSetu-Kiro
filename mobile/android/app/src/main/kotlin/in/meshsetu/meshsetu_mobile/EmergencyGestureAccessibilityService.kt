package `in`.meshsetu.meshsetu_mobile

import android.accessibilityservice.AccessibilityService
import android.accessibilityservice.AccessibilityServiceInfo
import android.content.Intent
import android.os.Handler
import android.os.Looper
import android.util.Log
import android.view.KeyEvent

/**
 * Opt-in global emergency gesture listener.
 *
 * It intentionally does not consume volume keys: their normal volume behavior
 * remains available. A recognized gesture brings MeshSetu to the foreground,
 * where the typed red-SOS confirmation countdown must complete before send.
 *
 * Sequences are evaluated after [WINDOW_MS], rather than on each key press, so
 * prefix patterns never collide: for example ↓↓↓ is Fire while ↓↓↓↓ is a
 * Natural Disaster, and neither also fires an earlier partial sequence.
 */
class EmergencyGestureAccessibilityService : AccessibilityService() {
    companion object {
        private const val TAG = "MeshSetuGesture"
        private const val WINDOW_MS = 900L
        private const val COOLDOWN_MS = 3_000L
        private const val UP = 'U'
        private const val DOWN = 'D'
    }

    private val handler = Handler(Looper.getMainLooper())
    private val sequence = StringBuilder()
    private var lastKeyAtMs = 0L
    private var lastTriggerAtMs = 0L
    private val evaluateSequence = Runnable { dispatchCurrentSequence() }

    override fun onServiceConnected() {
        super.onServiceConnected()
        serviceInfo = serviceInfo.apply {
            flags = flags or AccessibilityServiceInfo.FLAG_REQUEST_FILTER_KEY_EVENTS
        }
    }

    override fun onAccessibilityEvent(event: android.view.accessibility.AccessibilityEvent?) = Unit

    override fun onInterrupt() = Unit

    override fun onKeyEvent(event: KeyEvent): Boolean {
        if (event.action != KeyEvent.ACTION_UP || event.repeatCount != 0) return false
        val key = when (event.keyCode) {
            KeyEvent.KEYCODE_VOLUME_UP -> UP
            KeyEvent.KEYCODE_VOLUME_DOWN -> DOWN
            else -> return false
        }
        val now = System.currentTimeMillis()
        if (now - lastKeyAtMs > WINDOW_MS) resetSequence()
        lastKeyAtMs = now
        if (sequence.length < 4) sequence.append(key) else resetSequence()
        handler.removeCallbacks(evaluateSequence)
        handler.postDelayed(evaluateSequence, WINDOW_MS)
        // Never block normal volume adjustment.
        return false
    }

    override fun onDestroy() {
        handler.removeCallbacks(evaluateSequence)
        super.onDestroy()
    }

    private fun dispatchCurrentSequence() {
        val pattern = sequence.toString()
        resetSequence()
        val kind = when (pattern) {
            "UU" -> "normal"
            "DDD" -> "fire"
            "UDU" -> "crime"
            "DUD" -> "kidnap"
            "UUU" -> "medical"
            "DDDD" -> "natural_disaster"
            else -> null
        } ?: return

        val now = System.currentTimeMillis()
        if (now - lastTriggerAtMs < COOLDOWN_MS) return
        lastTriggerAtMs = now
        val launchIntent = Intent(this, MainActivity::class.java).apply {
            action = MainActivity.ACTION_TYPED_SOS_GESTURE
            putExtra(MainActivity.EXTRA_EMERGENCY_GESTURE, kind)
            addFlags(
                Intent.FLAG_ACTIVITY_NEW_TASK or
                    Intent.FLAG_ACTIVITY_CLEAR_TOP or
                    Intent.FLAG_ACTIVITY_SINGLE_TOP,
            )
        }
        startActivity(launchIntent)
        Log.i(TAG, "Opened typed SOS confirmation for gesture: $kind")
    }

    private fun resetSequence() {
        sequence.clear()
        handler.removeCallbacks(evaluateSequence)
    }
}
