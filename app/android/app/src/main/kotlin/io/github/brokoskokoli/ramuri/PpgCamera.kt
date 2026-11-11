package io.github.brokoskokoli.ramuri

import android.Manifest
import android.content.Context
import android.content.pm.PackageManager
import android.graphics.ImageFormat
import android.hardware.camera2.CameraCaptureSession
import android.hardware.camera2.CameraCharacteristics
import android.hardware.camera2.CameraDevice
import android.hardware.camera2.CameraManager
import android.hardware.camera2.CaptureRequest
import android.hardware.camera2.params.OutputConfiguration
import android.hardware.camera2.params.SessionConfiguration
import android.media.ImageReader
import android.os.Handler
import android.os.HandlerThread
import android.os.Looper
import android.util.Range
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel

/**
 * Kamera für das Kamera-PPG (ADR-0011): Rückkamera mit Blitz über Camera2 direkt (keine neue
 * Abhängigkeit), YUV 320×240, höchste feste Bildrate (60 vor 30), Torch, Belichtungs- und
 * Weißabgleichsperre nach 2,5 s, Sensor-Zeitstempel. Je Bild geht nur die Statistik an Dart
 * (PpgFrameStats), das Bild wird sofort geschlossen. Keine Bilder und keine Werte in Logs oder auf Platte.
 *
 * Ablauf, Fehlerzuordnung und Beenden stehen in PpgCameraLogic.kt (Unit-Tests); hier nur die Anbindung.
 * Fehler sind Statusereignisse mit Grund, nie ein Absturz. Geht die App in den Hintergrund
 * (MainActivity.onStop) oder tritt ein Fehler auf, endet die Aufnahme: Torch aus, Sitzung und Gerät zu.
 */
object PpgCamera {
    const val METHOD_CHANNEL = "ramuri/ppg_camera"
    const val EVENT_CHANNEL = "ramuri/ppg_camera_stream"

    @Volatile
    private var current: Session? = null

    private fun backCameraId(manager: CameraManager, withFlash: Boolean): String? =
        manager.cameraIdList.firstOrNull { id ->
            val c = manager.getCameraCharacteristics(id)
            c.get(CameraCharacteristics.LENS_FACING) == CameraCharacteristics.LENS_FACING_BACK &&
                (!withFlash || c.get(CameraCharacteristics.FLASH_INFO_AVAILABLE) == true)
        }

    /** Dart: PpgCameraAvailability. Fragt nichts an. */
    fun availability(context: Context): String {
        val manager = context.getSystemService(CameraManager::class.java)
        val (hasBack, hasFlash) = try {
            (manager != null && backCameraId(manager, false) != null) to
                (manager != null && backCameraId(manager, true) != null)
        } catch (_: Exception) {
            false to false
        }
        return PpgCameraLogic.decide(
            hasBackCamera = hasBack,
            hasFlash = hasFlash,
            permissionGranted = context.checkSelfPermission(Manifest.permission.CAMERA) ==
                PackageManager.PERMISSION_GRANTED,
        )
    }

