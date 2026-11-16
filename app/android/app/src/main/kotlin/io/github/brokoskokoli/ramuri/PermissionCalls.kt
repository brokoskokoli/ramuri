package io.github.brokoskokoli.ramuri

/** Wirkungen auf den Kanal; die Weiche liegt in [PermissionCalls]. */
interface PermissionAnswers<R> {
    fun success(result: R, value: Any?)
    fun error(result: R, code: String)
}

/**
 * Offene Berechtigungsanfragen je `requestCode` und die Weiche ihrer Antworten,
 * ohne Activity testbar auf der JVM.
 *
 * [health] bekommt jeden Code zuerst (FR-0200, ADR-0007) und meldet, ob er ihm gehört; dann
 * beantwortet kein anderer offener Aufruf. [states] liefert je eigenem Code den Stand, mit dem
 * der offene Aufruf nach dem Dialog beantwortet wird.
 */
class PermissionCalls<R : Any>(
    private val answers: PermissionAnswers<R>,
    private val health: (Int) -> Boolean,
    private val states: Map<Int, () -> Any?>,
) {
    private val pending = LinkedHashMap<Int, R>()

    /** Nimmt den Aufruf als offen auf; `false`, wenn für [requestCode] schon einer offen ist. */
    fun open(requestCode: Int, result: R): Boolean {
        require(requestCode in states) { "unbekannter Code $requestCode" }
        if (requestCode in pending) return false
        pending[requestCode] = result
        return true
    }

    /** Antwort des Systemdialogs; unbekannte Codes und Codes ohne offenen Aufruf tun nichts. */
    fun onRequestPermissionsResult(requestCode: Int) {
        if (health(requestCode)) return
        val state = states[requestCode] ?: return
        val result = pending.remove(requestCode) ?: return
        answers.success(result, state())
    }

    /** Activity löst sich von der Engine: alle offenen Aufrufe in der Reihenfolge von [states] mit `detached` beenden. */
    fun detachAll() {
        val open = states.keys.mapNotNull { code -> pending.remove(code) }
        open.forEach { answers.error(it, "detached") }
    }
}
