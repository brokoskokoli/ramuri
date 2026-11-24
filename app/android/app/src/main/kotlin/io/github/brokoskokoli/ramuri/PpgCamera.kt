package io.github.brokoskokoli.ramuri

import android.Manifest
import android.content.Context
import android.content.pm.PackageManager
import android.graphics.ImageFormat
import android.hardware.camera2.CameraCaptureSession
import android.hardware.camera2.CameraCharacteristics
import android.hardware.camera2.CameraDevice
import android.hardware.camera2.CameraManager
import android.hardware.camera2.CaptureResult
import android.hardware.camera2.TotalCaptureResult
import android.hardware.camera2.CaptureRequest
import android.hardware.camera2.params.ColorSpaceTransform
import android.hardware.camera2.params.OutputConfiguration
import android.hardware.camera2.params.RggbChannelVector
import android.hardware.camera2.params.TonemapCurve
import android.hardware.camera2.params.SessionConfiguration
import android.media.ImageReader
import android.os.Build
import android.os.Handler
import android.os.HandlerThread
import android.os.Looper
import android.util.Range
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel

/**
 * Kamera für das Kamera-PPG (ADR-0011): Rückkamera mit Blitz über Camera2 direkt (keine neue
 * Abhängigkeit) – die Standardkamera oder die von Dart angegebene (FR-0220, auch eine physische
 * Kamera einer logischen Mehrfachkamera, Liste über die Methode "cameras") –, YUV 320×240, höchste feste Bildrate (60 vor 30), Torch, Belichtungs- und
 * Weißabgleichsperre nach 2,5 s, Fokus fest und Stabilisierung aus, soweit die Kamera es kann (ADR-0011,
 * Nachtrag 2026-11-21), Antibanding aus und nach 2,5 s die längste Belichtung bei der Bildrate, soweit die
 * Kamera manuelle Belichtung kann (ADR-0011, Nachtrag 2026-11-22), Sensor-Zeitstempel. Je Bild geht nur die Statistik an Dart
 * (PpgFrameStats), das Bild wird sofort geschlossen. Keine Bilder und keine Werte in Logs oder auf Platte.
 * Auf Anforderung (Morgenmessung im Entwicklermodus, FR-0217) gehen je Bild zusätzlich 19 Werte des
 * CaptureResult desselben Bildes mit, und Diagnose-Schalter der Bildverarbeitung werden gesetzt, soweit
 * die Kamera sie anbietet (ADR-0011, Nachtrag 2026-11-21: Diagnose der Bildverarbeitung).
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

    /** Eigenschaften einer Camera2-ID für die Kamerawahl; null, wenn sie nicht lesbar sind. */
    private fun props(manager: CameraManager, id: String): PpgCameraProps? = try {
        val c = manager.getCameraCharacteristics(id)
        val multi = c.get(CameraCharacteristics.REQUEST_AVAILABLE_CAPABILITIES)
            ?.contains(CameraCharacteristics.REQUEST_AVAILABLE_CAPABILITIES_LOGICAL_MULTI_CAMERA) == true
        PpgCameraProps(
            id = id,
            back = c.get(CameraCharacteristics.LENS_FACING) == CameraCharacteristics.LENS_FACING_BACK,
            flash = c.get(CameraCharacteristics.FLASH_INFO_AVAILABLE) == true,
            logicalMulti = multi,
            physicalIds = if (multi) c.physicalCameraIds.toList() else emptyList(),
            focalLengths = c.get(CameraCharacteristics.LENS_INFO_AVAILABLE_FOCAL_LENGTHS)?.toList().orEmpty(),
            fpsRanges = c.get(CameraCharacteristics.CONTROL_AE_AVAILABLE_TARGET_FPS_RANGES)
                ?.map { it.lower to it.upper }.orEmpty(),
            yuvSizes = c.get(CameraCharacteristics.SCALER_STREAM_CONFIGURATION_MAP)
                ?.getOutputSizes(ImageFormat.YUV_420_888)?.map { it.width to it.height }.orEmpty(),
        )
    } catch (_: Exception) {
        null
    }

    /** Fokus- und Stabilisierungs-Characteristics für PpgCameraLogic.lensSettings; was fehlt, ist null. */
    private fun lensProps(c: CameraCharacteristics) = PpgLensProps(
        afModes = c.get(CameraCharacteristics.CONTROL_AF_AVAILABLE_MODES)?.toList(),
        minFocusDistance = c.get(CameraCharacteristics.LENS_INFO_MINIMUM_FOCUS_DISTANCE),
        oisModes = c.get(CameraCharacteristics.LENS_INFO_AVAILABLE_OPTICAL_STABILIZATION)?.toList(),
        videoStabModes = c.get(CameraCharacteristics.CONTROL_AVAILABLE_VIDEO_STABILIZATION_MODES)?.toList(),
    )

    /** Characteristics der Bildverarbeitung für PpgDiagnostics.diagnosticSettings; was fehlt, ist null. */
    private fun ispProps(c: CameraCharacteristics) = PpgIspProps(
        noiseReductionModes = c.get(CameraCharacteristics.NOISE_REDUCTION_AVAILABLE_NOISE_REDUCTION_MODES)?.toList(),
        edgeModes = c.get(CameraCharacteristics.EDGE_AVAILABLE_EDGE_MODES)?.toList(),
        awbModes = c.get(CameraCharacteristics.CONTROL_AWB_AVAILABLE_MODES)?.toList(),
        awbLockAvailable = c.get(CameraCharacteristics.CONTROL_AWB_LOCK_AVAILABLE),
        manualPostProcessing = c.get(CameraCharacteristics.REQUEST_AVAILABLE_CAPABILITIES)
            ?.contains(CameraCharacteristics.REQUEST_AVAILABLE_CAPABILITIES_MANUAL_POST_PROCESSING) == true,
        tonemapModes = c.get(CameraCharacteristics.TONEMAP_AVAILABLE_TONE_MAP_MODES)?.toList(),
        shadingModes = c.get(CameraCharacteristics.SHADING_AVAILABLE_MODES)?.toList(),
    )

    /** Rückkameras samt physischen Kameras (FR-0220, PpgCameraLogic.listCameras). Braucht kein Kamera-Recht. */
    private fun cameraEntries(manager: CameraManager): List<PpgCameraEntry> {
        val cache = HashMap<String, PpgCameraProps?>()
        return PpgCameraLogic.listCameras(manager.cameraIdList.toList()) { id ->
            cache.getOrPut(id) { props(manager, id) }
        }
    }

    /** Dart: PpgCamera.cameras. Fehler ergeben eine leere Liste; nichts davon ins Log. */
    fun cameras(context: Context): List<Map<String, Any?>> = try {
        val manager = context.getSystemService(CameraManager::class.java)
        if (manager == null) emptyList() else cameraEntries(manager).map { it.toMap() }
    } catch (_: Exception) {
        emptyList()
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
                "cameras" -> result.success(cameras(context))
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
            // Argument von PpgCamera.start in Dart: null = Standardkamera, sonst die angegebene Kamera;
            // dazu auf Anforderung Diagnose-Schalter und ISP-Werte je Bild (fehlt = aus, die Vorgabe).
            val args = arguments as? Map<*, *>
            val session = Session(
                context,
                events,
                args?.get("cameraId") as? String,
                args?.get("physicalCameraId") as? String,
                PpgDiagnostic.fromWire(args?.get("diagnostics")),
                args?.get("ispFrames") == true,
            )
            current = session
            session.open()
        }

        override fun onCancel(arguments: Any?) {
            current?.controller?.stop()
        }
    }

    private class Session(
        private val context: Context,
        events: EventChannel.EventSink,
        private val requestedId: String?,
        private val requestedPhysicalId: String?,
        private val requestedDiagnostics: Set<PpgDiagnostic>,
        private val ispFrames: Boolean,
    ) : PpgHardware {
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
            ispFrames,
        )

        // Gerät, Sitzung, Anfrage und Reader gehören dem Kamerathread: Callbacks und onImage laufen
        // dort, die Freigabe (Hauptthread: stop, Hintergrund) wird per PpgCameraThread dorthin gestellt.
        // So schließt reader.close() nie ein gerade gelesenes Bild und die Felder brauchen kein
        // @Volatile. Vor openCamera (Hauptthread) gesetzte Felder werden durch Handler-Post sichtbar.
        private val cameraThread = PpgCameraThread(
            onThread = { Looper.myLooper() == thread.looper },
            post = { handler.post(it) },
        )
        private val threadGuard = PpgThreadGuard { thread.quitSafely() }
        private var device: CameraDevice? = null
        private var session: CameraCaptureSession? = null
        private var reader: ImageReader? = null
        private var request: CaptureRequest.Builder? = null
        private var fps = 0
        private var timestampSource: String? = null
        private var opened: PpgCameraEntry? = null

        // Fokus und Stabilisierung (ADR-0011, Nachtrag 2026-11-21). Nur Zahlen, nie ins Log.
        private var lens: PpgLensSettings? = null

        // Belichtung (ADR-0011, Nachtrag 2026-11-22), aus der Kamera, die die Bilder liefert. Nur Zahlen, nie ins Log.
        private var antibanding: Int? = null
        private var manualSensor = false
        private var exposureRange: Pair<Long, Long>? = null
        private var sensitivityRange: Pair<Int, Int>? = null

        // Belichtung und Empfindlichkeit aus dem letzten Ergebnis der Kamera, die die Bilder liefert
        // (bei einer physischen Kamera deren Teilergebnis, sonst das logische). Nur für die Sperre.
        private var lastExposureNs: Long? = null
        private var lastSensitivity: Int? = null

        // Letzte Angaben der Kamera (Kamerathread schreibt, onImage liest ebenfalls dort). Nur Zahlen, nie ins Log.
        private var capture = PpgCaptureInfo()

        // Diagnose der Bildverarbeitung (ADR-0011, Nachtrag 2026-11-21): gesetzte Schalter, fester
        // Weißabgleich (a) und die Zuordnung der ISP-Werte zum Bild über den Sensor-Zeitstempel.
        private var diagnostics = PpgDiagnosticSettings.NONE
        private val awbFixer = PpgAwbFixer<RggbChannelVector, ColorSpaceTransform>()
        private val matcher = PpgIspMatcher<PpgStats> { ts, stats, isp -> controller.frame(ts, stats, capture, isp) }

        private val captureCallback = object : CameraCaptureSession.CaptureCallback() {
            override fun onCaptureCompleted(s: CameraCaptureSession, r: CaptureRequest, result: TotalCaptureResult) {
                capture = PpgCaptureInfo(
                    exposureNs = result.get(CaptureResult.SENSOR_EXPOSURE_TIME),
                    iso = result.get(CaptureResult.SENSOR_SENSITIVITY),
                    timestampSource = timestampSource,
                    skewNs = result.get(CaptureResult.SENSOR_ROLLING_SHUTTER_SKEW),
                    // FLASH_STRENGTH_LEVEL gibt es erst ab Android 15 (API 35); minSdk ist 31.
                    torch = if (Build.VERSION.SDK_INT >= 35) result.get(CaptureResult.FLASH_STRENGTH_LEVEL) else null,
                )
                // getPhysicalCameraTotalResults gibt es ab API 31 (= minSdk).
                val source = opened?.physicalCameraId?.let { result.physicalCameraTotalResults[it] } ?: result
                lastExposureNs = source.get(CaptureResult.SENSOR_EXPOSURE_TIME)
                lastSensitivity = source.get(CaptureResult.SENSOR_SENSITIVITY)
                // Was das Teilergebnis der physischen Kamera nicht führt, kommt aus dem logischen.
                val value = { key: CaptureResult.Key<*> -> read(source, result, key) }
                val ts = value(CaptureResult.SENSOR_TIMESTAMP) as? Long ?: return
                if (diagnostics.awb == PpgAwbVariant.MATRIX) {
                    awbFixer.offer(
                        ts,
                        value(CaptureResult.CONTROL_AWB_STATE) as? Int,
                        value(CaptureResult.COLOR_CORRECTION_GAINS) as? RggbChannelVector,
                        value(CaptureResult.COLOR_CORRECTION_TRANSFORM) as? ColorSpaceTransform,
                    )?.let { (gains, matrix) -> fixWhiteBalance(gains, matrix) }
                }
                if (ispFrames) matcher.onResult(ts, ispValues(value))
            }
        }

        @Suppress("UNCHECKED_CAST")
        private fun read(source: CaptureResult, result: CaptureResult, key: CaptureResult.Key<*>): Any? {
            val k = key as CaptureResult.Key<Any?>
            return source.get(k) ?: result.get(k)
        }

        /** Die 19 Werte eines Ergebnisses in der Reihenfolge von PpgIspValues (Dart); fehlt = NaN. */
        private fun ispValues(value: (CaptureResult.Key<*>) -> Any?): DoubleArray {
            val g = value(CaptureResult.COLOR_CORRECTION_GAINS) as? RggbChannelVector
            fun n(key: CaptureResult.Key<*>) = value(key) as? Number
            return PpgDiagnostics.pack(
                listOf(
                    g?.red, g?.greenEven, g?.greenOdd, g?.blue,
                    n(CaptureResult.CONTROL_AWB_STATE),
                    n(CaptureResult.CONTROL_AWB_MODE),
                    n(CaptureResult.COLOR_CORRECTION_MODE),
                    n(CaptureResult.NOISE_REDUCTION_MODE),
                    n(CaptureResult.EDGE_MODE),
                    n(CaptureResult.TONEMAP_MODE),
                    n(CaptureResult.SHADING_MODE),
                    n(CaptureResult.SENSOR_EXPOSURE_TIME),
                    n(CaptureResult.SENSOR_SENSITIVITY),
                    n(CaptureResult.CONTROL_AE_STATE),
                    n(CaptureResult.SENSOR_FRAME_DURATION),
                    n(CaptureResult.CONTROL_AF_MODE),
                    n(CaptureResult.LENS_FOCUS_DISTANCE),
                    n(CaptureResult.LENS_OPTICAL_STABILIZATION_MODE),
                    n(CaptureResult.LENS_STATE),
                ),
            )
        }

        /** Weißabgleich (a): AWB aus mit Verstärkungen und Matrix des gewählten Ergebnisses, im selben Builder. */
        private fun fixWhiteBalance(gains: RggbChannelVector, matrix: ColorSpaceTransform) {
            val b = request ?: return
            if (controller.isFinished) return
            try {
                b.set(CaptureRequest.CONTROL_AWB_MODE, CaptureRequest.CONTROL_AWB_MODE_OFF)
                b.set(CaptureRequest.COLOR_CORRECTION_MODE, CaptureRequest.COLOR_CORRECTION_MODE_TRANSFORM_MATRIX)
                b.set(CaptureRequest.COLOR_CORRECTION_GAINS, gains)
                b.set(CaptureRequest.COLOR_CORRECTION_TRANSFORM, matrix)
                session?.setRepeatingRequest(b.build(), captureCallback, handler)
            } catch (e: Throwable) {
                controller.abort(PpgCameraLogic.fromException(e))
            }
        }

        fun open() {
            val state = availability(context)
            if (state != "available") {
                controller.abort(state)
                return
            }
            try {
                val manager = context.getSystemService(CameraManager::class.java)
                // Genau die angegebene Kamera, ohne Angabe die Standardkamera; nie eine andere.
                val pick = PpgCameraLogic.pick(cameraEntries(manager), requestedId, requestedPhysicalId)
                pick.reason?.let { return controller.abort(it) }
                val target = pick.entry ?: return controller.abort("error")
                opened = target
                val id = target.cameraId
                // Bildrate und Größe aus der Kamera, die die Bilder liefert (physische Kamera, wenn angegeben).
                val chars = manager.getCameraCharacteristics(target.physicalCameraId ?: id)
                val logical = manager.getCameraCharacteristics(id)
                timestampSource = PpgCaptureInfo.sourceName(
                    logical.get(CameraCharacteristics.SENSOR_INFO_TIMESTAMP_SOURCE),
                )
                // AF-Modi und Stabilisierung von der Kamera, an die die Anfrage geht; die kürzeste
                // Distanz von der Kamera, die die Bilder liefert (FR-0220).
                // Diagnose-Schalter nach der Kamera, an die die Anfrage geht; ohne Anforderung NONE.
                diagnostics = if (requestedDiagnostics.isEmpty()) {
                    PpgDiagnosticSettings.NONE
                } else {
                    PpgDiagnostics.diagnosticSettings(requestedDiagnostics, ispProps(logical))
                }
                lens = PpgCameraLogic.lensSettings(
                    lensProps(logical),
                    if (target.physicalCameraId != null) lensProps(chars) else null,
                )
                // Antibanding und manuelle Belichtung nach der Kamera, die die Bilder liefert (FR-0220).
                antibanding = PpgCameraLogic.antibandingMode(
                    chars.get(CameraCharacteristics.CONTROL_AE_AVAILABLE_ANTIBANDING_MODES)?.toList(),
                )
                manualSensor = chars.get(CameraCharacteristics.REQUEST_AVAILABLE_CAPABILITIES)
                    ?.contains(CameraCharacteristics.REQUEST_AVAILABLE_CAPABILITIES_MANUAL_SENSOR) == true
                exposureRange = chars.get(CameraCharacteristics.SENSOR_INFO_EXPOSURE_TIME_RANGE)
                    ?.let { it.lower to it.upper }
                sensitivityRange = chars.get(CameraCharacteristics.SENSOR_INFO_SENSITIVITY_RANGE)
                    ?.let { it.lower to it.upper }
                // Dieselbe Rate wie in der Kameraliste (PpgCameraLogic.chooseFps über die Eigenschaften
                // der Kamera, die die Bilder liefert).
                fps = target.frameRate ?: return controller.abort("frame_rate")
                val sizes = chars.get(CameraCharacteristics.SCALER_STREAM_CONFIGURATION_MAP)
                    ?.getOutputSizes(ImageFormat.YUV_420_888)?.map { it.width to it.height }.orEmpty()
                val (w, h) = PpgCameraLogic.chooseSize(sizes) ?: return controller.abort("error")
                val r = ImageReader.newInstance(w, h, ImageFormat.YUV_420_888, 2)
                reader = r
                r.setOnImageAvailableListener({ onImage(it) }, handler)
                threadGuard.openRequested()
                try {
                    manager.openCamera(id, deviceCallback, handler)
                } catch (e: Throwable) {
                    threadGuard.openSettled()
                    throw e
                }
            } catch (e: Throwable) {
                controller.abort(PpgCameraLogic.fromException(e))
            }
        }

        private val deviceCallback = object : CameraDevice.StateCallback() {
            override fun onOpened(d: CameraDevice) {
                device = d
                if (controller.isFinished) {
                    // Beendet, bevor das Gerät aufging: jetzt schließen (der Torch war nie an), dann erst den Thread beenden.
                    try {
                        d.close()
                    } finally {
                        device = null
                        threadGuard.openSettled()
                    }
                    return
                }
                threadGuard.openSettled()
                try {
                    val surface = reader!!.surface
                    // Physische Kamera: Bilder dieses Objektivs über die logische Kamera; Taschenlampe,
                    // Belichtungs- und Weißabgleichsperre wie bisher über deren Anfrage. Kann die Kamera
                    // den Ausgang nicht liefern, endet die Aufnahme über onConfigureFailed mit "error".
                    val output = OutputConfiguration(surface)
                    opened?.physicalCameraId?.let { output.setPhysicalCameraId(it) }
                    d.createCaptureSession(
                        SessionConfiguration(
                            SessionConfiguration.SESSION_REGULAR,
                            listOf(output),
                            { handler.post(it) },
                            sessionCallback,
                        ),
                    )
                } catch (e: Throwable) {
                    controller.abort(PpgCameraLogic.fromException(e))
                }
            }

            override fun onDisconnected(d: CameraDevice) {
                settleAndClose(d)
                controller.abort("disconnected")
            }

            override fun onError(d: CameraDevice, error: Int) {
                settleAndClose(d)
                controller.abort(PpgCameraLogic.fromDeviceError(error))
            }

            /** Das Gerät ist unbrauchbar (auch vor onOpened): schließen, dann darf der Thread enden. */
            private fun settleAndClose(d: CameraDevice) {
                try {
                    d.close()
                } catch (_: Exception) {
                } finally {
                    threadGuard.openSettled()
                }
            }
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
                    // Schon in der ersten Anfrage; lockExposure und torchOff nutzen denselben Builder
                    // und behalten die Werte. Nie ein CONTROL_AF_TRIGGER.
                    applyLens(b)
                    antibanding?.let { b.set(CaptureRequest.CONTROL_AE_ANTIBANDING_MODE, it) }
                    applyDiagnostics(b)
                    request = b
                    s.setRepeatingRequest(b.build(), captureCallback, handler)
                    val o = opened!!
                    controller.started(fps, o.cameraId, o.physicalCameraId, diagnostics)
                } catch (e: Throwable) {
                    controller.abort(PpgCameraLogic.fromException(e))
                }
            }

            override fun onConfigureFailed(s: CameraCaptureSession) = controller.abort("error")
        }

        /**
         * Fokus und Stabilisierung auf der Anfrage der geöffneten (logischen) Kamera, wie Bildrate, Torch
         * und Sperren (ADR-0011, Nachtrag 2026-11-18). Keine Anfrage mit physischen Schlüsseln: bei ihr
         * bekäme die physische Kamera für jeden ihrer physischen Anfrage-Schlüssel die Werte der Vorlage,
         * nicht die hier gesetzten.
         */
        private fun applyLens(b: CaptureRequest.Builder) {
            val l = lens ?: return
            l.afMode?.let { b.set(CaptureRequest.CONTROL_AF_MODE, it) }
            l.focusDistance?.let { b.set(CaptureRequest.LENS_FOCUS_DISTANCE, it) }
            l.oisMode?.let { b.set(CaptureRequest.LENS_OPTICAL_STABILIZATION_MODE, it) }
            l.videoStabMode?.let { b.set(CaptureRequest.CONTROL_VIDEO_STABILIZATION_MODE, it) }
        }

        /**
         * Diagnose-Schalter (nur die angebotenen, PpgDiagnostics.diagnosticSettings); alle aus setzt
         * nichts. Weißabgleich (b) sperrt ab der ersten Anfrage, (a) folgt in fixWhiteBalance.
         */
        private fun applyDiagnostics(b: CaptureRequest.Builder) {
            val d = diagnostics
            d.noiseReductionMode?.let { b.set(CaptureRequest.NOISE_REDUCTION_MODE, it) }
            d.edgeMode?.let { b.set(CaptureRequest.EDGE_MODE, it) }
            d.tonemapMode?.let { b.set(CaptureRequest.TONEMAP_MODE, it) }
            d.tonemapCurve?.let { b.set(CaptureRequest.TONEMAP_CURVE, TonemapCurve(it, it.copyOf(), it.copyOf())) }
            d.shadingMode?.let { b.set(CaptureRequest.SHADING_MODE, it) }
            if (d.awb == PpgAwbVariant.LOCK) b.set(CaptureRequest.CONTROL_AWB_LOCK, true)
        }

        private fun onImage(r: ImageReader) {
            val img = try {
                r.acquireLatestImage()
            } catch (_: IllegalStateException) {
                null
            } ?: return
            try {
                val p = img.planes
                val stats = PpgFrameStats.compute(
                    img.width,
                    img.height,
                    PpgPlane(p[0].buffer, p[0].rowStride, p[0].pixelStride),
                    PpgPlane(p[1].buffer, p[1].rowStride, p[1].pixelStride),
                    PpgPlane(p[2].buffer, p[2].rowStride, p[2].pixelStride),
                )
                // Mit ISP-Werten wartet das Bild auf das Ergebnis mit demselben Zeitstempel.
                if (ispFrames) matcher.onFrame(img.timestamp, stats) else controller.frame(img.timestamp, stats, capture)
            } catch (_: Exception) {
                controller.abort("error")
            } finally {
                img.close()
            }
        }

        /**
         * Sperre nach der Einschwingzeit im selben Builder (Torch, Fokus, Stabilisierung und Antibanding
         * bleiben): manuell mit längster Belichtung bei der Bildrate, wenn die Kamera es kann
         * (PpgCameraLogic.exposureLock), sonst die AE-Sperre. Weißabgleich immer gesperrt. Ohne
         * Automatik gilt CONTROL_AE_TARGET_FPS_RANGE nicht mehr; die Bilddauer hält die Rate.
         */
        override fun lockExposure() = cameraThread.run {
            val b = request ?: return@run
            when (
                val lock = PpgCameraLogic.exposureLock(
                    fps, lastExposureNs, lastSensitivity, exposureRange, sensitivityRange, manualSensor,
                )
            ) {
                is PpgExposureLock.Manual -> {
                    b.set(CaptureRequest.CONTROL_AE_MODE, CaptureRequest.CONTROL_AE_MODE_OFF)
                    b.set(CaptureRequest.SENSOR_EXPOSURE_TIME, lock.exposureNs)
                    b.set(CaptureRequest.SENSOR_SENSITIVITY, lock.sensitivity)
                    b.set(CaptureRequest.SENSOR_FRAME_DURATION, lock.frameDurationNs)
                }
                PpgExposureLock.AeLock -> b.set(CaptureRequest.CONTROL_AE_LOCK, true)
            }
            b.set(CaptureRequest.CONTROL_AWB_LOCK, true)
            session?.setRepeatingRequest(b.build(), captureCallback, handler)
        }

        /**
         * Neu einschwingen nach einem Helligkeitssprung (PAR-246): zurück auf die Automatik der ersten
         * Phase im selben Builder (Torch, Fokus, Stabilisierung, Antibanding und Diagnose-Schalter bleiben).
         * Setzt beide Arten der Sperre zurück: AE wieder an (die manuellen Werte gelten dann nicht) und
         * ohne AE-Sperre; der Weißabgleich wieder frei, außer der Diagnose-Schalter sperrt ihn ab Start.
         * Die neue Sperre kommt danach mit lockExposure.
         */
        override fun unlockExposure() = cameraThread.run {
            val b = request ?: return@run
            b.set(CaptureRequest.CONTROL_AE_MODE, CaptureRequest.CONTROL_AE_MODE_ON)
            b.set(CaptureRequest.CONTROL_AE_LOCK, false)
            b.set(CaptureRequest.CONTROL_AWB_LOCK, diagnostics.awb == PpgAwbVariant.LOCK)
            session?.setRepeatingRequest(b.build(), captureCallback, handler)
        }

        override fun torchOff() = cameraThread.run {
            val b = request ?: return@run
            b.set(CaptureRequest.FLASH_MODE, CaptureRequest.FLASH_MODE_OFF)
            session?.setRepeatingRequest(b.build(), captureCallback, handler)
        }

        override fun closeSession() = cameraThread.run {
            session?.close()
            session = null
        }

        // Zuletzt: Gerät und Reader schließen, dann den Thread beenden (quitSafely arbeitet die vorher
        // gestellten Schritte noch ab); steht openCamera noch aus, beendet ihn erst onOpened/onError.
        override fun closeDevice() = cameraThread.run {
            try {
                device?.close()
            } finally {
                device = null
                try {
                    reader?.close()
                } finally {
                    reader = null
                    threadGuard.quitWhenIdle()
                }
            }
        }
    }
}
