package com.example.frontend_student

import ai.onnxruntime.OnnxTensor
import ai.onnxruntime.OrtEnvironment
import ai.onnxruntime.OrtSession
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.Canvas
import android.graphics.ImageFormat
import android.graphics.Matrix
import android.graphics.Paint
import android.graphics.Rect
import android.graphics.YuvImage
import android.os.Handler
import android.os.Looper
import com.google.mediapipe.framework.image.BitmapImageBuilder
import com.google.mediapipe.tasks.core.BaseOptions
import com.google.mediapipe.tasks.vision.core.RunningMode
import com.google.mediapipe.tasks.vision.facelandmarker.FaceLandmarker
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.nio.FloatBuffer
import java.security.KeyPairGenerator
import java.security.KeyStore
import java.security.Signature
import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyProperties
import android.util.Base64
import java.io.ByteArrayOutputStream
import java.util.concurrent.Executors
import kotlin.math.abs
import kotlin.math.max
import kotlin.math.min
import kotlin.math.sqrt

class MainActivity : FlutterActivity() {
    private lateinit var landmarker: FaceLandmarker
    private lateinit var environment: OrtEnvironment
    private lateinit var recognizer: OrtSession
    private val inferenceExecutor = Executors.newSingleThreadExecutor()
    private val mainHandler = Handler(Looper.getMainLooper())

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
            .setMethodCallHandler { call, result ->
                try {
                    inferenceExecutor.execute {
                        try {
                            val value = when (call.method) {
                                "initialize" -> {
                                    initializeModels()
                                    null
                                }
                                "analyzeJpeg" -> analyze(call)
                                "analyzeCameraImage" -> analyzeCameraImage(call)
                                "signMobileFaceNonce" -> signNonce(call)
                                else -> {
                                    mainHandler.post { result.notImplemented() }
                                    return@execute
                                }
                            }
                            mainHandler.post { result.success(value) }
                        } catch (error: Throwable) {
                            // Native ML libraries may be unavailable on an ABI or fail to
                            // load. Report that to Flutter instead of killing the process.
                            mainHandler.post { result.error("FACE_ML_ERROR", error.message ?: "Face ML unavailable", null) }
                        }
                    }
                } catch (error: Throwable) {
                    result.error("FACE_ML_ERROR", error.message ?: "Face ML unavailable", null)
                }
            }
    }

    private fun signNonce(call: MethodCall): Map<String, String> {
        val payload = call.argument<String>("payload")?.toByteArray(Charsets.UTF_8) ?: error("Missing payload")
        val store = KeyStore.getInstance("AndroidKeyStore").apply { load(null) }
        if (!store.containsAlias(DEVICE_KEY_ALIAS)) {
            KeyPairGenerator.getInstance(KeyProperties.KEY_ALGORITHM_EC, "AndroidKeyStore").apply {
                initialize(KeyGenParameterSpec.Builder(DEVICE_KEY_ALIAS, KeyProperties.PURPOSE_SIGN or KeyProperties.PURPOSE_VERIFY)
                    .setDigests(KeyProperties.DIGEST_SHA256).build()); generateKeyPair()
            }
        }
        val privateKey = store.getKey(DEVICE_KEY_ALIAS, null)
        val signature = Signature.getInstance("SHA256withECDSA").apply { initSign(privateKey as java.security.PrivateKey); update(payload) }.sign()
        val certificate = store.getCertificate(DEVICE_KEY_ALIAS).publicKey.encoded
        return mapOf("publicKey" to Base64.encodeToString(certificate, Base64.NO_WRAP), "signature" to Base64.encodeToString(signature, Base64.NO_WRAP))
    }

    private fun initializeModels() {
        if (::landmarker.isInitialized && ::recognizer.isInitialized) return
        if (::landmarker.isInitialized) landmarker.close()
        val options = FaceLandmarker.FaceLandmarkerOptions.builder()
            .setBaseOptions(BaseOptions.builder().setModelAssetPath(LANDMARK_MODEL).build())
            .setRunningMode(RunningMode.IMAGE)
            .setNumFaces(2)
            .setOutputFaceBlendshapes(true)
            .build()
        landmarker = FaceLandmarker.createFromOptions(this, options)
        environment = OrtEnvironment.getEnvironment()
        recognizer = OrtSession.SessionOptions().use { sessionOptions ->
            // Keep model inference from consuming every core and starving the
            // camera preview on lower-end phones.
            sessionOptions.setIntraOpNumThreads(2)
            sessionOptions.setInterOpNumThreads(1)
            environment.createSession(readAsset(RECOGNITION_MODEL), sessionOptions)
        }
    }

    private fun analyze(call: MethodCall): Map<String, Any> {
        initializeModels()
        val jpeg = call.argument<ByteArray>("jpeg") ?: error("Missing JPEG")
        val bitmap = BitmapFactory.decodeByteArray(jpeg, 0, jpeg.size) ?: error("Invalid JPEG")
        return try { analyzeBitmap(bitmap) } finally { bitmap.recycle() }
    }

    private fun analyzeCameraImage(call: MethodCall): Map<String, Any> {
        initializeModels()
        val includeEmbedding = call.argument<Boolean>("includeEmbedding") ?: true
        val width = call.argument<Int>("width") ?: error("Missing image width")
        val height = call.argument<Int>("height") ?: error("Missing image height")
        val rotationDegrees = call.argument<Int>("rotationDegrees") ?: 0
        @Suppress("UNCHECKED_CAST")
        val planes = call.argument<List<Map<String, Any>>>("planes")
            ?: error("Missing camera planes")
        val nv21 = cameraPlanesToNv21(width, height, planes)
        val jpeg = ByteArrayOutputStream().use { output ->
            val encoded = YuvImage(nv21, ImageFormat.NV21, width, height, null)
                .compressToJpeg(Rect(0, 0, width, height), 88, output)
            if (!encoded) error("Could not encode camera frame")
            output.toByteArray()
        }
        val source = BitmapFactory.decodeByteArray(jpeg, 0, jpeg.size)
            ?: error("Invalid camera frame")
        val normalizedRotation = ((rotationDegrees % 360) + 360) % 360
        val bitmap = if (normalizedRotation == 0) {
            source
        } else {
            Bitmap.createBitmap(
                source,
                0,
                0,
                source.width,
                source.height,
                Matrix().apply { postRotate(normalizedRotation.toFloat()) },
                true,
            )
        }
        return try {
            analyzeBitmap(bitmap, includeEmbedding)
        } finally {
            if (bitmap !== source) bitmap.recycle()
            source.recycle()
        }
    }

    private fun cameraPlanesToNv21(
        width: Int,
        height: Int,
        planes: List<Map<String, Any>>,
    ): ByteArray {
        require(width > 0 && height > 0) { "Invalid camera dimensions" }
        require(width % 2 == 0 && height % 2 == 0) { "Camera dimensions must be even" }
        require(planes.isNotEmpty()) { "Camera frame has no planes" }
        val expectedSize = width * height * 3 / 2
        val firstBytes = planes.first()["bytes"] as? ByteArray
            ?: error("Camera plane bytes are missing")
        if (planes.size == 1 && firstBytes.size >= expectedSize) {
            return firstBytes.copyOf(expectedSize)
        }
        require(planes.size >= 3) { "Unsupported camera plane layout" }
        val output = ByteArray(expectedSize)
        copyPlaneToBuffer(
            plane = planes[0],
            planeWidth = width,
            planeHeight = height,
            target = output,
            targetOffset = 0,
            targetPixelStride = 1,
        )
        val chromaWidth = width / 2
        val chromaHeight = height / 2
        copyPlaneToBuffer(
            plane = planes[2],
            planeWidth = chromaWidth,
            planeHeight = chromaHeight,
            target = output,
            targetOffset = width * height,
            targetPixelStride = 2,
        )
        copyPlaneToBuffer(
            plane = planes[1],
            planeWidth = chromaWidth,
            planeHeight = chromaHeight,
            target = output,
            targetOffset = width * height + 1,
            targetPixelStride = 2,
        )
        return output
    }

    private fun copyPlaneToBuffer(
        plane: Map<String, Any>,
        planeWidth: Int,
        planeHeight: Int,
        target: ByteArray,
        targetOffset: Int,
        targetPixelStride: Int,
    ) {
        val bytes = plane["bytes"] as? ByteArray ?: error("Camera plane bytes are missing")
        val rowStride = (plane["bytesPerRow"] as? Number)?.toInt()
            ?: error("Camera row stride is missing")
        val pixelStride = (plane["bytesPerPixel"] as? Number)?.toInt() ?: 1
        require(rowStride > 0 && pixelStride > 0) { "Invalid camera plane stride" }
        for (row in 0 until planeHeight) {
            for (column in 0 until planeWidth) {
                val sourceIndex = row * rowStride + column * pixelStride
                val targetIndex = targetOffset + (row * planeWidth + column) * targetPixelStride
                require(sourceIndex < bytes.size && targetIndex < target.size) { "Incomplete camera frame" }
                target[targetIndex] = bytes[sourceIndex]
            }
        }
    }

    private fun analyzeBitmap(bitmap: Bitmap, includeEmbedding: Boolean = true): Map<String, Any> {
        val result = landmarker.detect(BitmapImageBuilder(bitmap).build())
        if (result.faceLandmarks().size != 1) {
            return mapOf("faceCount" to result.faceLandmarks().size)
        }
        val points = result.faceLandmarks().first()
        val blendshapes = result.faceBlendshapes().orElse(emptyList()).firstOrNull().orEmpty()
        val blink = blendshapes
            .filter { it.categoryName() == "eyeBlinkLeft" || it.categoryName() == "eyeBlinkRight" }
            .map { it.score() }
            .average().takeIf { it.isFinite() } ?: 0.0
        val smile = blendshapes
            .filter { it.categoryName() == "mouthSmileLeft" || it.categoryName() == "mouthSmileRight" }
            .map { it.score() }
            .average().takeIf { it.isFinite() } ?: 0.0
        val noseX = points[1].x()
        val leftSpan = abs(noseX - points[234].x())
        val rightSpan = abs(points[454].x() - noseX)
        // Positive means the nose moves right in the unmirrored camera frame:
        // the person's own left turn. Keep the sign for directional prompts.
        val signedTurn = ((leftSpan - rightSpan) / (leftSpan + rightSpan).coerceAtLeast(1e-6f)).toDouble()
        val turn = abs(signedTurn)
        val bounds = bounds(points.map { floatArrayOf(it.x(), it.y()) })
        val analysis = mutableMapOf<String, Any>(
            "faceCount" to 1,
            "faceSizeRatio" to ((bounds[2] - bounds[0]) * (bounds[3] - bounds[1])).toDouble(),
            "faceCentered" to (bounds[0] >= 0.10f && bounds[1] >= 0.08f && bounds[2] <= 0.90f && bounds[3] <= 0.92f),
            "blinkScore" to blink,
            "smileScore" to smile,
            "turnScore" to turn,
            "signedTurnScore" to signedTurn,
        )
        if (includeEmbedding) {
            val aligned = align(bitmap, points)
            analysis["embedding"] = try { embed(aligned).toList() } finally { aligned.recycle() }
        }
        return analysis
    }

    private fun align(bitmap: Bitmap, landmarks: List<com.google.mediapipe.tasks.components.containers.NormalizedLandmark>): Bitmap {
        val sourceIndexes = intArrayOf(33, 263, 1, 61, 291)
        val target = floatArrayOf(38.2946f, 51.6963f, 73.5318f, 51.5014f, 56.0252f, 71.7366f, 41.5493f, 92.3655f, 70.7299f, 92.2041f)
        val source = FloatArray(10)
        sourceIndexes.forEachIndexed { index, landmarkIndex ->
            source[index * 2] = landmarks[landmarkIndex].x() * bitmap.width
            source[index * 2 + 1] = landmarks[landmarkIndex].y() * bitmap.height
        }
        val transform = similarityTransform(source, target)
        return Bitmap.createBitmap(112, 112, Bitmap.Config.ARGB_8888).also {
            Canvas(it).drawBitmap(bitmap, transform, Paint(Paint.FILTER_BITMAP_FLAG))
        }
    }

    private fun similarityTransform(source: FloatArray, target: FloatArray): Matrix {
        val count = source.size / 2
        val sx = (0 until count).sumOf { source[it * 2].toDouble() } / count
        val sy = (0 until count).sumOf { source[it * 2 + 1].toDouble() } / count
        val tx = (0 until count).sumOf { target[it * 2].toDouble() } / count
        val ty = (0 until count).sumOf { target[it * 2 + 1].toDouble() } / count
        var real = 0.0; var imaginary = 0.0; var energy = 0.0
        for (i in 0 until count) {
            val x = source[i * 2] - sx; val y = source[i * 2 + 1] - sy
            val u = target[i * 2] - tx; val v = target[i * 2 + 1] - ty
            real += x * u + y * v; imaginary += x * v - y * u; energy += x * x + y * y
        }
        require(energy > 1e-8) { "Invalid face landmarks" }
        val a = (real / energy).toFloat(); val b = (imaginary / energy).toFloat()
        return Matrix().apply { setValues(floatArrayOf(a, -b, (tx - a * sx + b * sy).toFloat(), b, a, (ty - b * sx - a * sy).toFloat(), 0f, 0f, 1f)) }
    }

    private fun embed(face: Bitmap): FloatArray {
        val input = FloatArray(1 * 3 * 112 * 112)
        var offset = 0
        for (channel in 0..2) for (y in 0 until 112) for (x in 0 until 112) {
            val pixel = face.getPixel(x, y)
            val value = when (channel) { 0 -> (pixel shr 16) and 0xff; 1 -> (pixel shr 8) and 0xff; else -> pixel and 0xff }
            // This OpenCV Zoo SFace export contains its own normalization.
            // Feeding pre-normalized pixels yields embeddings that do not
            // match OpenCV/desktop enrollment vectors.
            input[offset++] = value.toFloat()
        }
        OnnxTensor.createTensor(environment, FloatBuffer.wrap(input), longArrayOf(1, 3, 112, 112)).use { tensor ->
            recognizer.run(mapOf(recognizer.inputNames.iterator().next() to tensor)).use { output ->
                val vector = (output[0].value as Array<FloatArray>)[0]
                val norm = sqrt(vector.sumOf { (it * it).toDouble() }).toFloat().coerceAtLeast(1e-6f)
                return FloatArray(vector.size) { vector[it] / norm }
            }
        }
    }

    private fun bounds(points: List<FloatArray>): FloatArray {
        var left = 1f; var top = 1f; var right = 0f; var bottom = 0f
        points.forEach { point -> left = min(left, point[0]); top = min(top, point[1]); right = max(right, point[0]); bottom = max(bottom, point[1]) }
        return floatArrayOf(left, top, right, bottom)
    }

    private fun readAsset(name: String): ByteArray = assets.open(name).use { it.readBytes() }

    override fun onDestroy() {
        inferenceExecutor.execute {
            if (::recognizer.isInitialized) recognizer.close()
            if (::landmarker.isInitialized) landmarker.close()
        }
        inferenceExecutor.shutdown()
        super.onDestroy()
    }

    private companion object {
        const val CHANNEL = "com.smartattendance.mobile/face_ml"
        const val LANDMARK_MODEL = "models/face_landmarker.task"
        const val RECOGNITION_MODEL = "models/face_recognition_sface_2021dec.onnx"
        const val DEVICE_KEY_ALIAS = "smartattendance.mobile.face.device.v1"
    }
}
