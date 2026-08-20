package `in`.meshsetu.app

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.net.ConnectivityManager
import android.net.NetworkCapabilities
import android.net.Uri
import android.os.Bundle
import android.provider.Settings
import `in`.meshsetu.model.MeshEnvelope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import org.json.JSONObject
import java.net.HttpURLConnection
import java.net.URL

private const val RELAY_CHANNEL = "meshsetu-sos-relay"
private const val DETAILS_CHANNEL = "meshsetu-sos-details"

data class IncidentSnapshot(val title: String, val body: String, val publicUrl: String?)

/** Keeps the existing encrypted GATT flow intact and only enriches an already verified SOS. */
class SosRelayNotifier(private val context: Context) {
    private val manager = context.getSystemService(NotificationManager::class.java)
    private val gateway = RelaySosGateway(context)

    init {
        manager.createNotificationChannel(NotificationChannel(RELAY_CHANNEL, "SOS relay alerts", NotificationManager.IMPORTANCE_HIGH).apply { description = "Shows when this device is relaying an SOS" })
        manager.createNotificationChannel(NotificationChannel(DETAILS_CHANNEL, "SOS detail updates", NotificationManager.IMPORTANCE_HIGH).apply { description = "Shows enriched SOS details and important updates" })
    }

    fun isOnline(): Boolean {
        val network = context.getSystemService(ConnectivityManager::class.java).activeNetwork ?: return false
        val capabilities = context.getSystemService(ConnectivityManager::class.java).getNetworkCapabilities(network) ?: return false
        return capabilities.hasCapability(NetworkCapabilities.NET_CAPABILITY_INTERNET)
    }

    fun showRelay(envelope: MeshEnvelope, online: Boolean) {
        val summary = localSummary(envelope)
        val title = if (online) "SOS received — decrypted" else "You are relaying an SOS"
        val body = if (online) summary else "Relay ${envelope.eventId.take(8)} · ${summary.substringBefore(" · ")}" 
        manager.notify(notificationId(envelope, 0), notification(RELAY_CHANNEL, title, body, null))
    }

    suspend fun enrich(envelope: MeshEnvelope): IncidentSnapshot? = gateway.sync(envelope)

    fun showEnriched(envelope: MeshEnvelope, snapshot: IncidentSnapshot) {
        manager.notify(notificationId(envelope, 1), notification(DETAILS_CHANNEL, snapshot.title, snapshot.body, snapshot.publicUrl))
    }

    fun showServerDelivery(delivery: ServerNotificationDelivery) {
        manager.notify(("server:" + delivery.notificationId).hashCode() and 0x7fffffff, notification(DETAILS_CHANNEL, delivery.title, delivery.body, delivery.publicUrl))
    }

    private fun notification(channel: String, title: String, body: String, publicUrl: String?): Notification {
        val intent = publicUrl?.let { Intent(Intent.ACTION_VIEW, Uri.parse(it)) } ?: Intent(context, MainActivity::class.java)
        val pending = PendingIntent.getActivity(context, title.hashCode() xor body.hashCode(), intent, PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT)
        return Notification.Builder(context, channel)
            .setSmallIcon(android.R.drawable.stat_sys_warning)
            .setContentTitle(title)
            .setContentText(body)
            .setStyle(Notification.BigTextStyle().bigText(body))
            .setCategory(Notification.CATEGORY_ALARM)
            .setAutoCancel(true)
            .setContentIntent(pending)
            .build()
    }

    private fun notificationId(envelope: MeshEnvelope, update: Int) = (envelope.eventId.hashCode() and 0x3fffffff) + update

    private fun localSummary(envelope: MeshEnvelope): String = runCatching {
        val payload = JSONObject(envelope.payload.toString(Charsets.UTF_8))
        listOf(payload.optString("incidentType", "Emergency"), payload.optString("logicalZone", ""), payload.optString("transcript", "")).filter { it.isNotBlank() }.joinToString(" · ")
    }.getOrElse { "Verified encrypted SOS · ${envelope.hopCount} relay hops" }
}

private class RelaySosGateway(context: Context) {
    private val metadata: Bundle? = context.packageManager.getApplicationInfo(context.packageName, android.content.pm.PackageManager.GET_META_DATA).metaData
    private val baseUrl = metadata?.getString("in.meshsetu.GATEWAY_URL")?.trimEnd('/') ?: ""
    private val gatewayKey = metadata?.getString("in.meshsetu.GATEWAY_KEY")?.takeIf { it.isNotBlank() }
    private val relayDeviceId = Settings.Secure.getString(context.contentResolver, Settings.Secure.ANDROID_ID) ?: "unknown-relay"

    suspend fun sync(envelope: MeshEnvelope): IncidentSnapshot? = withContext(Dispatchers.IO) {
        if (baseUrl.isBlank()) return@withContext null
        val uploaded = gatewayKey?.let { upload(envelope, it) }
        uploaded ?: fetch(envelope.eventId)
    }

