package io.github.brokoskokoli.ramuri

import android.content.Context
import android.graphics.Bitmap
import android.graphics.ImageFormat
import android.graphics.Rect
import android.hardware.camera2.CameraCaptureSession
import android.hardware.camera2.CameraDevice
import android.hardware.camera2.CameraManager
import android.hardware.camera2.CaptureRequest
import android.hardware.camera2.CaptureResult
import android.hardware.camera2.TotalCaptureResult
import android.hardware.camera2.params.OutputConfiguration
import android.hardware.camera2.params.SessionConfiguration
import android.media.ImageReader
import android.os.Handler
import android.os.HandlerThread
import android.os.Looper
import android.os.SystemClock
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.EventChannel
import io.flutter.view.TextureRegistry

/**
 * Kamerasuche (FR-0220, PAR-227; ADR-0011, Nachtrag 2026-11-24): Live-Vorschau mehrerer Rückkameras
 * mit Taschenlampe. Gleichzeitig, wenn alle Kameras physische Kameras derselben logischen Kamera sind
 * und das Gerät die Sitzung bestätigt (isSessionConfigurationSupported), sonst im Wechsel je
 * PpgPreviewLogic.PREVIEW_TURN_NS. Je Kamera ein kleiner YUV-Ausgang: R, G der Bildmitte
 * (PpgFrameStats), Belichtungszeit und ISO aus dem CaptureResult gehen als Zahlen an Dart; das Bild wird
 * nativ verkleinert in eine Flutter-Texture (SurfaceProducer) gezeichnet und sofort verworfen – keine
 * Pixel nach Dart, nichts gespeichert, nichts ins Log. Automatische Belichtung bleibt an.
 *
 * Regeln (Plan, Betriebsart, Reihenfolge und Takt, Nachrichten) stehen in PpgPreviewLogic (Unit-Tests).
 * Fehler einer Kamera gehen als "failed" mit Grund an Dart, nie ein Absturz. Hintergrund
 * (MainActivity.onStop) oder Abbestellen: alles zu, Taschenlampe aus.
 */
object PpgCameraPreview {
    const val EVENT_CHANNEL = "ramuri/ppg_camera_preview"

    @Volatile
    private var current: Search? = null

    fun register(messenger: BinaryMessenger, context: Context, textures: TextureRegistry) {
        EventChannel(messenger, EVENT_CHANNEL).setStreamHandler(
            object : EventChannel.StreamHandler {
                override fun onListen(arguments: Any?, events: EventChannel.EventSink) {
                    current?.finish(null)
                    val s = Search(context, events, textures, PpgPreviewLogic.parseRefs(arguments))
                    current = s
                    s.start()
                }

                override fun onCancel(arguments: Any?) {
                    current?.finish(null)
                    current = null
                }
            },
        )
    }

    /** Die App ist nicht mehr sichtbar: Vorschau beenden, Dart erfährt den Grund "background". */
    fun onAppBackground() {
        current?.finish("background")
        current = null
    }

    /** Eine Vorschau-Sitzung: eine Kamera (Wechsel) oder alle physischen Kameras einer logischen. */
    private class Group(val refs: List<PpgPreviewRef>) {
        var device: CameraDevice? = null
        var session: CameraCaptureSession? = null
        val readers = LinkedHashMap<PpgPreviewRef, ImageReader>()
        val exposureNs = HashMap<PpgPreviewRef, Long?>()
        val iso = HashMap<PpgPreviewRef, Int?>()
        var closed = false
    }

