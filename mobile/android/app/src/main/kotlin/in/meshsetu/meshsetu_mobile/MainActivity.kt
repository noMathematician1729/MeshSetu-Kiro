package `in`.meshsetu.meshsetu_mobile

import android.Manifest
import android.content.pm.PackageManager
import android.location.Location
import android.location.LocationListener
import android.location.LocationManager
import android.os.Build
import android.os.Handler
import android.os.Looper
import androidx.core.content.ContextCompat
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val locationChannel = "meshsetu/location"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, locationChannel)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "getCurrentLocation" -> getCurrentLocation(result)
                    else -> result.notImplemented()
                }
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
                System.currentTimeMillis() - lastKnown.time <= 5 * 60 * 1000
            ) {
                finish(lastKnown, "no_fix")
                return
            }

            timeoutRunnable = Runnable { finish(null, "timeout") }
            handler.postDelayed(timeoutRunnable!!, 12_000L)

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
