package io.github.brokoskokoli.running_app

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
    }
}
