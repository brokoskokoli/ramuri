package io.github.brokoskokoli.running_app

import android.annotation.SuppressLint
import android.location.Location
import android.location.LocationListener
import android.location.LocationManager
import android.os.Looper
import io.flutter.plugin.common.EventChannel

/**
 * Standortpunkte vom GPS-Anbieter des Systems (kein Play-Dienst, ADR-0005 Punkt 4).
 * Bewusst dünn: Rohwerte mit `has*`-Flags; was fehlt (null statt 0), entscheidet Dart
 * (adapters/lib/src/location/method_channel_location.dart, getestet).
 */
class GpsStreamHandler(private val manager: LocationManager) : EventChannel.StreamHandler {
    private var listener: LocationListener? = null

    @SuppressLint("MissingPermission") // Fehlende Berechtigung wird als SecurityException gemeldet.
    override fun onListen(arguments: Any?, events: EventChannel.EventSink) {
        // Ein früherer Listener bliebe sonst beim System angemeldet.
        listener?.let { manager.removeUpdates(it) }
        listener = null
        val interval = ((arguments as? Map<*, *>)?.get("intervalMs") as? Number)?.toLong() ?: INTERVAL_MS
        val l = object : LocationListener {
            override fun onLocationChanged(location: Location) = events.success(toEvent(location))
            override fun onProviderDisabled(provider: String) {
                if (provider == LocationManager.GPS_PROVIDER) events.error("provider_disabled", null, null)
            }
            override fun onProviderEnabled(provider: String) {}
        }
        try {
            manager.requestLocationUpdates(LocationManager.GPS_PROVIDER, interval, 0f, l, Looper.getMainLooper())
            listener = l
        } catch (e: SecurityException) {
            events.error("permission_denied", null, null)
        } catch (e: IllegalArgumentException) {
            // Kein GPS-Anbieter auf dem Gerät.
            events.error("provider_disabled", null, null)
        }
    }

    override fun onCancel(arguments: Any?) {
        listener?.let { manager.removeUpdates(it) }
        listener = null
    }

    companion object {
        /** OQ-0064: einmal je Sekunde (Dart: locationIntervalMs). */
        const val INTERVAL_MS = 1000L

        /** Schlüssel stehen in Dart (decodeLocationEvent). */
        fun toEvent(l: Location): Map<String, Any> = mapOf(
            "timeMs" to l.time,
            "lat" to l.latitude,
            "lon" to l.longitude,
            "hasAccuracy" to l.hasAccuracy(),
            "accuracy" to l.accuracy.toDouble(),
            "hasAltitude" to l.hasAltitude(),
            "altitude" to l.altitude,
            "hasSpeed" to l.hasSpeed(),
            "speed" to l.speed.toDouble(),
            "hasSpeedAccuracy" to l.hasSpeedAccuracy(),
            "speedAccuracy" to l.speedAccuracyMetersPerSecond.toDouble(),
            "hasVerticalAccuracy" to l.hasVerticalAccuracy(),
            "verticalAccuracy" to l.verticalAccuracyMeters.toDouble(),
        )
    }
}
