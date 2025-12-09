package com.example.platedepth

import android.content.Context
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.ImageFormat
import android.graphics.Matrix
import android.graphics.Rect
import android.graphics.YuvImage
import android.util.Log
import android.util.Size
import android.view.Surface
import androidx.camera.core.CameraSelector
import androidx.camera.core.ImageAnalysis
import androidx.camera.core.ImageCapture
import androidx.camera.core.ImageCaptureException
import androidx.camera.core.ImageProxy
import androidx.camera.core.Preview
import androidx.camera.lifecycle.ProcessCameraProvider
import androidx.core.content.ContextCompat
import androidx.lifecycle.LifecycleOwner
import io.flutter.view.TextureRegistry
import java.io.ByteArrayOutputStream
import java.io.File
import java.io.FileOutputStream
import java.util.concurrent.ExecutorService
import java.util.concurrent.Executors
import kotlin.math.max
import kotlin.math.min

class NativeCameraController(private val context: Context) {
    companion object {
        private const val TAG = "NativeCameraController"
        private const val MASK_WIDTH = 512
        private const val MASK_HEIGHT = 512
    }

    private var cameraProvider: ProcessCameraProvider? = null
    private var imageCapture: ImageCapture? = null
    private var imageAnalysis: ImageAnalysis? = null
    private var preview: Preview? = null
    private var textureEntry: TextureRegistry.SurfaceTextureEntry? = null
    private val cameraExecutor: ExecutorService = Executors.newSingleThreadExecutor()
    
    private var latestBitmap: Bitmap? = null
    private var latestWidth: Int = 0
    private var latestHeight: Int = 0
    private var latestLaplacian: Double = 0.0
    
    // EdgeSAM for segmentation
    private val edgeSAM = EdgeSAMBridge(context)
    private var hasEncodedImage = false
    
    fun hasEdgeSAM(): Boolean = edgeSAM.hasModels

    fun initialize(
        textureRegistry: TextureRegistry,
        lifecycleOwner: LifecycleOwner,
        callback: (Long?, String?) -> Unit
    ) {
        val cameraProviderFuture = ProcessCameraProvider.getInstance(context)
        
        cameraProviderFuture.addListener({
            try {
                cameraProvider = cameraProviderFuture.get()
                
                // Create texture entry for Flutter
                textureEntry = textureRegistry.createSurfaceTexture()
                val textureId = textureEntry!!.id()
                val surfaceTexture = textureEntry!!.surfaceTexture()
                surfaceTexture.setDefaultBufferSize(1920, 1080)
                
                // Build preview use case
                preview = Preview.Builder()
                    .setTargetResolution(Size(1920, 1080))
                    .build()
                    .also {
                        it.setSurfaceProvider { request ->
                            val surface = Surface(surfaceTexture)
                            request.provideSurface(surface, cameraExecutor) { result ->
                                // Surface provided
                            }
                        }
                    }
                
                // Build image capture use case
                imageCapture = ImageCapture.Builder()
                    .setCaptureMode(ImageCapture.CAPTURE_MODE_MAXIMIZE_QUALITY)
                    .setTargetResolution(Size(1920, 1080))
                    .build()
                
                // Build image analysis for live preview frame access
                imageAnalysis = ImageAnalysis.Builder()
                    .setTargetResolution(Size(640, 480))
                    .setBackpressureStrategy(ImageAnalysis.STRATEGY_KEEP_ONLY_LATEST)
                    .build()
                
                callback(textureId, null)
            } catch (e: Exception) {
                Log.e(TAG, "Camera initialization failed", e)
                callback(null, e.message ?: "Unknown error")
            }
        }, ContextCompat.getMainExecutor(context))
    }

