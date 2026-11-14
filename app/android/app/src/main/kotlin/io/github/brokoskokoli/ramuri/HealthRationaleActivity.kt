package io.github.brokoskokoli.ramuri

import android.app.Activity
import android.content.Intent
import android.os.Bundle

/**
 * ADR-0007 Punkt 5: Ziel von `ACTION_SHOW_PERMISSIONS_RATIONALE` und (über den Alias) von "Berechtigungsnutzung
 * ansehen". Leitet nur in die App weiter; die Erklärung (samt Verweis auf die Datenschutzerklärung) zeigt die Oberfläche (WP32 Teil C/E), nicht diese Activity.
 */
class HealthRationaleActivity : Activity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        startActivity(Intent(this, MainActivity::class.java).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
        finish()
    }
}