    private fun upload(envelope: MeshEnvelope, key: String): IncidentSnapshot? {
        val payload = runCatching { JSONObject(envelope.payload.toString(Charsets.UTF_8)) }.getOrElse { JSONObject() }
        val reporter = payload.optJSONObject("reporter")
        val event = JSONObject().apply {
            put("event_id", envelope.eventId); put("object_id", envelope.objectId.toString()); put("site_id", envelope.siteId); put("room_id", envelope.roomId)
            put("priority", when (envelope.priority.name) { "P0_CRITICAL" -> "p0Critical"; "P1_HIGH" -> "p1High"; "P2_NORMAL" -> "p2Normal"; else -> "p3Bulk" })
            put("incident_type", payload.optString("incidentType", "compact_sos")); put("transcript", payload.optString("transcript", ""))
            put("zone", payload.optString("logicalZone", "")); put("latitude", payload.opt("lat")); put("longitude", payload.opt("lon")); put("accuracy_m", payload.opt("accuracyM")); put("location_captured_at_ms", payload.opt("locationCapturedAtMs"))
            put("hops", envelope.hopCount); put("relay_latency_ms", (System.currentTimeMillis() - envelope.createdAtMs).coerceAtLeast(0)); put("created_at_ms", envelope.createdAtMs); put("expires_at_ms", envelope.expiresAtMs)
            reporter?.optString("uid")?.takeIf { it.isNotBlank() }?.let { put("reporter_uid", it) }
        }
        return request("$baseUrl/v1/gateway/relay-sos", JSONObject().put("relay_device_id", relayDeviceId).put("event", event), key)
    }

    private fun fetch(eventId: String): IncidentSnapshot? = request("$baseUrl/v1/public/sos/${Uri.encode(eventId)}", null, null)

    private fun request(url: String, body: JSONObject?, key: String?): IncidentSnapshot? = runCatching {
        val connection = URL(url).openConnection() as HttpURLConnection
        connection.requestMethod = if (body == null) "GET" else "POST"
        connection.connectTimeout = 5_000; connection.readTimeout = 5_000
        connection.setRequestProperty("Accept", "application/json")
        key?.let { connection.setRequestProperty("X-MeshSetu-Gateway-Key", it) }
        if (body != null) {
            connection.doOutput = true; connection.setRequestProperty("Content-Type", "application/json")
            connection.outputStream.bufferedWriter().use { it.write(body.toString()) }
        }
        if (connection.responseCode !in 200..299) return null
        val json = connection.inputStream.bufferedReader().use { JSONObject(it.readText()) }
        val event = json.optJSONObject("event") ?: json
        val reporter = event.optString("reporter_name", event.optString("reporter_uid", "Unknown sender"))
        val incident = event.optString("incident_type", "Emergency")
        val zone = event.optString("zone", "")
        val transcript = event.optString("transcript", "")
        IncidentSnapshot("SOS details received", listOf(reporter, incident, zone, transcript).filter { it.isNotBlank() && it != "null" }.joinToString(" · "), json.optString("public_url", "").takeIf { it.isNotBlank() })
    }.getOrNull()
}


data class ServerNotificationDelivery(val notificationId: String, val title: String, val body: String, val publicUrl: String?)

/**
 * Delivery bridge for registered emergency-contact accounts. It deliberately runs
 * in event mode's existing foreground service; FCM can replace this poller later
 * without changing the server notification record or Android presentation.
 */
class EmergencyContactNotificationPoller(private val context: Context) {
    private val metadata: Bundle? = context.packageManager.getApplicationInfo(context.packageName, android.content.pm.PackageManager.GET_META_DATA).metaData
    private val baseUrl = metadata?.getString("in.meshsetu.GATEWAY_URL")?.trimEnd('/') ?: ""
    private val recipientUid = metadata?.getString("in.meshsetu.USER_UID")?.takeIf { it.isNotBlank() }
    private val seen = context.getSharedPreferences("meshsetu-notification-deliveries", Context.MODE_PRIVATE)

    suspend fun poll(): List<ServerNotificationDelivery> = withContext(Dispatchers.IO) {
        val uid = recipientUid ?: return@withContext emptyList()
        if (baseUrl.isBlank()) return@withContext emptyList()
        runCatching {
            val connection = URL("$baseUrl/v1/notifications/${Uri.encode(uid)}").openConnection() as HttpURLConnection
            connection.connectTimeout = 5_000; connection.readTimeout = 5_000
            if (connection.responseCode !in 200..299) return@runCatching emptyList()
            val records = org.json.JSONArray(connection.inputStream.bufferedReader().use { it.readText() })
            buildList {
                for (index in 0 until records.length()) {
                    val record = records.getJSONObject(index)
                    val id = record.getString("notification_id")
                    if (seen.getBoolean(id, false)) continue
                    seen.edit().putBoolean(id, true).apply()
                    add(ServerNotificationDelivery(id, record.optString("title", "SOS update"), record.optString("body", "Emergency update received"), record.optString("public_url", "").takeIf { it.isNotBlank() }))
                }
            }
        }.getOrDefault(emptyList())
    }
}