    private class Search(
        private val context: Context,
        private val events: EventChannel.EventSink,
        private val textures: TextureRegistry,
        private val refs: List<PpgPreviewRef>,
    ) {
        private val main = Handler(Looper.getMainLooper())
        private val thread = HandlerThread("ppg-preview").also { it.start() }
        private val handler = Handler(thread.looper)
        private val manager = context.getSystemService(CameraManager::class.java)

        // Nur auf dem Hauptthread: Texturen und das Ende.
        private val producers = LinkedHashMap<PpgPreviewRef, TextureRegistry.SurfaceProducer>()

        @Volatile
        private var finished = false

        // Ab hier nur auf dem Vorschau-Thread.
        private var live: List<PpgPreviewRef> = emptyList()
        private var unit: Group? = null
        private var turn = -1
        private val failed = HashSet<Int>()
        private val startNs = SystemClock.elapsedRealtimeNanos()
        private val pixels = IntArray(PpgPreviewLogic.PREVIEW_WIDTH * PpgPreviewLogic.PREVIEW_HEIGHT)
        private val bitmap = Bitmap.createBitmap(
            PpgPreviewLogic.PREVIEW_WIDTH,
            PpgPreviewLogic.PREVIEW_HEIGHT,
            Bitmap.Config.ARGB_8888,
        )
        private val nextTurn = Runnable { advance() }

        private fun send(map: Map<String, Any?>) {
            main.post { if (!finished) events.success(map) }
        }

        /** Hauptthread: Recht prüfen, Kameras zuordnen, Texturen anlegen, dann auf dem Vorschau-Thread öffnen. */
        fun start() {
            val state = PpgCamera.availability(context)
            if (state != "available" || manager == null) {
                finish(if (state != "available") state else "no_camera")
                return
            }
            val plan = try {
                PpgPreviewLogic.plan(refs, PpgCamera.cameraEntries(manager))
            } catch (_: Exception) {
                PpgPreviewPlan(emptyList(), refs.map { it to "error" })
            }
            plan.failed.forEach { (r, reason) -> send(PpgPreviewLogic.failedMap(r, reason)) }
            if (plan.live.isEmpty()) {
                finish(plan.failed.firstOrNull()?.second ?: "no_camera")
                return
            }
            for (r in plan.live) {
                val p = textures.createSurfaceProducer()
                p.setSize(PpgPreviewLogic.PREVIEW_WIDTH, PpgPreviewLogic.PREVIEW_HEIGHT)
                producers[r] = p
            }
            val ids = producers.mapValues { it.value.id() }
            handler.post {
                live = plan.live
                if (PpgPreviewLogic.canShareSession(live)) {
                    open(Group(live), check = live.size > 1, ids = ids)
                } else {
                    alternate(ids)
                }
            }
        }

        private fun alternate(ids: Map<PpgPreviewRef, Long>) {
            send(PpgPreviewLogic.startedMap("alternating", ids))
            advance()
        }

        /** Wechsel (PAR-227): aktuelle Kamera schließen, die nächste ohne Fehler öffnen; Takt PREVIEW_TURN_NS. */
        private fun advance() {
            if (finished) return
            unit?.let { close(it) }
            unit = null
            val k = PpgPreviewLogic.nextTurn(turn, live.size, failed) ?: return finishFromThread("error")
            turn = k
            send(PpgPreviewLogic.turnMap(live[k]))
            open(Group(listOf(live[k])), check = false, ids = null)
            handler.postDelayed(nextTurn, PpgPreviewLogic.PREVIEW_TURN_NS / 1_000_000L)
        }

        /** Fehler der geöffneten Sitzung: im Wechsel nur diese Kamera, sonst alle. */
        private fun fail(u: Group, reason: String) {
            if (finished || u.closed) return
            close(u)
            if (unit === u) unit = null
            if (u.refs.size == 1 && live.size > 1) {
                send(PpgPreviewLogic.failedMap(u.refs[0], reason))
                failed.add(live.indexOf(u.refs[0]))
                handler.removeCallbacks(nextTurn)
                advance()
            } else {
                u.refs.forEach { send(PpgPreviewLogic.failedMap(it, reason)) }
                finishFromThread(reason)
            }
        }

        /**
         * Öffnet [u] (logische Kamera, je Kamera ein Ausgang). Mit [check] fragt sie vorher
         * isSessionConfigurationSupported; lehnt das Gerät ab, geht es im Wechsel weiter. [ids] gesetzt:
         * erste Sitzung, die "started" (gleichzeitig) meldet.
         */
        private fun open(u: Group, check: Boolean, ids: Map<PpgPreviewRef, Long>?) {
            unit = u
            try {
                val m = manager ?: return fail(u, "error")
                for (r in u.refs) {
                    val chars = m.getCameraCharacteristics(r.physicalCameraId ?: r.cameraId)
                    val sizes = chars.get(android.hardware.camera2.CameraCharacteristics.SCALER_STREAM_CONFIGURATION_MAP)
                        ?.getOutputSizes(ImageFormat.YUV_420_888)?.map { it.width to it.height }.orEmpty()
                    val (w, h) = PpgPreviewLogic.chooseSize(sizes) ?: return fail(u, "error")
                    val reader = ImageReader.newInstance(w, h, ImageFormat.YUV_420_888, 2)
                    reader.setOnImageAvailableListener({ onImage(u, r, it) }, handler)
                    u.readers[r] = reader
                }
                m.openCamera(
                    u.refs[0].cameraId,
                    object : CameraDevice.StateCallback() {
                        override fun onOpened(d: CameraDevice) {
                            u.device = d
                            if (finished || u.closed) return close(u)
                            configure(u, d, check, ids)
                        }

                        override fun onDisconnected(d: CameraDevice) {
                            u.device = d
                            fail(u, "disconnected")
                        }

                        override fun onError(d: CameraDevice, error: Int) {
                            u.device = d
                            fail(u, PpgCameraLogic.fromDeviceError(error))
                        }
                    },
                    handler,
                )
            } catch (e: Throwable) {
                fail(u, PpgCameraLogic.fromException(e))
            }
        }

        private fun configure(u: Group, d: CameraDevice, check: Boolean, ids: Map<PpgPreviewRef, Long>?) {
            try {
                val outputs = u.readers.map { (r, reader) ->
                    OutputConfiguration(reader.surface).also { o -> r.physicalCameraId?.let { o.setPhysicalCameraId(it) } }
                }
                val config = SessionConfiguration(
                    SessionConfiguration.SESSION_REGULAR,
                    outputs,
                    { handler.post(it) },
                    object : CameraCaptureSession.StateCallback() {
                        override fun onConfigured(s: CameraCaptureSession) {
                            u.session = s
                            if (finished || u.closed) return close(u)
                            try {
                                val b = d.createCaptureRequest(CameraDevice.TEMPLATE_PREVIEW)
                                u.readers.values.forEach { b.addTarget(it.surface) }
                                b.set(CaptureRequest.FLASH_MODE, CaptureRequest.FLASH_MODE_TORCH)
                                s.setRepeatingRequest(b.build(), captureCallback(u), handler)
                                if (ids != null) send(PpgPreviewLogic.startedMap("simultaneous", ids))
                            } catch (e: Throwable) {
                                fail(u, PpgCameraLogic.fromException(e))
                            }
                        }

                        override fun onConfigureFailed(s: CameraCaptureSession) = fail(u, "error")
                    },
                )
                if (check) {
                    val supported = try {
                        d.isSessionConfigurationSupported(config)
                    } catch (_: Exception) {
                        false
                    }
                    if (PpgPreviewLogic.previewMode(u.refs, supported) == "alternating") {
                        close(u)
                        unit = null
                        return alternate(ids.orEmpty())
                    }
                }
                d.createCaptureSession(config)
            } catch (e: Throwable) {
                fail(u, PpgCameraLogic.fromException(e))
            }
        }

        private fun captureCallback(u: Group) = object : CameraCaptureSession.CaptureCallback() {
            override fun onCaptureCompleted(s: CameraCaptureSession, r: CaptureRequest, result: TotalCaptureResult) {
                // Je Kamera das eigene Teilergebnis (physische Kamera), sonst das logische.
                for (ref in u.refs) {
                    val source = ref.physicalCameraId?.let { result.physicalCameraTotalResults[it] } ?: result
                    u.exposureNs[ref] = source.get(CaptureResult.SENSOR_EXPOSURE_TIME)
                    u.iso[ref] = source.get(CaptureResult.SENSOR_SENSITIVITY)
                }
            }
        }

        private fun onImage(u: Group, ref: PpgPreviewRef, r: ImageReader) {
            val img = try {
                r.acquireLatestImage()
            } catch (_: IllegalStateException) {
                null
            } ?: return
            try {
                if (finished || u.closed) return
                val p = img.planes
                val y = PpgPlane(p[0].buffer, p[0].rowStride, p[0].pixelStride)
                val cu = PpgPlane(p[1].buffer, p[1].rowStride, p[1].pixelStride)
                val cv = PpgPlane(p[2].buffer, p[2].rowStride, p[2].pixelStride)
                val stats = PpgFrameStats.compute(img.width, img.height, y, cu, cv)
                draw(ref, img.width, img.height, y, cu, cv)
                val t = (SystemClock.elapsedRealtimeNanos() - startNs) / 1e9
                send(PpgPreviewLogic.frameMap(ref, t, stats.r, stats.g, u.exposureNs[ref], u.iso[ref]))
            } catch (_: Exception) {
                fail(u, "error")
            } finally {
                img.close()
            }
        }

        /** Bild verkleinert in die Texture; Pixel und Bitmap bleiben im Speicher dieser Sitzung. */
        private fun draw(ref: PpgPreviewRef, w: Int, h: Int, y: PpgPlane, u: PpgPlane, v: PpgPlane) {
            val producer = producers[ref] ?: return
            val ow = PpgPreviewLogic.PREVIEW_WIDTH
            val oh = PpgPreviewLogic.PREVIEW_HEIGHT
            PpgPreviewLogic.argb(w, h, y, u, v, ow, oh, pixels)
            bitmap.setPixels(pixels, 0, ow, 0, 0, ow, oh)
            val surface = producer.surface
            if (!surface.isValid) return
            val canvas = surface.lockHardwareCanvas()
            try {
                canvas.drawBitmap(bitmap, null, Rect(0, 0, canvas.width, canvas.height), null)
            } finally {
                surface.unlockCanvasAndPost(canvas)
            }
        }

        /** Schließt Sitzung, Gerät (Taschenlampe aus) und Leser einer Sitzung; mehrfach unschädlich. */
        private fun close(u: Group) {
            u.closed = true
            try {
                u.session?.close()
            } catch (_: Exception) {
            }
            u.session = null
            try {
                u.device?.close()
            } catch (_: Exception) {
            }
            u.device = null
            u.readers.values.forEach {
                try {
                    it.close()
                } catch (_: Exception) {
                }
            }
            u.readers.clear()
        }

        private fun finishFromThread(reason: String) {
            main.post { finish(reason) }
        }

        /**
         * Ende (beliebiger Thread): mit [reason] meldet es "stopped" und schließt den Strom, ohne Grund
         * (Abbestellen) nicht. Danach alles zu: Kamera und Taschenlampe, Texturen, Thread.
         */
        fun finish(reason: String?) {
            if (Looper.myLooper() != Looper.getMainLooper()) return finishFromThread(reason ?: return)
            if (finished) return
            if (reason != null) {
                events.success(PpgPreviewLogic.stoppedMap(reason))
                events.endOfStream()
            }
            finished = true
            if (current === this) current = null
            handler.post {
                handler.removeCallbacks(nextTurn)
                unit?.let { close(it) }
                unit = null
                main.post {
                    producers.values.forEach { it.release() }
                    producers.clear()
                }
                thread.quitSafely()
            }
        }
    }
}
