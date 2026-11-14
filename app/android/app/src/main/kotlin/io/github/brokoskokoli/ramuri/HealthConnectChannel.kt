package io.github.brokoskokoli.ramuri

import android.app.Activity
import android.content.Context
import android.content.Intent
import android.os.Handler
import android.os.Looper
import androidx.health.connect.client.HealthConnectClient
import androidx.health.connect.client.PermissionController
import androidx.health.connect.client.records.ExerciseSessionRecord
import androidx.health.connect.client.records.HeartRateRecord
import androidx.health.connect.client.records.HeartRateVariabilityRmssdRecord
import androidx.health.connect.client.records.Record
import androidx.health.connect.client.records.RestingHeartRateRecord
import androidx.health.connect.client.records.SleepSessionRecord
import androidx.health.connect.client.records.Vo2MaxRecord
import androidx.health.connect.client.request.ReadRecordsRequest
import androidx.health.connect.client.time.TimeRangeFilter
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel
import kotlinx.coroutines.runBlocking
import java.io.IOException
import java.time.Instant
import java.time.ZoneOffset
import java.util.concurrent.Executors
import kotlin.reflect.KClass

/**
 * Echte [HealthSource] auf `androidx.health.connect:connect-client` (ADR-0007). Nur Lesen. Jeder Datensatz wird zu einer
 * Map mit der Health-Connect-ID (`id`), Zeiten in Millisekunden (UTC), Werten, Einheit (`unit`) und der Quell-App
 * (`origin` = metadata.dataOrigin.packageName). Die Zuordnung ([toChannelMap]) ist im JVM-Test belegt, am Gerät noch nicht.
 */
class HealthConnectSource(private val context: Context) : HealthSource {
    private val client: HealthConnectClient by lazy { HealthConnectClient.getOrCreate(context) }

    override fun sdkStatus(): String = when (HealthConnectClient.getSdkStatus(context)) {
        HealthConnectClient.SDK_AVAILABLE -> "available"
        HealthConnectClient.SDK_UNAVAILABLE_PROVIDER_UPDATE_REQUIRED -> "update_required"
        else -> "unavailable"
    }

    override fun grantedPermissions(): Set<String> =
        runBlocking { client.permissionController.getGrantedPermissions() }

    override fun readPage(kind: HealthKind, fromMs: Long, toMs: Long, pageToken: String?, pageSize: Int): HealthPage =
        when (kind) {
            HealthKind.EXERCISE -> page(ExerciseSessionRecord::class, fromMs, toMs, pageToken, pageSize)
            HealthKind.HEART_RATE -> page(HeartRateRecord::class, fromMs, toMs, pageToken, pageSize)
            HealthKind.RESTING_HEART_RATE -> page(RestingHeartRateRecord::class, fromMs, toMs, pageToken, pageSize)
            HealthKind.HRV_RMSSD -> page(HeartRateVariabilityRmssdRecord::class, fromMs, toMs, pageToken, pageSize)
            HealthKind.SLEEP -> page(SleepSessionRecord::class, fromMs, toMs, pageToken, pageSize)
            HealthKind.VO2_MAX -> page(Vo2MaxRecord::class, fromMs, toMs, pageToken, pageSize)
        }

    private fun <T : Record> page(
        type: KClass<T>, fromMs: Long, toMs: Long, pageToken: String?, pageSize: Int,
    ): HealthPage {
        val request = ReadRecordsRequest(
            recordType = type,
            timeRangeFilter = TimeRangeFilter.between(Instant.ofEpochMilli(fromMs), Instant.ofEpochMilli(toMs)),
            pageSize = pageSize,
            pageToken = pageToken,
        )
        val response = try {
            runBlocking { client.readRecords(request) }
        } catch (e: SecurityException) {
            throw HealthReadException("permission_missing")
        } catch (e: IOException) {
            throw HealthReadException("unavailable")
        } catch (e: android.os.RemoteException) {
            throw HealthReadException("unavailable")
        } catch (e: IllegalStateException) {
            // Vermutet: Health Connect meldet überschrittene Lese-Limits so; am Gerät noch nicht belegt.
            throw HealthReadException(if (e.message?.contains("limit", ignoreCase = true) == true) "rate_limited" else "error")
        }
        return HealthPage(response.records.map(::toChannelMap), response.pageToken?.takeIf { it.isNotEmpty() })
    }
}

/**
 * Reine Abbildung eines Health-Connect-Records auf die Map des Kanals (Vertrag mit `method_channel_health_connect.dart`).
 * Eigene Funktion, damit sie ohne Gerät getestet werden kann. Eine nicht unterstützte Art ist ein Programmfehler.
 */
