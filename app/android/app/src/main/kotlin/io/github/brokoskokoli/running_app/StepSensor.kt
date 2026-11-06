package io.github.brokoskokoli.running_app

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
    const val METHOD_CHANNEL = "running_app/step_sensor"
    const val EVENT_CHANNEL = "running_app/step_stream"

    /** Dart: CadenceAvailability (available, permissionDenied, noSensor). */
    fun decide(hasSensor: Boolean, permissionGranted: Boolean): String = when {
        !hasSensor -> "no_sensor"
        !permissionGranted -> "permission_denied"
        else -> "available"
    }

    fun availability(context: Context): String = decide(
        hasSensor = context.getSystemService(SensorManager::class.java)
            ?.getDefaultSensor(Sensor.TYPE_STEP_DETECTOR) != null,
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
                    val ageMs = (SystemClock.elapsedRealtimeNanos() - event.timestamp) / 1_000_000L
                    // elapsedMs: Monotonuhr (Zeitbasis des Sensors), für Abstände.
                    // timeMs: Wanduhr, nur zur Anzeige; sie kann umgestellt werden.
                    events.success(
                        mapOf(
                            "timeMs" to System.currentTimeMillis() - ageMs,
                            "elapsedMs" to event.timestamp / 1_000_000L,
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
