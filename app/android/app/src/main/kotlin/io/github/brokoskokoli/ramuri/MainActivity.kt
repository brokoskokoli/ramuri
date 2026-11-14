package io.github.brokoskokoli.ramuri

import android.Manifest
import android.content.Intent
import android.content.pm.PackageManager
import android.location.LocationManager
import android.net.Uri
import android.os.Build
import android.provider.Settings
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    /** Die Engine gehört der Application (ADR-0005 Punkt 1) und überlebt die Activity. */
    override fun getCachedEngineId(): String = RunningApplication.ENGINE_ID

    override fun cleanUpFlutterEngine(flutterEngine: FlutterEngine) {
        // Der Handler hält diese Activity; die Engine bleibt ohne sie bestehen.
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "ramuri/permissions")
            .setMethodCallHandler(null)
        pendingLocation?.error("detached", null, null)
        pendingLocation = null
        pendingNotifications?.error("detached", null, null)
        pendingNotifications = null
        pendingActivity?.error("detached", null, null)
        pendingActivity = null
        pendingCamera?.error("detached", null, null)
        pendingCamera = null
        fileHandoff?.detach()
        fileHandoff = null
        super.cleanUpFlutterEngine(flutterEngine)
    }

    /** FR-0201: Teilen und Speichern starten Systemdialoge, daher an der Activity. */
    private var fileHandoff: FileHandoffChannel? = null

    override fun onResume() {
        super.onResume()
        fileHandoff?.onResume()
    }

    /** ADR-0011 Punkt 6: Nicht mehr sichtbar (Hintergrund, Bildschirm aus): die Kamera-Messung bricht ab. */
    override fun onStop() {
        PpgCamera.onAppBackground()
        super.onStop()
    }

    override fun onPause() {
        fileHandoff?.onPause()
        super.onPause()
    }

    /** Antwort des Dokumentenziels (FileHandoffChannel.save). */
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        if (fileHandoff?.onActivityResult(requestCode, resultCode, data) == true) return
        super.onActivityResult(requestCode, resultCode, data)
    }

    /** Nur Kanäle, die diese Activity braucht; prozessweite hängen in [RunningApplication] an der Engine. */
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        fileHandoff?.detach()
        fileHandoff = FileHandoffChannel(this, flutterEngine.dartExecutor.binaryMessenger)
        // SEC-0007: Stand der Berechtigungen nur lesen; Widerruf im System.
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "ramuri/permissions")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "status" -> result.success(
                        mapOf(
                            "location" to state(Manifest.permission.ACCESS_FINE_LOCATION),
                            "bluetooth" to state(
                                Manifest.permission.BLUETOOTH_SCAN,
                                Manifest.permission.BLUETOOTH_CONNECT,
                            ),
                            "activity_recognition" to state(Manifest.permission.ACTIVITY_RECOGNITION),
                        ),
                    )
                    // Nur gelesen: was das Manifest anfordert (PackageManager), nicht ob es erteilt ist.
                    "requested" -> result.success(requestedKeys())
                    // FR-0217: Version für die Seite "Über" (versionName und versionCode aus dem Build; kein Netz, keine Kennung).
                    "appVersion" -> result.success(runCatching { appVersion() }.getOrNull())
                    // FR-0195: genauer Standort vor dem Lauf (OQ-0064).
                    "locationAccess" -> result.success(locationAccess())
                    "requestLocation" -> requestLocation(result)
                    // ADR-0005 Punkt 2: Die App fragt, läuft aber auch ohne; Antwort blockiert nichts.
                    "requestNotifications" -> requestNotifications(result)
                    // FR-0202: eigene Berechtigung, fragt ohne Sensor nur im Bandmodus (der Dienst braucht sie dort).
                    "requestActivityRecognition" -> requestActivityRecognition(
                        result,
                        call.argument<Boolean>("treadmill") == true,
                    )
                    // ADR-0011 Punkt 5: erst beim Start der Kamera-Messung; Antwort wie PpgCamera.availability.
                    "requestCamera" -> requestCamera(result)
                    "gpsEnabled" -> result.success(
                        (getSystemService(LOCATION_SERVICE) as LocationManager)
                            .isProviderEnabled(LocationManager.GPS_PROVIDER),
                    )
                    "openAppSettings" -> {
                        val intent = Intent(
                            Settings.ACTION_APPLICATION_DETAILS_SETTINGS,
                            Uri.fromParts("package", packageName, null),
                        )
                        startActivity(intent)
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            }
    }

    private var pendingLocation: MethodChannel.Result? = null
    private var pendingNotifications: MethodChannel.Result? = null
    private var pendingActivity: MethodChannel.Result? = null
    private var pendingCamera: MethodChannel.Result? = null

    private fun requestCamera(result: MethodChannel.Result) {
        val state = PpgCamera.availability(this)
        if (state != "permission_denied") {
            result.success(state)
            return
        }
        if (pendingCamera != null) {
            result.error("busy", null, null)
            return
        }
        pendingCamera = result
        requestPermissions(arrayOf(Manifest.permission.CAMERA), CAMERA_REQUEST)
    }

    private fun requestActivityRecognition(result: MethodChannel.Result, treadmill: Boolean) {
        if (!StepSensor.shouldAsk(StepSensor.hasSensor(this), StepSensor.granted(this), treadmill)) {
            result.success(StepSensor.availability(this))
            return
        }
        if (pendingActivity != null) {
            result.error("busy", null, null)
            return
        }
        pendingActivity = result
        requestPermissions(arrayOf(Manifest.permission.ACTIVITY_RECOGNITION), ACTIVITY_REQUEST)
    }

    private fun notificationsGranted(): Boolean =
        Build.VERSION.SDK_INT < 33 ||
            checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) == PackageManager.PERMISSION_GRANTED

    private fun requestNotifications(result: MethodChannel.Result) {
        if (notificationsGranted()) {
            result.success("granted")
            return
        }
        if (pendingNotifications != null) {
            result.error("busy", null, null)
            return
        }
        pendingNotifications = result
        requestPermissions(arrayOf(Manifest.permission.POST_NOTIFICATIONS), NOTIFICATION_REQUEST)
    }

    /** "precise" nur mit ACCESS_FINE_LOCATION; nur COARSE ist "approximate". */
    private fun locationAccess(): String = when {
        checkSelfPermission(Manifest.permission.ACCESS_FINE_LOCATION) == PackageManager.PERMISSION_GRANTED -> "precise"
        checkSelfPermission(Manifest.permission.ACCESS_COARSE_LOCATION) == PackageManager.PERMISSION_GRANTED -> "approximate"
        else -> "denied"
    }

    private fun requestLocation(result: MethodChannel.Result) {
        if (locationAccess() == "precise") {
            result.success("precise")
            return
        }
        if (pendingLocation != null) {
            result.error("busy", null, null)
            return
        }
        pendingLocation = result
        // Ab Android 12 immer beide anfordern; der Nutzer kann "ungefähr" wählen.
        requestPermissions(
            arrayOf(Manifest.permission.ACCESS_FINE_LOCATION, Manifest.permission.ACCESS_COARSE_LOCATION),
            LOCATION_REQUEST,
        )
    }

    override fun onRequestPermissionsResult(requestCode: Int, permissions: Array<String>, grantResults: IntArray) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode == LOCATION_REQUEST) {
            pendingLocation?.success(locationAccess())
            pendingLocation = null
        }
        if (requestCode == ACTIVITY_REQUEST) {
            pendingActivity?.success(StepSensor.availability(this))
            pendingActivity = null
        }
        if (requestCode == CAMERA_REQUEST) {
            pendingCamera?.success(PpgCamera.availability(this))
            pendingCamera = null
        }
        if (requestCode == NOTIFICATION_REQUEST) {
            pendingNotifications?.success(if (notificationsGranted()) "granted" else "denied")
            pendingNotifications = null
        }
    }

    /** `versionName (versionCode)` aus dem installierten Paket. */
    private fun appVersion(): String? {
        val info = if (Build.VERSION.SDK_INT >= 33) {
            packageManager.getPackageInfo(packageName, PackageManager.PackageInfoFlags.of(0L))
        } else {
            @Suppress("DEPRECATION")
            packageManager.getPackageInfo(packageName, 0)
        }
        val name = info.versionName ?: return null
        @Suppress("DEPRECATION")
        val code = if (Build.VERSION.SDK_INT >= 28) info.longVersionCode else info.versionCode.toLong()
        return "$name ($code)"
    }

    /** Schlüssel der Berechtigungen, die das Manifest der App anfordert (Dart: MethodChannelPermissionStatus.keys). */
    private fun requestedKeys(): List<String> {
        val info = if (Build.VERSION.SDK_INT >= 33) {
            packageManager.getPackageInfo(packageName, PackageManager.PackageInfoFlags.of(PackageManager.GET_PERMISSIONS.toLong()))
        } else {
            @Suppress("DEPRECATION")
            packageManager.getPackageInfo(packageName, PackageManager.GET_PERMISSIONS)
        }
        val asked = info.requestedPermissions?.toSet() ?: emptySet()
        val keys = mutableListOf<String>()
        if (Manifest.permission.ACCESS_FINE_LOCATION in asked) keys.add("location")
        if (Manifest.permission.BLUETOOTH_SCAN in asked || Manifest.permission.BLUETOOTH_CONNECT in asked) keys.add("bluetooth")
        if (Manifest.permission.ACTIVITY_RECOGNITION in asked) keys.add("activity_recognition")
        return keys
    }

    /** "granted" nur, wenn alle genannten Berechtigungen erteilt sind. */
    private fun state(vararg permissions: String): String =
        if (permissions.all { checkSelfPermission(it) == PackageManager.PERMISSION_GRANTED }) "granted" else "denied"

    private companion object {
        const val LOCATION_REQUEST = 6001
        const val NOTIFICATION_REQUEST = 6002
        const val ACTIVITY_REQUEST = 6003
        const val CAMERA_REQUEST = 6004
    }
}
