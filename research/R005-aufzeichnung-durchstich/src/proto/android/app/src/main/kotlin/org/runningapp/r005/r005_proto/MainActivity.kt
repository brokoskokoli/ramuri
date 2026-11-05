package org.runningapp.r005.r005_proto

import android.content.Intent
import android.os.Bundle
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngineCache
import io.flutter.plugin.common.MethodChannel

/** Bindet den vorhandenen Engine; `am start ... --es cmd start ...` reicht Befehle an Dart. */
class MainActivity : FlutterActivity() {
  override fun getCachedEngineId() = R005App.ENGINE
  override fun onCreate(s: Bundle?) { super.onCreate(s); pass(intent) }
  override fun onNewIntent(i: Intent) { super.onNewIntent(i); pass(i) }
  private fun pass(i: Intent?) {
    val ex = i?.extras ?: return
    if (!ex.containsKey("cmd")) return
    val m = HashMap<String, Any?>()
    for (k in ex.keySet()) m[k] = ex.get(k)
    val e = FlutterEngineCache.getInstance().get(R005App.ENGINE) ?: return
    MethodChannel(e.dartExecutor.binaryMessenger, "r005/cmd").invokeMethod("cmd", m)
  }
}