    fun startStream(lifecycleOwner: LifecycleOwner, callback: (String?) -> Unit) {
        try {
            val provider = cameraProvider
            if (provider == null) {
                callback("Camera not initialized")
                return
            }
            
            // Unbind all use cases before rebinding
            provider.unbindAll()
            
            // Select back camera
            val cameraSelector = CameraSelector.DEFAULT_BACK_CAMERA
            
            // Bind use cases to camera
            provider.bindToLifecycle(
                lifecycleOwner,
                cameraSelector,
                preview,
                imageCapture,
                imageAnalysis
            )
            
            callback(null)
        } catch (e: Exception) {
            Log.e(TAG, "Failed to start camera stream", e)
            callback(e.message ?: "Unknown error")
        }
    }

    fun captureFrame(callback: (Map<String, Any>?, String?) -> Unit) {
        val capture = imageCapture
        if (capture == null) {
            callback(null, "Camera not initialized")
            return
        }
        
        val tempDir = context.cacheDir
        val imageFile = File(tempDir, "capture.jpg")
        val depthFile = File(tempDir, "depth_map.tif")
        
        val outputOptions = ImageCapture.OutputFileOptions.Builder(imageFile).build()
        
        capture.takePicture(
            outputOptions,
            cameraExecutor,
            object : ImageCapture.OnImageSavedCallback {
                override fun onImageSaved(output: ImageCapture.OutputFileResults) {
                    try {
                        // Load the captured image
                        val bitmap = BitmapFactory.decodeFile(imageFile.absolutePath)
                        latestBitmap?.recycle()
                        latestBitmap = bitmap
                        latestWidth = bitmap.width
                        latestHeight = bitmap.height
                        
                        // Calculate Laplacian variance for blur detection
                        latestLaplacian = BlurChecker.laplacianVariance(bitmap)
                        
                        // Encode image for EdgeSAM
                        Log.d(TAG, "Encoding captured image for EdgeSAM...")
                        hasEncodedImage = edgeSAM.encode(bitmap)
                        Log.d(TAG, "EdgeSAM encoding result: $hasEncodedImage")
                        
                        // Android doesn't have native depth camera API like iOS
                        // Return placeholder depth values
                        val payload = mapOf<String, Any>(
                            "imagePath" to imageFile.absolutePath,
                            "depthPath" to depthFile.absolutePath,
                            "width" to latestWidth,
                            "height" to latestHeight,
                            "laplacian" to latestLaplacian,
                            "backgroundDepth" to 100.0,
                            "pixelSizeCm" to 0.05,
                            "depthValues" to listOf<Double>(),
                            "depthWidth" to 0,
                            "depthHeight" to 0
                        )
                        
                        ContextCompat.getMainExecutor(context).execute {
                            callback(payload, null)
                        }
                    } catch (e: Exception) {
                        Log.e(TAG, "Failed to process captured image", e)
                        ContextCompat.getMainExecutor(context).execute {
                            callback(null, e.message ?: "Processing failed")
                        }
                    }
                }
                
                override fun onError(exception: ImageCaptureException) {
                    Log.e(TAG, "Image capture failed", exception)
                    ContextCompat.getMainExecutor(context).execute {
                        callback(null, exception.message ?: "Capture failed")
                    }
                }
            }
        )
    }

    fun decodeMask(normalizedX: Double, normalizedY: Double, callback: (ByteArray?, String?) -> Unit) {
        val bitmap = latestBitmap
        if (bitmap == null) {
            callback(null, "No capture available")
            return
        }
        
        cameraExecutor.execute {
            try {
                // Try EdgeSAM first
                if (edgeSAM.hasModels && hasEncodedImage) {
                    val mask = edgeSAM.decodeMask(normalizedX, normalizedY, MASK_WIDTH, MASK_HEIGHT)
                    if (mask != null) {
                        val coverage = mask.count { it > 0 }.toDouble() / mask.size * 100
                        Log.d(TAG, "EdgeSAM decoded mask at ($normalizedX, $normalizedY): ${coverage.toInt()}% coverage")
                        ContextCompat.getMainExecutor(context).execute {
                            callback(mask, null)
                        }
                        return@execute
                    }
                }
                
                Log.e(TAG, "EdgeSAM not available for decodeMask")
                ContextCompat.getMainExecutor(context).execute {
                    callback(null, "EdgeSAM not available. Capture image first.")
                }
            } catch (e: Exception) {
                Log.e(TAG, "Mask decode failed", e)
                ContextCompat.getMainExecutor(context).execute {
                    callback(null, e.message ?: "Decode failed")
                }
            }
        }
    }

