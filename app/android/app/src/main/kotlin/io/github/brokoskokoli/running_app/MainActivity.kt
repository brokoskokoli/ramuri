package io.github.brokoskokoli.running_app

import android.Manifest
import android.content.Intent
import android.content.pm.PackageManager
import android.location.LocationManager
import android.net.Uri
import android.os.Build
import android.provider.Settings
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        // ADR-0003 Punkt 3: Die Datenbank liegt in getNoBackupFilesDir(), das immer vom Backup ausgenommen ist.
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "running_app/storage")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "getNoBackupFilesDir" -> result.success(applicationContext.noBackupFilesDir.absolutePath)
                    else -> result.notImplemented()
                }
            }
    
        // SEC-0007: Stand der Berechtigungen nur lesen; Widerruf im System.
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "running_app/permissions")
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
                    // FR-0195: genauer Standort vor dem Lauf (OQ-0064).
                    "locationAccess" -> result.success(locationAccess())
                    "requestLocation" -> requestLocation(result)
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

        // ADR-0005 Punkt 4: GPS_PROVIDER ohne Play-Dienste.
        EventChannel(flutterEngine.dartExecutor.binaryMessenger, "running_app/location_stream")
            .setStreamHandler(GpsStreamHandler(getSystemService(LOCATION_SERVICE) as LocationManager))
    }

    private var pendingLocation: MethodChannel.Result? = null

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
    }
}
