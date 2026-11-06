package io.github.brokoskokoli.running_app

import android.Manifest
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.provider.Settings
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
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

    /** "granted" nur, wenn alle genannten Berechtigungen erteilt sind. */
    private fun state(vararg permissions: String): String =
        if (permissions.all { checkSelfPermission(it) == PackageManager.PERMISSION_GRANTED }) "granted" else "denied"
}