internal fun toChannelMap(r: Record): Map<String, Any?> = when (r) {
    is ExerciseSessionRecord -> base(r, r.startTime, r.endTime, r.startZoneOffset) + mapOf(
        "exerciseType" to r.exerciseType.toLong(),
    )
    is HeartRateRecord -> base(r, r.startTime, r.endTime, r.startZoneOffset) + mapOf(
        "unit" to "bpm",
        // [Zeitpunkt in ms, Schläge pro Minute]
        "samples" to r.samples.map { listOf(it.time.toEpochMilli(), it.beatsPerMinute) },
    )
    is RestingHeartRateRecord ->
        base(r, r.time, r.time, r.zoneOffset) + mapOf("value" to r.beatsPerMinute.toDouble(), "unit" to "bpm")
    is HeartRateVariabilityRmssdRecord ->
        base(r, r.time, r.time, r.zoneOffset) + mapOf("value" to r.heartRateVariabilityMillis, "unit" to "ms")
    is SleepSessionRecord -> base(r, r.startTime, r.endTime, r.startZoneOffset) + mapOf(
        // [Beginn in ms, Ende in ms, Phase (SleepSessionRecord.STAGE_TYPE_*)]
        "stages" to r.stages.map { listOf(it.startTime.toEpochMilli(), it.endTime.toEpochMilli(), it.stage.toLong()) },
    )
    is Vo2MaxRecord -> base(r, r.time, r.time, r.zoneOffset) + mapOf(
        "value" to r.vo2MillilitersPerMinuteKilogram,
        "unit" to "ml/min/kg",
        "method" to r.measurementMethod.toLong(),
    )
    else -> throw IllegalArgumentException("unsupported record")
}

private fun base(r: Record, start: Instant, end: Instant, offset: ZoneOffset?): Map<String, Any?> = mapOf(
    "id" to r.metadata.id,
    "origin" to r.metadata.dataOrigin.packageName,
    "startMs" to start.toEpochMilli(),
    "endMs" to end.toEpochMilli(),
    "offsetSeconds" to offset?.totalSeconds?.toLong(),
)

/**
 * Kanal `ramuri/health` (ADR-0007, WP32 Teil A): `sdkStatus`, `grantedKinds`, `requestPermissions` (Dialog von Health
 * Connect über den PermissionController-Vertrag, daher an der Activity) und `readPage`. Alles läuft auf einem eigenen
 * Thread, nie auf dem Hauptthread; Antworten und Fehlercodes tragen keine Gesundheitswerte.
 */
class HealthConnectChannel(
    private val activity: Activity,
    messenger: BinaryMessenger,
    private val reader: HealthReader = HealthReader(HealthConnectSource(activity.applicationContext)),
) {
    private val channel = MethodChannel(messenger, CHANNEL)
    private val main = Handler(Looper.getMainLooper())
    private val contract = PermissionController.createRequestPermissionResultContract()
    private var pending: MethodChannel.Result? = null

    init {
        channel.setMethodCallHandler { call, result ->
            when (call.method) {
                "sdkStatus" -> work(result) { reader.sdkStatus() }
                "grantedKinds" -> work(result) { reader.grantedKeys() }
                "openInstall" -> result.success(openInstall())
                "requestPermissions" -> request(result, call.argument<List<String>>("kinds"))
                "readPage" -> work(result) {
                    val page = reader.read(
                        call.argument<String>("kind"),
                        (call.argument<Any>("fromMs") as? Number)?.toLong(),
                        (call.argument<Any>("toMs") as? Number)?.toLong(),
                        call.argument<String>("pageToken"),
                        (call.argument<Any>("pageSize") as? Number)?.toInt(),
                    )
                    mapOf("records" to page.records, "nextToken" to page.nextToken)
                }
                else -> result.notImplemented()
            }
        }
    }

    private fun work(result: MethodChannel.Result, body: () -> Any?) {
        io.execute {
            try {
                val value = body()
                main.post { result.success(value) }
            } catch (e: HealthReadException) {
                main.post { result.error(e.code, null, null) }
            } catch (e: Exception) {
                // Nie e.message weiterreichen: Es könnte Werte enthalten.
                main.post { result.error("error", null, null) }
            }
        }
    }

    /** Öffnet die Installationsseite im Play Store (market://, dann https); `false`, wenn nichts antwortet. Kein Netzzugriff der App. */
    private fun openInstall(): Boolean {
        for (uri in listOf(INSTALL_MARKET, INSTALL_WEB)) {
            try {
                activity.startActivity(Intent(Intent.ACTION_VIEW, android.net.Uri.parse(uri)))
                return true
            } catch (e: Exception) {
                // nächster Versuch
            }
        }
        return false
    }

    private fun request(result: MethodChannel.Result, keys: List<String>?) {
        val permissions = keys?.map { HealthKind.fromKey(it)?.permission }
        if (permissions == null || permissions.isEmpty() || permissions.any { it == null }) {
            result.error("bad_arguments", null, null)
            return
        }
        if (pending != null) {
            result.error("busy", null, null)
            return
        }
        pending = result
        try {
            @Suppress("DEPRECATION")
            activity.startActivityForResult(contract.createIntent(activity, permissions.filterNotNull().toSet()), REQUEST)
        } catch (e: Exception) {
            pending = null
            result.error("unavailable", null, null)
        }
    }

    /** Antwort des Berechtigungsdialogs; false, wenn der Code nicht zu diesem Kanal gehört. */
    fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?): Boolean {
        if (requestCode != REQUEST) return false
        val result = pending ?: return true
        pending = null
        // Erteilt ist, was Health Connect danach meldet, nicht, was der Dialog zurückgibt.
        work(result) { reader.grantedKeys() }
        return true
    }

    fun detach() {
        channel.setMethodCallHandler(null)
        pending?.error("detached", null, null)
        pending = null
    }

    companion object {
        const val CHANNEL = "ramuri/health"
        const val REQUEST = 6005
        const val INSTALL_MARKET = "market://details?id=com.google.android.apps.healthdata"
        const val INSTALL_WEB = "https://play.google.com/store/apps/details?id=com.google.android.apps.healthdata"
        private val io = Executors.newSingleThreadExecutor { Thread(it, "ramuri-health").apply { isDaemon = true } }
    }
}
