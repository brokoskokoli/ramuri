package org.runningapp.r005.r005_proto

import android.app.Application
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.engine.FlutterEngineCache
import io.flutter.embedding.engine.dart.DartExecutor

/** ADR-0005 Punkt 3: genau ein FlutterEngine im Application-Objekt; ueberlebt jede Activity. */
class R005App : Application() {
  override fun onCreate() {
    super.onCreate()
    val e = FlutterEngine(this)
    e.dartExecutor.executeDartEntrypoint(DartExecutor.DartEntrypoint.createDefault())
    FlutterEngineCache.getInstance().put(ENGINE, e)
  }
  companion object { const val ENGINE = "main" }
}