    fun register(messenger: BinaryMessenger, context: Context) {
        MethodChannel(messenger, METHOD_CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "availability" -> result.success(availability(context))
                "stop" -> {
                    current?.controller?.stop()
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }
        EventChannel(messenger, EVENT_CHANNEL).setStreamHandler(Handler(context))
    }

    /** Die App ist nicht mehr sichtbar (MainActivity.onStop): laufende Aufnahme abbrechen. */
    fun onAppBackground() {
        current?.controller?.abort("background")
    }

    private class Handler(private val context: Context) : EventChannel.StreamHandler {
        override fun onListen(arguments: Any?, events: EventChannel.EventSink) {
            current?.controller?.stop()
            val session = Session(context, events)
            current = session
            session.open()
        }

        override fun onCancel(arguments: Any?) {
            current?.controller?.stop()
        }
    }

    private class Session(private val context: Context, events: EventChannel.EventSink) : PpgHardware {
        private val main = android.os.Handler(Looper.getMainLooper())
        private val thread = HandlerThread("ppg-camera").also { it.start() }
        private val handler = android.os.Handler(thread.looper)

        // EventSink nur vom Hauptthread aus; die Reihenfolge bleibt durch post erhalten.
        val controller = PpgController(
            this,
            object : PpgSink {
                override fun event(map: Map<String, Any>) {
                    main.post { events.success(map) }
                }

                override fun end() {
                    main.post { events.endOfStream() }
                }
            },
        )

        private var device: CameraDevice? = null
        private var session: CameraCaptureSession? = null
        private var reader: ImageReader? = null
        private var request: CaptureRequest.Builder? = null
        private var fps = 0

        fun open() {
            val state = availability(context)
            if (state != "available") {
                controller.abort(state)
                return
            }
            try {
                val manager = context.getSystemService(CameraManager::class.java)
                val id = backCameraId(manager, true) ?: return controller.abort("no_flash")
                val chars = manager.getCameraCharacteristics(id)
                fps = PpgCameraLogic.chooseFps(
                    chars.get(CameraCharacteristics.CONTROL_AE_AVAILABLE_TARGET_FPS_RANGES)
                        ?.map { it.lower to it.upper }.orEmpty(),
                ) ?: return controller.abort("frame_rate")
                val sizes = chars.get(CameraCharacteristics.SCALER_STREAM_CONFIGURATION_MAP)
                    ?.getOutputSizes(ImageFormat.YUV_420_888)?.map { it.width to it.height }.orEmpty()
                val (w, h) = PpgCameraLogic.chooseSize(sizes) ?: return controller.abort("error")
                val r = ImageReader.newInstance(w, h, ImageFormat.YUV_420_888, 2)
                reader = r
                r.setOnImageAvailableListener({ onImage(it) }, handler)
                manager.openCamera(id, deviceCallback, handler)
            } catch (e: Throwable) {
                controller.abort(PpgCameraLogic.fromException(e))
            }
        }

        private val deviceCallback = object : CameraDevice.StateCallback() {
            override fun onOpened(d: CameraDevice) {
                device = d
                if (controller.isFinished) {
                    d.close()
                    return
                }
                try {
                    val surface = reader!!.surface
                    d.createCaptureSession(
                        SessionConfiguration(
                            SessionConfiguration.SESSION_REGULAR,
                            listOf(OutputConfiguration(surface)),
                            { handler.post(it) },
                            sessionCallback,
                        ),
                    )
                } catch (e: Throwable) {
                    controller.abort(PpgCameraLogic.fromException(e))
                }
            }

            override fun onDisconnected(d: CameraDevice) = controller.abort("disconnected")

            override fun onError(d: CameraDevice, error: Int) =
                controller.abort(PpgCameraLogic.fromDeviceError(error))
        }

        private val sessionCallback = object : CameraCaptureSession.StateCallback() {
            override fun onConfigured(s: CameraCaptureSession) {
                session = s
                val d = device
                if (controller.isFinished || d == null) {
                    d?.close()
                    return
                }
                try {
                    val b = d.createCaptureRequest(CameraDevice.TEMPLATE_PREVIEW)
                    b.addTarget(reader!!.surface)
                    b.set(CaptureRequest.CONTROL_AE_TARGET_FPS_RANGE, Range(fps, fps))
                    b.set(CaptureRequest.FLASH_MODE, CaptureRequest.FLASH_MODE_TORCH)
                    request = b
                    s.setRepeatingRequest(b.build(), null, handler)
                    controller.started(fps)
                } catch (e: Throwable) {
                    controller.abort(PpgCameraLogic.fromException(e))
                }
            }

            override fun onConfigureFailed(s: CameraCaptureSession) = controller.abort("error")
        }

        private fun onImage(r: ImageReader) {
            val img = try {
                r.acquireLatestImage()
            } catch (_: IllegalStateException) {
                null
            } ?: return
            try {
                val p = img.planes
                controller.frame(
                    img.timestamp,
                    PpgFrameStats.compute(
                        img.width,
                        img.height,
                        PpgPlane(p[0].buffer, p[0].rowStride, p[0].pixelStride),
                        PpgPlane(p[1].buffer, p[1].rowStride, p[1].pixelStride),
                        PpgPlane(p[2].buffer, p[2].rowStride, p[2].pixelStride),
                    ),
                )
            } catch (_: Exception) {
                controller.abort("error")
            } finally {
                img.close()
            }
        }

        override fun lockExposure() {
            val b = request ?: return
            b.set(CaptureRequest.CONTROL_AE_LOCK, true)
            b.set(CaptureRequest.CONTROL_AWB_LOCK, true)
            session?.setRepeatingRequest(b.build(), null, handler)
        }

        override fun torchOff() {
            val b = request ?: return
            b.set(CaptureRequest.FLASH_MODE, CaptureRequest.FLASH_MODE_OFF)
            session?.setRepeatingRequest(b.build(), null, handler)
        }

        override fun closeSession() {
            session?.close()
            session = null
        }

        override fun closeDevice() {
            try {
                device?.close()
            } finally {
                device = null
                try {
                    reader?.close()
                } finally {
                    reader = null
                    thread.quitSafely()
                }
            }
        }
    }
}
