package org.runningapp.r005.r005_host

import android.annotation.SuppressLint
import android.app.KeyguardManager
import android.content.Context
import android.content.Intent
import android.hardware.Sensor
import android.hardware.SensorEvent
import android.hardware.SensorEventListener
import android.hardware.SensorManager
import android.location.Location
import android.location.LocationListener
import android.location.LocationManager
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.os.PowerManager
import android.os.SystemClock
import android.util.Log
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

/** Duenner Adapter: LocationManager/GPS_PROVIDER (ADR-0005 Punkt 4), Wake Lock, Geraetezustand, Schrittsensor. Je Engine eine Instanz. */
class R005HostPlugin : FlutterPlugin, MethodChannel.MethodCallHandler, EventChannel.StreamHandler, LocationListener {
  private lateinit var ctx: Context
  private lateinit var method: MethodChannel
  private lateinit var events: EventChannel
  private var sink: EventChannel.EventSink? = null
  private var wake: PowerManager.WakeLock? = null
  private var stepListener: SensorEventListener? = null

  override fun onAttachedToEngine(b: FlutterPlugin.FlutterPluginBinding) {
    ctx = b.applicationContext
    method = MethodChannel(b.binaryMessenger, "r005/host"); method.setMethodCallHandler(this)
    events = EventChannel(b.binaryMessenger, "r005/location"); events.setStreamHandler(this)
  }
  override fun onDetachedFromEngine(b: FlutterPlugin.FlutterPluginBinding) {
    method.setMethodCallHandler(null); events.setStreamHandler(null)
  }
  override fun onListen(a: Any?, s: EventChannel.EventSink?) { sink = s }
  override fun onCancel(a: Any?) { sink = null }

  override fun onLocationChanged(l: Location) {
    sink?.success(mapOf(
      "lat" to l.latitude, "lon" to l.longitude,
      "tfix_ns" to l.elapsedRealtimeNanos,
      "trecv_ns" to SystemClock.elapsedRealtimeNanos(),
      "trecv_up_ms" to SystemClock.uptimeMillis(),
    ))
  }

  @SuppressLint("MissingPermission", "WakelockTimeout")
  override fun onMethodCall(c: MethodCall, r: MethodChannel.Result) {
    when (c.method) {
      "noBackupDir" -> r.success(ctx.noBackupFilesDir.absolutePath)
      "startService" -> {
        // Der Dienst liegt in der App; Name per Argument, damit das Plugin ihn nicht kennen muss.
        val i = Intent().setClassName(ctx.packageName, c.argument<String>("cls")!!)
        ctx.startForegroundService(i); r.success(true)
      }
      "startLocation" -> {
        val lm = ctx.getSystemService(LocationManager::class.java)
        val ms = (c.argument<Int>("ms") ?: 1000).toLong()
        lm.requestLocationUpdates(LocationManager.GPS_PROVIDER, ms, 0f, this, Looper.getMainLooper())
        r.success(lm.isProviderEnabled(LocationManager.GPS_PROVIDER))
      }
      "wakeLock" -> {
        val on = c.argument<Boolean>("on") == true
        if (on && wake == null) {
          wake = ctx.getSystemService(PowerManager::class.java).newWakeLock(PowerManager.PARTIAL_WAKE_LOCK, "r005:rec").apply { acquire() }
        } else if (!on) { wake?.release(); wake = null }
        r.success(wake?.isHeld == true)
      }
      "state" -> {
        val pm = ctx.getSystemService(PowerManager::class.java)
        val km = ctx.getSystemService(KeyguardManager::class.java)
        r.success(mapOf(
          "elapsed_ms" to SystemClock.elapsedRealtime(), "uptime_ms" to SystemClock.uptimeMillis(),
          "interactive" to pm.isInteractive, "idle" to pm.isDeviceIdleMode, "locked" to km.isDeviceLocked,
          "powersave" to pm.isPowerSaveMode, "sdk" to Build.VERSION.SDK_INT,
          "wakeHeld" to (wake?.isHeld == true),
        ))
      }
      "steps" -> {
        val sm = ctx.getSystemService(SensorManager::class.java)
        val all = sm.getSensorList(Sensor.TYPE_ALL).joinToString(";") { "${it.type}:${it.name}" }
        val st = sm.getDefaultSensor(Sensor.TYPE_STEP_COUNTER)
        val sd = sm.getDefaultSensor(Sensor.TYPE_STEP_DETECTOR)
        Log.i("R005", "R005SENSOR stepCounter=${st != null} stepDetector=${sd != null} all=$all")
        var reg = false
        if (st != null || sd != null) {
          val l = object : SensorEventListener {
            override fun onSensorChanged(e: SensorEvent) { Log.i("R005", "R005STEP type=${e.sensor.type} v=${e.values[0]} t=${e.timestamp}") }
            override fun onAccuracyChanged(s: Sensor?, a: Int) {}
          }
          stepListener = l
          reg = (st != null && sm.registerListener(l, st, SensorManager.SENSOR_DELAY_NORMAL)) or
            (sd != null && sm.registerListener(l, sd, SensorManager.SENSOR_DELAY_NORMAL))
        }
        r.success(mapOf("counter" to (st != null), "detector" to (sd != null), "registered" to reg))
      }
      else -> r.notImplemented()
    }
  }
}
