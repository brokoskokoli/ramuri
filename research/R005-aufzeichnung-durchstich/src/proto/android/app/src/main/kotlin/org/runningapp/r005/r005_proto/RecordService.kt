package org.runningapp.r005.r005_proto

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.Service
import android.content.Intent
import android.content.pm.ServiceInfo
import android.os.IBinder
import android.util.Log

/** Duenner Foreground-Service (ADR-0005 Punkt 1-3): haelt nur den Prozess. Logik laeuft im Engine aus R005App. */
class RecordService : Service() {
  override fun onBind(i: Intent?): IBinder? = null
  override fun onStartCommand(i: Intent?, f: Int, id: Int): Int {
    val nm = getSystemService(NotificationManager::class.java)
    nm.createNotificationChannel(NotificationChannel("rec", "Aufzeichnung", NotificationManager.IMPORTANCE_LOW))
    val n = Notification.Builder(this, "rec").setContentTitle("R005").setSmallIcon(android.R.drawable.ic_menu_mylocation).setOngoing(true).build()
    startForeground(1, n, ServiceInfo.FOREGROUND_SERVICE_TYPE_LOCATION)
    Log.i("R005", "R005SVC started type=location")
    return START_NOT_STICKY // ADR-0005 Punkt 6: kein Sticky-Neustart
  }
  override fun onTaskRemoved(r: Intent?) { Log.i("R005", "R005SVC onTaskRemoved"); super.onTaskRemoved(r) }
  override fun onDestroy() { Log.i("R005", "R005SVC onDestroy"); super.onDestroy() }
}