    fun loadImageFromPath(path: String, callback: (Map<String, Any>?, String?) -> Unit) {
        Log.d(TAG, "loadImageFromPath called with: $path")
        
        cameraExecutor.execute {
            try {
                val file = File(path)
                Log.d(TAG, "Checking file existence: ${file.absolutePath}")
                
                if (!file.exists()) {
                    Log.e(TAG, "File does not exist: $path")
                    ContextCompat.getMainExecutor(context).execute {
                        callback(null, "Image file does not exist")
                    }
                    return@execute
                }
                
                Log.d(TAG, "File exists, size: ${file.length()} bytes")

                // Load bitmap from file with options to handle large images
                val options = BitmapFactory.Options().apply {
                    inJustDecodeBounds = true
                }
                BitmapFactory.decodeFile(path, options)
                Log.d(TAG, "Image dimensions: ${options.outWidth}x${options.outHeight}")
                
                // Calculate sample size if image is too large
                val maxDimension = 2048
                var sampleSize = 1
                while (options.outWidth / sampleSize > maxDimension || 
                       options.outHeight / sampleSize > maxDimension) {
                    sampleSize *= 2
                }
                
                val loadOptions = BitmapFactory.Options().apply {
                    inSampleSize = sampleSize
                }
                
                val bitmap = BitmapFactory.decodeFile(path, loadOptions)
                if (bitmap == null) {
                    Log.e(TAG, "Failed to decode image: $path")
                    ContextCompat.getMainExecutor(context).execute {
                        callback(null, "Failed to decode image. The file may be corrupted.")
                    }
                    return@execute
                }
                
                Log.d(TAG, "Loaded bitmap: ${bitmap.width}x${bitmap.height} (sample size: $sampleSize)")

                // Store for segmentation
                latestBitmap?.recycle()
                latestBitmap = bitmap
                latestWidth = bitmap.width
                latestHeight = bitmap.height

                // Calculate Laplacian variance for blur detection
                Log.d(TAG, "Calculating blur score...")
                latestLaplacian = BlurChecker.laplacianVariance(bitmap)
                Log.d(TAG, "Laplacian score: $latestLaplacian")
                
                // Try to load models first if needed
                if (!edgeSAM.hasModels) {
                    Log.d(TAG, "Loading EdgeSAM models...")
                    edgeSAM.tryLoadModels()
                    Log.d(TAG, "Models loaded: ${edgeSAM.hasModels}")
                }
                
                // Encode image for EdgeSAM
                Log.d(TAG, "Encoding image for EdgeSAM...")
                hasEncodedImage = edgeSAM.encode(bitmap)
                Log.d(TAG, "EdgeSAM encoding result: $hasEncodedImage")
                
                if (!hasEncodedImage) {
                    Log.w(TAG, "Image encoding failed, but continuing - will retry during segmentation")
                }

                val payload = mapOf<String, Any>(
                    "imagePath" to path,
                    "width" to latestWidth,
                    "height" to latestHeight,
                    "laplacian" to latestLaplacian,
                    "success" to true,
                    "encoded" to hasEncodedImage
                )

                ContextCompat.getMainExecutor(context).execute {
                    callback(payload, null)
                }
            } catch (e: Exception) {
                Log.e(TAG, "Failed to load image from path", e)
                ContextCompat.getMainExecutor(context).execute {
                    callback(null, "Failed to load image: ${e.message}")
                }
            }
        }
    }

