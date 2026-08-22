package `in`.meshsetu.meshsetu_mobile

import android.Manifest
import android.content.ComponentName
import android.content.Intent
import android.content.pm.PackageManager
import android.location.Location
import android.location.LocationListener
import android.location.LocationManager
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.provider.Settings
import androidx.core.content.ContextCompat
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    companion object {
        const val ACTION_TYPED_SOS_GESTURE = "in.meshsetu.meshsetu_mobile.TYPED_SOS_GESTURE"
        const val EXTRA_EMERGENCY_GESTURE = "emergency_gesture"
        private const val GESTURE_PREFERENCES = "meshsetu_emergency_gestures"
        private const val PENDING_TYPED_SOS_GESTURE = "pending_typed_sos_gesture"
    }

    private val locationChannel = "meshsetu/location"
    private val emergencyGestureChannel = "meshsetu/emergency-gestures"
    private var emergencyGestureMethodChannel: MethodChannel? = null
    private var pendingTypedSosGesture: String? = null
    private var dartGestureListenerReady = false

    override fun onCreate(savedInstanceState: android.os.Bundle?) {
        super.onCreate(savedInstanceState)
        captureTypedSosGesture(intent)
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        captureTypedSosGesture(intent)
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, locationChannel)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "getCurrentLocation" -> getCurrentLocation(result)
                    else -> result.notImplemented()
                }
            }
        val gestureMethodChannel = MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            emergencyGestureChannel,
        )
        emergencyGestureMethodChannel = gestureMethodChannel
        gestureMethodChannel
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "isEnabled" -> result.success(isEmergencyGestureServiceEnabled())
                    "openSettings" -> {
                        startActivity(Intent(Settings.ACTION_ACCESSIBILITY_SETTINGS))
                        result.success(null)
                    }
                    "takePendingTypedSosGesture" -> {
                        result.success(takePendingTypedSosGesture())
                    }
                    "gestureListenerReady" -> {
                        dartGestureListenerReady = true
                        result.success(null)
                        deliverPendingTypedSosGesture()
                    }
                    else -> result.notImplemented()
                }
            }
    }

    private fun captureTypedSosGesture(intent: Intent?) {
        if (intent?.action != ACTION_TYPED_SOS_GESTURE) return
        val gesture = intent.getStringExtra(EXTRA_EMERGENCY_GESTURE)
        if (gesture !in setOf("normal", "fire", "crime", "kidnap", "medical", "natural_disaster")) {
            return
        }
        pendingTypedSosGesture = gesture
        getSharedPreferences(GESTURE_PREFERENCES, MODE_PRIVATE)
            .edit()
            .putString(PENDING_TYPED_SOS_GESTURE, gesture)
            .apply()
        deliverPendingTypedSosGesture()
    }

    private fun takePendingTypedSosGesture(): String? {
        val gesture = pendingTypedSosGesture ?: getSharedPreferences(
            GESTURE_PREFERENCES,
            MODE_PRIVATE,
        ).getString(PENDING_TYPED_SOS_GESTURE, null)
        pendingTypedSosGesture = null
        getSharedPreferences(GESTURE_PREFERENCES, MODE_PRIVATE)
            .edit()
            .remove(PENDING_TYPED_SOS_GESTURE)
            .apply()
        return gesture
    }

    private fun deliverPendingTypedSosGesture() {
        if (!dartGestureListenerReady) return
        val gesture = takePendingTypedSosGesture() ?: return
        emergencyGestureMethodChannel?.invokeMethod("typedSosGesture", gesture)
    }

    private fun isEmergencyGestureServiceEnabled(): Boolean {
        val enabled = Settings.Secure.getString(
            contentResolver,
            Settings.Secure.ENABLED_ACCESSIBILITY_SERVICES,
        ) ?: return false
        val component = ComponentName(this, EmergencyGestureAccessibilityService::class.java)
        return enabled.split(':').any { entry ->
            ComponentName.unflattenFromString(entry) == component
        }
    }

    private fun getCurrentLocation(result: MethodChannel.Result) {
        if (ContextCompat.checkSelfPermission(
                this,
                Manifest.permission.ACCESS_FINE_LOCATION,
            ) != PackageManager.PERMISSION_GRANTED &&
            ContextCompat.checkSelfPermission(
                this,
                Manifest.permission.ACCESS_COARSE_LOCATION,
            ) != PackageManager.PERMISSION_GRANTED
        ) {
            result.success(failureMap("permission_denied"))
            return
        }

        val manager = getSystemService(LocationManager::class.java)
        val candidates = locationProviderCandidates()
        val providers = candidates.filter { provider ->
            try {
                manager.isProviderEnabled(provider)
            } catch (_: Exception) {
                false
            }
        }
        if (providers.isEmpty()) {
            result.success(failureMap("services_disabled"))
            return
        }

        val listeners = mutableListOf<LocationListener>()
        val handler = Handler(Looper.getMainLooper())
        var finished = false
        var pendingProviders = providers.size
        var timeoutRunnable: Runnable? = null

        fun finish(location: Location?, reason: String) {
            if (finished) return
            finished = true
            timeoutRunnable?.let(handler::removeCallbacks)
            listeners.forEach { listener ->
                try {
                    manager.removeUpdates(listener)
                } catch (_: SecurityException) {
                    // Permission cannot be revoked between the check and cleanup.
                }
            }
            result.success(location?.toMap() ?: failureMap(reason))
        }

        fun providerFinished(location: Location?) {
            if (location != null) {
                finish(location, "no_fix")
                return
            }
            pendingProviders -= 1
            if (pendingProviders == 0) finish(null, "no_fix")
        }

        try {
            val lastKnown = candidates.mapNotNull { candidate ->
                try {
                    manager.getLastKnownLocation(candidate)
                } catch (_: SecurityException) {
                    null
                }
            }.maxByOrNull { it.time }
            if (lastKnown != null &&
                System.currentTimeMillis() - lastKnown.time <= 30 * 60 * 1000
            ) {
                finish(lastKnown, "no_fix")
                return
            }

            timeoutRunnable = Runnable { finish(null, "timeout") }
            handler.postDelayed(timeoutRunnable!!, 20_000L)

            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
                providers.forEach { provider ->
                    try {
                        manager.getCurrentLocation(provider, null, mainExecutor) { location ->
                            providerFinished(location)
                        }
                    } catch (_: SecurityException) {
                        providerFinished(null)
                    } catch (_: IllegalArgumentException) {
                        providerFinished(null)
                    }
                }
            } else {
                providers.forEach { provider ->
                    val listener = object : LocationListener {
                        override fun onLocationChanged(location: Location) {
                            providerFinished(location)
                        }
                    }
                    listeners += listener
                    try {
                        @Suppress("DEPRECATION")
                        manager.requestSingleUpdate(
                            provider,
                            listener,
                            Looper.getMainLooper(),
                        )
                    } catch (_: SecurityException) {
                        providerFinished(null)
                    } catch (_: IllegalArgumentException) {
                        providerFinished(null)
                    }
                }
            }
        } catch (_: SecurityException) {
            finish(null, "permission_denied")
        } catch (_: IllegalArgumentException) {
            finish(null, "unavailable")
        }
    }

    private fun locationProviderCandidates(): List<String> = buildList {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            add(LocationManager.FUSED_PROVIDER)
        }
        add(LocationManager.GPS_PROVIDER)
        add(LocationManager.NETWORK_PROVIDER)
    }

    private fun failureMap(reason: String): Map<String, Any> = mapOf(
        "ok" to false,
        "reason" to reason,
    )

    private fun Location.toMap(): Map<String, Any?> = mapOf(
        "ok" to true,
        "latitude" to latitude,
        "longitude" to longitude,
        "accuracyM" to if (hasAccuracy()) accuracy.toDouble() else null,
        "capturedAtMs" to time,
    )
}
