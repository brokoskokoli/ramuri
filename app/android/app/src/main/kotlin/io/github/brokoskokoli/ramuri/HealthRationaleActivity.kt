package io.github.brokoskokoli.ramuri

import android.app.Activity
import android.app.AlertDialog
import android.content.Intent
import android.os.Bundle

/**
 * ADR-0007 Punkt 5: Ziel von `ACTION_SHOW_PERMISSIONS_RATIONALE` und (über den Alias) von "Berechtigungsnutzung
 * ansehen". Zeigt einen kurzen Erklärungstext (wofür, nur Lesen, lokal, widerrufbar) in einem Systemdialog
 * (Texte in `res/values*`/strings.xml, hell/dunkel nach System) und bietet an, die App zu öffnen, wo die
 * Einstellungen je Datenart liegen (WP32 Teil C2). Die Activity liest und speichert nichts.
 */
class HealthRationaleActivity : Activity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        AlertDialog.Builder(this)
            .setTitle(R.string.health_rationale_title)
            .setMessage(R.string.health_rationale_body)
            .setPositiveButton(R.string.health_rationale_open) { _, _ ->
                startActivity(Intent(this, MainActivity::class.java).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
            }
            .setNegativeButton(R.string.health_rationale_close, null)
            .setOnDismissListener { finish() }
            .show()
    }
}