    fun autoSegment(callback: (List<Map<String, Any>>?, String?) -> Unit) {
        val bitmap = latestBitmap
        if (bitmap == null) {
            Log.e(TAG, "autoSegment called but no image is loaded")
            callback(null, "No image available. Please capture or upload an image first.")
            return
        }

        cameraExecutor.execute {
            try {
                Log.d(TAG, "Starting EdgeSAM auto-segmentation...")
                Log.d(TAG, "Image size: ${bitmap.width}x${bitmap.height}")
                Log.d(TAG, "EdgeSAM status - hasModels: ${edgeSAM.hasModels}, hasEncodedImage: $hasEncodedImage")
                
                // Try to load models if not already loaded
                if (!edgeSAM.hasModels) {
                    Log.d(TAG, "Models not loaded, attempting to load...")
                    edgeSAM.tryLoadModels()
                }
                
                if (!edgeSAM.hasModels) {
                    Log.e(TAG, "EdgeSAM models still not available after load attempt")
                    ContextCompat.getMainExecutor(context).execute {
                        callback(null, "EdgeSAM models not loaded. Please ensure ONNX model files are in assets folder.")
                    }
                    return@execute
                }
                
                if (!hasEncodedImage) {
                    // Try encoding now
                    Log.d(TAG, "No cached encoding, encoding image now...")
                    hasEncodedImage = edgeSAM.encode(bitmap)
                    Log.d(TAG, "Encoding result: $hasEncodedImage")
                    if (!hasEncodedImage) {
                        ContextCompat.getMainExecutor(context).execute {
                            callback(null, "Failed to encode image. The image may be corrupted or unsupported.")
                        }
                        return@execute
                    }
                }
                
                // Run EdgeSAM point-grid segmentation
                Log.d(TAG, "Running point-grid segmentation...")
                val segments = segmentWithEdgeSAM()
                
                if (segments.isEmpty()) {
                    Log.d(TAG, "No segments found in image")
                    ContextCompat.getMainExecutor(context).execute {
                        callback(null, "No food regions detected. Try with a clearer image of food on a plate.")
                    }
                    return@execute
                }

                Log.d(TAG, "EdgeSAM found ${segments.size} segments")
                ContextCompat.getMainExecutor(context).execute {
                    callback(segments, null)
                }
            } catch (e: Exception) {
                Log.e(TAG, "Auto-segmentation failed with exception", e)
                val errorMessage = when {
                    e.message?.contains("ORT", ignoreCase = true) == true -> 
                        "ONNX Runtime error: ${e.message}"
                    e.message?.contains("memory", ignoreCase = true) == true ->
                        "Out of memory. Try with a smaller image."
                    else -> "Segmentation failed: ${e.message ?: "Unknown error"}"
                }
                ContextCompat.getMainExecutor(context).execute {
                    callback(null, errorMessage)
                }
            }
        }
    }

