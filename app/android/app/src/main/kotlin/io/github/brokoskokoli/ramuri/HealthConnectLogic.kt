package io.github.brokoskokoli.ramuri

/**
 * Die sechs Datenarten aus ADR-0007 Punkt 2 mit ihrem Leserecht. Mehr gibt es nicht: Schreibrechte,
 * Hintergrundlesen und alte Daten (READ_HEALTH_DATA_HISTORY) kommen hier nicht vor.
 */
enum class HealthKind(val key: String, val permission: String) {
    EXERCISE("exercise", "android.permission.health.READ_EXERCISE"),
    HEART_RATE("heart_rate", "android.permission.health.READ_HEART_RATE"),
    RESTING_HEART_RATE("resting_heart_rate", "android.permission.health.READ_RESTING_HEART_RATE"),
    HRV_RMSSD("hrv_rmssd", "android.permission.health.READ_HEART_RATE_VARIABILITY"),
    SLEEP("sleep", "android.permission.health.READ_SLEEP"),
    VO2_MAX("vo2_max", "android.permission.health.READ_VO2_MAX");

    companion object {
        fun fromKey(key: String?): HealthKind? = values().firstOrNull { it.key == key }
    }
}

/** Eine Seite Datensätze (Maps mit Zahlen, Text und Listen; nie in ein Log) und das Zeichen für die nächste Seite. */
data class HealthPage(val records: List<Map<String, Any?>>, val nextToken: String?)

/** Fehler mit festem Code; die Meldung trägt nie Inhalte. */
class HealthReadException(val code: String) : Exception(code)

/** Was der Leser von Health Connect braucht; die echte Fassung ist [HealthConnectSource], Tests nehmen eine Attrappe. */
interface HealthSource {
    /** "available", "update_required" oder "unavailable". */
    fun sdkStatus(): String
    fun grantedPermissions(): Set<String>
    fun readPage(kind: HealthKind, fromMs: Long, toMs: Long, pageToken: String?, pageSize: Int): HealthPage
}

/**
 * Liest nur, was der Nutzer für diese Datenart freigegeben hat: vor jedem Lesen werden die erteilten Rechte frisch
 * gefragt (sie können jederzeit entzogen werden, ADR-0007 Punkt 3, SEC-0007). Fehlt das Recht dieser Art, wird die Quelle
 * nicht zum Lesen aufgerufen. Die Ratenbegrenzung hält zwischen zwei Lesevorgängen einen Mindestabstand ein.
 * Nicht für mehrere Threads gedacht; der Aufrufer serialisiert (ein Ausführungsthread).
 */
class HealthReader(
    private val source: HealthSource,
    private val nowMs: () -> Long = System::currentTimeMillis,
    private val sleep: (Long) -> Unit = { Thread.sleep(it) },
    private val minGapMs: Long = MIN_GAP_MS,
) {
    private var lastReadAt: Long? = null

    fun sdkStatus(): String = source.sdkStatus()

    /** Nur die sechs Arten dieses Adapters; fremde Rechte der Quelle werden nicht weitergereicht. */
    fun grantedKeys(): List<String> {
        val granted = source.grantedPermissions()
        return HealthKind.values().filter { it.permission in granted }.map { it.key }
    }

    fun read(kindKey: String?, fromMs: Long?, toMs: Long?, pageToken: String?, pageSize: Int?): HealthPage {
        val kind = HealthKind.fromKey(kindKey) ?: throw HealthReadException("bad_arguments")
        if (fromMs == null || toMs == null || toMs <= fromMs) throw HealthReadException("bad_arguments")
        // Pulsverlauf nur im Zeitfenster einer Einheit (Paket WP32), nie als Dauerpuls.
        if (kind == HealthKind.HEART_RATE && toMs - fromMs > MAX_HEART_RATE_WINDOW_MS) {
            throw HealthReadException("bad_arguments")
        }
        if (kind.permission !in source.grantedPermissions()) throw HealthReadException("permission_missing")
        throttle()
        val size = (pageSize ?: DEFAULT_PAGE_SIZE).coerceIn(1, MAX_PAGE_SIZE)
        return source.readPage(kind, fromMs, toMs, pageToken?.takeIf { it.isNotEmpty() }, size)
    }

    private fun throttle() {
        val last = lastReadAt
        if (last != null) {
            val wait = minGapMs - (nowMs() - last)
            if (wait > 0) sleep(wait)
        }
        lastReadAt = nowMs()
    }

    companion object {
        const val MIN_GAP_MS = 300L
        const val DEFAULT_PAGE_SIZE = 500
        const val MAX_PAGE_SIZE = 1000
        const val MAX_HEART_RATE_WINDOW_MS = 24L * 60 * 60 * 1000
    }
}
