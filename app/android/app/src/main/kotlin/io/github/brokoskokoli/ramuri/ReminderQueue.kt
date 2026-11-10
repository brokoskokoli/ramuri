package io.github.brokoskokoli.ramuri

/**
 * Reine Logik der Erinnerungen (FR-0174), ohne Android: welche fällig sind, welche
 * bleiben und wann der nächste Wecker klingelt. Kotlin-Test: ReminderQueueTest.
 */
object ReminderQueue {
    /** Zu spät zugestellt (Gerät aus, Doze): ältere Erinnerungen entfallen ohne Anzeige. */
    const val STALE_MS = 2 * 60 * 60 * 1000L

    /**
     * Zeitpunkt (ms seit 1970) und Art der Einheit als Schlüssel (etwa `easy`), sonst nichts:
     * Die Liste liegt außerhalb der verschlüsselten Datenbank (SEC-0009-Ausnahme, WP22 Teil F).
     */
    data class Item(val at: Long, val kind: String)

    /** Ergebnis von [split]: jetzt zeigen, behalten, nächster Wecker (null: keiner). */
    data class Split(val show: List<Item>, val keep: List<Item>, val next: Long?)

    /**
     * Fällig ist, was bis [now] liegt; gezeigt wird davon nur, was höchstens [STALE_MS]
     * zurückliegt. Behalten wird alles nach [now], nach Zeit sortiert.
     */
    fun split(items: List<Item>, now: Long): Split {
        val show = items.filter { it.at <= now && it.at > now - STALE_MS }.sortedBy { it.at }
        val keep = items.filter { it.at > now }.sortedBy { it.at }
        return Split(show, keep, keep.firstOrNull()?.at)
    }

    private val KIND = Regex("^[A-Za-z]{1,32}$")

    /** Gespeicherte Form: je Zeile `<ms> <art>`. Nur Zeitpunkt und Art-Schlüssel. */
    fun encode(items: List<Item>): String {
        require(items.all { KIND.matches(it.kind) }) { "Art-Schlüssel ungültig" }
        return items.joinToString("\n") { "${it.at} ${it.kind}" }
    }

    /** Liest [encode]; unlesbare Zeilen entfallen. */
    fun decode(raw: String?): List<Item> = raw.orEmpty().lineSequence().mapNotNull { line ->
        val parts = line.split(' ')
        val at = parts.getOrNull(0)?.toLongOrNull()
        val kind = parts.getOrNull(1)
        if (parts.size == 2 && at != null && kind != null && KIND.matches(kind)) Item(at, kind) else null
    }.toList()

    /** Kennung der Benachrichtigung je Zeitpunkt (Minute), gleich für dieselbe Erinnerung. */
    fun notificationId(item: Item): Int = (item.at / 60_000L % Int.MAX_VALUE).toInt()
}