    /**
     * EdgeSAM-based segmentation using point grid sampling
     */
    private fun segmentWithEdgeSAM(): List<Map<String, Any>> {
        Log.d(TAG, "Running EdgeSAM point-grid segmentation")
        
        // Grid of points to sample - 5x5 = 25 points
        val gridSize = 5
        val margin = 0.15
        val step = (1.0 - 2 * margin) / (gridSize - 1)
        
        val candidates = mutableListOf<MaskCandidate>()
        
        // Sample masks at grid points
        for (row in 0 until gridSize) {
            for (col in 0 until gridSize) {
                val x = margin + col * step
                val y = margin + row * step
                
                val mask = edgeSAM.decodeMask(x, y, MASK_WIDTH, MASK_HEIGHT)
                if (mask == null) {
                    Log.d(TAG, "Point ($x, $y) -> decode failed")
                    continue
                }
                
                // Calculate coverage and bounds
                var count = 0
                var minX = MASK_WIDTH
                var maxX = 0
                var minY = MASK_HEIGHT
                var maxY = 0
                var sumX = 0L
                var sumY = 0L
                
                for (py in 0 until MASK_HEIGHT) {
                    for (px in 0 until MASK_WIDTH) {
                        if (mask[py * MASK_WIDTH + px] > 0) {
                            count++
                            minX = min(minX, px)
                            maxX = max(maxX, px)
                            minY = min(minY, py)
                            maxY = max(maxY, py)
                            sumX += px
                            sumY += py
                        }
                    }
                }
                
                val coverage = count.toDouble() / (MASK_WIDTH * MASK_HEIGHT)
                
                // Filter: 0.5% to 70% coverage
                if (coverage >= 0.005 && coverage <= 0.70 && maxX > minX && maxY > minY) {
                    val centroidX = sumX.toDouble() / count / MASK_WIDTH
                    val centroidY = sumY.toDouble() / count / MASK_HEIGHT
                    candidates.add(MaskCandidate(mask, coverage, centroidX, centroidY, minX, maxX, minY, maxY))
                    Log.d(TAG, "Point (${"%.2f".format(x)}, ${"%.2f".format(y)}) -> ${"%.1f".format(coverage * 100)}% coverage")
                } else {
                    Log.d(TAG, "Point (${"%.2f".format(x)}, ${"%.2f".format(y)}) -> filtered (${"%.1f".format(coverage * 100)}%)")
                }
            }
        }
        
        Log.d(TAG, "Found ${candidates.size} candidate masks, clustering...")
        
        // Cluster similar masks using IoU
        val clusters = clusterMasks(candidates)
        Log.d(TAG, "Clustered into ${clusters.size} segments")
        
        // Convert to response format
        return clusters.mapIndexed { index, candidate ->
            val bounds = mapOf(
                "x" to candidate.minX.toDouble() / MASK_WIDTH,
                "y" to candidate.minY.toDouble() / MASK_HEIGHT,
                "width" to (candidate.maxX - candidate.minX).toDouble() / MASK_WIDTH,
                "height" to (candidate.maxY - candidate.minY).toDouble() / MASK_HEIGHT
            )
            
            mapOf(
                "id" to index,
                "mask" to candidate.mask,
                "bounds" to bounds,
                "centerX" to candidate.centroidX,
                "centerY" to candidate.centroidY
            )
        }
    }
    
    // Data class for mask candidates - declared at class level for clustering
    private data class MaskCandidate(
        val mask: ByteArray,
        val coverage: Double,
        val centroidX: Double,
        val centroidY: Double,
        val minX: Int, val maxX: Int,
        val minY: Int, val maxY: Int
    )
    
    /**
     * Cluster masks by IoU similarity
     */
    private fun clusterMasks(masks: List<MaskCandidate>): List<MaskCandidate> {
        if (masks.isEmpty()) return emptyList()
        
        val used = BooleanArray(masks.size) { false }
        val clusters = mutableListOf<MaskCandidate>()
        val iouThreshold = 0.5
        
        for (i in masks.indices) {
            if (used[i]) continue
            
            used[i] = true
            
            // Find all similar masks
            for (j in i + 1 until masks.size) {
                if (used[j]) continue
                
                val iou = calculateIoU(masks[i].mask, masks[j].mask)
                if (iou > iouThreshold) {
                    used[j] = true
                }
            }
            
            clusters.add(masks[i])
        }
        
        // Limit to 8 segments max
        return clusters.take(8)
    }
    
    /**
     * Calculate Intersection over Union for two masks
     */
    private fun calculateIoU(mask1: ByteArray, mask2: ByteArray): Double {
        var intersection = 0
        var union = 0
        
        for (i in 0 until min(mask1.size, mask2.size)) {
            val a = mask1[i] > 0
            val b = mask2[i] > 0
            if (a && b) intersection++
            if (a || b) union++
        }
        
        return if (union > 0) intersection.toDouble() / union else 0.0
    }

    fun release() {
        cameraProvider?.unbindAll()
        textureEntry?.release()
        cameraExecutor.shutdown()
        latestBitmap?.recycle()
        latestBitmap = null
        hasEncodedImage = false
        edgeSAM.release()
    }
}

