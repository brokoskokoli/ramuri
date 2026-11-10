package io.github.brokoskokoli.ramuri

/**
 * Reine Logik der Erinnerungen (FR-0174), ohne Android: welche fällig sind, welche
 * bleiben und wann der nächste Wecker klingelt. Kotlin-Test: ReminderQueueTest.
 */
object ReminderQueue {
    /** Zu spät zugestellt (Gerät aus, Doze): ältere Erinnerungen entfallen ohne Anzeige. */
    const val STALE_MS = 2 * 60 * 60 * 1000L

    /** Zeitpunkt (ms seit 1970), Titel und Text; der Text nennt nur die Art der Einheit. */
    data class Item(val at: Long, val title: String, val body: String)

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

    /** Kennung der Benachrichtigung je Zeitpunkt (Minute), gleich für dieselbe Erinnerung. */
    fun notificationId(item: Item): Int = (item.at / 60_000L % Int.MAX_VALUE).toInt()
}
