package io.github.brokoskokoli.ramuri

import android.Manifest
import android.content.Context
import android.content.pm.PackageManager
import android.hardware.Sensor
import android.hardware.SensorEvent
import android.hardware.SensorEventListener
import android.hardware.SensorManager
import android.os.SystemClock
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel

/**
 * Schrittsensor des Telefons (FR-0202) als prozessweiter Kanal an der Engine.
 * Bewusst dünn: Kotlin meldet nur den Zeitpunkt jedes Schritts, die Schrittfrequenz
 * rechnet Dart (core, CadenceEstimator, getestet).
 *
 * TYPE_STEP_DETECTOR statt TYPE_STEP_COUNTER: Der Detektor liefert je Schritt ein
 * Ereignis mit Zeitstempel, daraus folgt die Frequenz in einem Fenster ohne
 * Bezugswert (der Zähler zählt seit dem Systemstart und liefert gebündelt).
 * Beide brauchen ACTIVITY_RECOGNITION. Kein Foreground-Typ `health`.
 */
object StepSensor {
    const val METHOD_CHANNEL = "ramuri/step_sensor"
    const val EVENT_CHANNEL = "ramuri/step_stream"

    /** Dart: CadenceAvailability (available, permissionDenied, noSensor). */
    fun decide(hasSensor: Boolean, permissionGranted: Boolean): String = when {
        !hasSensor -> "no_sensor"
        !permissionGranted -> "permission_denied"
        else -> "available"
    }

    /**
     * Nachricht an Dart für einen Schritt. elapsedMs: Monotonuhr (Zeitbasis des Sensors,
     * elapsedRealtimeNanos), für Abstände. timeMs: Wanduhr abzüglich Alter des Ereignisses,
     * nur zur Anzeige; sie kann umgestellt werden.
     */
    fun stepEvent(wallMs: Long, nowNs: Long, eventNs: Long): Map<String, Long> = mapOf(
        "timeMs" to wallMs - (nowNs - eventNs) / 1_000_000L,
        "elapsedMs" to eventNs / 1_000_000L,
    )

    /**
     * Ob die Berechtigungsabfrage erscheint. Im Bandmodus braucht der Dienst das Recht
     * (Diensttyp health) auch ohne Schrittsensor; sonst fragt nur, wer einen Sensor hat (FR-0202).
     */
    fun shouldAsk(hasSensor: Boolean, permissionGranted: Boolean, treadmill: Boolean): Boolean =
        !permissionGranted && (hasSensor || treadmill)

    fun hasSensor(context: Context): Boolean = context.getSystemService(SensorManager::class.java)
        ?.getDefaultSensor(Sensor.TYPE_STEP_DETECTOR) != null

    fun granted(context: Context): Boolean =
        context.checkSelfPermission(Manifest.permission.ACTIVITY_RECOGNITION) == PackageManager.PERMISSION_GRANTED

    fun availability(context: Context): String = decide(
        hasSensor = hasSensor(context),
        permissionGranted = context.checkSelfPermission(Manifest.permission.ACTIVITY_RECOGNITION) ==
            PackageManager.PERMISSION_GRANTED,
    )

    fun register(messenger: BinaryMessenger, context: Context) {
        MethodChannel(messenger, METHOD_CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "availability" -> result.success(availability(context))
                else -> result.notImplemented()
            }
        }
        EventChannel(messenger, EVENT_CHANNEL).setStreamHandler(Handler(context))
    }

    /** Schrittzeitpunkte; Zeit der Wanduhr = jetzt minus Alter auf der Monotonuhr. */
    private class Handler(private val context: Context) : EventChannel.StreamHandler {
        private var listener: SensorEventListener? = null

        override fun onListen(arguments: Any?, events: EventChannel.EventSink) {
            onCancel(null)
            val state = availability(context)
            if (state != "available") {
                events.error(state, null, null)
                return
            }
            val manager = context.getSystemService(SensorManager::class.java)
            val sensor = manager.getDefaultSensor(Sensor.TYPE_STEP_DETECTOR)
            val l = object : SensorEventListener {
                override fun onSensorChanged(event: SensorEvent) {
                    events.success(
                        stepEvent(
                            wallMs = System.currentTimeMillis(),
                            nowNs = SystemClock.elapsedRealtimeNanos(),
                            eventNs = event.timestamp,
                        ),
                    )
                }

                override fun onAccuracyChanged(sensor: Sensor?, accuracy: Int) {}
            }
            // Verzögerung 0: keine Bündelung, damit die Anzeige live bleibt.
            if (manager.registerListener(l, sensor, SensorManager.SENSOR_DELAY_NORMAL, 0)) {
                listener = l
            } else {
                events.error("no_sensor", null, null)
            }
        }

        override fun onCancel(arguments: Any?) {
            listener?.let { context.getSystemService(SensorManager::class.java).unregisterListener(it) }
            listener = null
        }
    }
}
