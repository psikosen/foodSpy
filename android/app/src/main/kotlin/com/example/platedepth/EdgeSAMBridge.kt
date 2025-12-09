package com.example.platedepth

import ai.onnxruntime.OnnxTensor
import ai.onnxruntime.OrtEnvironment
import ai.onnxruntime.OrtSession
import android.content.Context
import android.graphics.Bitmap
import android.util.Log
import java.io.File
import java.io.FileOutputStream
import java.nio.FloatBuffer
import kotlin.math.max
import kotlin.math.min

/**
 * EdgeSAM Bridge for Android using ONNX Runtime
 * Models: edge_sam_3x_encoder.onnx and edge_sam_3x_decoder.onnx
 */
class EdgeSAMBridge(private val context: Context) {
    companion object {
        private const val TAG = "EdgeSAMBridge"
        private const val ENCODER_MODEL = "edge_sam_3x_encoder.onnx"
        private const val DECODER_MODEL = "edge_sam_3x_decoder.onnx"
        private const val INPUT_SIZE = 1024
    }

    private var ortEnvironment: OrtEnvironment? = null
    private var encoderSession: OrtSession? = null
    private var decoderSession: OrtSession? = null
    private var modelsLoaded = false
    private var loadAttempted = false
    
    // Cached embedding from last encoded image
    private var cachedEmbedding: OnnxTensor? = null
    private var embeddingShape: LongArray? = null

    val hasModels: Boolean get() = modelsLoaded

    /**
     * Try to load models, returns true if successful
     */
    fun tryLoadModels(): Boolean {
        if (loadAttempted) return modelsLoaded
        loadAttempted = true
        
        return try {
            loadModels()
            true
        } catch (e: Exception) {
            Log.e(TAG, "Failed to load models: ${e.message}")
            false
        }
    }

    /**
     * Load both encoder and decoder models
     */
    fun loadModels() {
        if (modelsLoaded) return
        
        Log.d(TAG, "Loading EdgeSAM ONNX models...")
        
        ortEnvironment = OrtEnvironment.getEnvironment()
        val env = ortEnvironment ?: throw IllegalStateException("Failed to create ORT environment")
        
        // Copy models from assets to files dir if needed
        val encoderFile = copyModelFromAssets(ENCODER_MODEL)
        val decoderFile = copyModelFromAssets(DECODER_MODEL)
        
        if (encoderFile == null || decoderFile == null) {
            throw IllegalStateException("EdgeSAM models not found. Place $ENCODER_MODEL and $DECODER_MODEL in assets folder.")
        }
        
        val sessionOptions = OrtSession.SessionOptions()
        sessionOptions.setIntraOpNumThreads(4)
        
        Log.d(TAG, "Loading encoder from: ${encoderFile.absolutePath}")
        encoderSession = env.createSession(encoderFile.absolutePath, sessionOptions)
        Log.d(TAG, "Encoder loaded. Inputs: ${encoderSession?.inputNames}, Outputs: ${encoderSession?.outputNames}")
        
        Log.d(TAG, "Loading decoder from: ${decoderFile.absolutePath}")
        decoderSession = env.createSession(decoderFile.absolutePath, sessionOptions)
        Log.d(TAG, "Decoder loaded. Inputs: ${decoderSession?.inputNames}, Outputs: ${decoderSession?.outputNames}")
        
        modelsLoaded = true
        Log.d(TAG, "EdgeSAM models loaded successfully")
    }

    /**
     * Copy model from assets to internal storage
     */
    private fun copyModelFromAssets(modelName: String): File? {
        val modelFile = File(context.filesDir, modelName)
        
        // If already copied, return existing file
        if (modelFile.exists() && modelFile.length() > 0) {
            Log.d(TAG, "Model already exists: ${modelFile.absolutePath}")
            return modelFile
        }
        
        // Try to copy from assets
        return try {
            context.assets.open(modelName).use { input ->
                FileOutputStream(modelFile).use { output ->
                    input.copyTo(output)
                }
            }
            Log.d(TAG, "Copied model to: ${modelFile.absolutePath}")
            modelFile
        } catch (e: Exception) {
            Log.e(TAG, "Model not found in assets: $modelName - ${e.message}")
            null
        }
    }

    /**
     * Encode image to embedding
     */
    fun encode(bitmap: Bitmap): Boolean {
        if (!modelsLoaded) {
            Log.d(TAG, "Models not loaded, attempting to load...")
            tryLoadModels()
            if (!modelsLoaded) {
                Log.e(TAG, "Failed to load models for encoding")
                return false
            }
        }
        
        val encoder = encoderSession
        if (encoder == null) {
            Log.e(TAG, "Encoder session is null")
            return false
        }
        
        val env = ortEnvironment
        if (env == null) {
            Log.e(TAG, "ORT environment is null")
            return false
        }
        
        Log.d(TAG, "Encoding image ${bitmap.width}x${bitmap.height}")
        
        var resized: Bitmap? = null
        var inputTensor: OnnxTensor? = null
        
        return try {
            // Resize to 1024x1024
            resized = Bitmap.createScaledBitmap(bitmap, INPUT_SIZE, INPUT_SIZE, true)
            Log.d(TAG, "Resized image to ${INPUT_SIZE}x${INPUT_SIZE}")
            
            // Convert to float tensor [1, 3, 1024, 1024]
            val inputBuffer = FloatBuffer.allocate(1 * 3 * INPUT_SIZE * INPUT_SIZE)
            val pixels = IntArray(INPUT_SIZE * INPUT_SIZE)
            resized.getPixels(pixels, 0, INPUT_SIZE, 0, 0, INPUT_SIZE, INPUT_SIZE)
            
            // NCHW format: channels first
            for (c in 0 until 3) {
                for (i in pixels.indices) {
                    val pixel = pixels[i]
                    val value = when (c) {
                        0 -> ((pixel shr 16) and 0xFF) / 255.0f  // R
                        1 -> ((pixel shr 8) and 0xFF) / 255.0f   // G
                        2 -> (pixel and 0xFF) / 255.0f          // B
                        else -> 0f
                    }
                    inputBuffer.put(value)
                }
            }
            inputBuffer.rewind()
            
            // Create input tensor
            val inputShape = longArrayOf(1, 3, INPUT_SIZE.toLong(), INPUT_SIZE.toLong())
            inputTensor = OnnxTensor.createTensor(env, inputBuffer, inputShape)
            Log.d(TAG, "Created input tensor with shape: ${inputShape.contentToString()}")
            
            // Run encoder - use the actual input name from the model
            Log.d(TAG, "Running encoder with input name 'image'...")
            val inputs = mapOf("image" to inputTensor)
            val results = encoder.run(inputs)
            
            Log.d(TAG, "Encoder returned ${results.size()} outputs")
            
            // Get embedding output - look for "image_embeddings"
            var embeddingResult: OnnxTensor? = null
            for (result in results) {
                Log.d(TAG, "Encoder output: ${result.key}")
                if (result.key == "image_embeddings" || result.key.contains("embed", ignoreCase = true)) {
                    embeddingResult = result.value as? OnnxTensor
                    break
                }
            }
            
            // Fallback to first output
            if (embeddingResult == null) {
                embeddingResult = results.firstOrNull()?.value as? OnnxTensor
            }
            
            if (embeddingResult != null) {
                cachedEmbedding?.close()
                cachedEmbedding = embeddingResult
                embeddingShape = cachedEmbedding?.info?.shape
                Log.d(TAG, "Encoding complete. Embedding shape: ${embeddingShape?.contentToString()}")
                true
            } else {
                Log.e(TAG, "No embedding output from encoder")
                false
            }
        } catch (e: Exception) {
            Log.e(TAG, "Encoding failed: ${e.message}", e)
            false
        } finally {
            if (resized != null && resized != bitmap) {
                resized.recycle()
            }
            // Don't close inputTensor here as the ORT session might still reference it
            // The cached embedding keeps a reference to the result
        }
    }

    /**
     * Decode mask from point prompt
     * @param normalizedX X coordinate normalized to [0, 1]
     * @param normalizedY Y coordinate normalized to [0, 1]
     * @param maskWidth Output mask width
     * @param maskHeight Output mask height
     */
    fun decodeMask(
        normalizedX: Double,
        normalizedY: Double,
        maskWidth: Int,
        maskHeight: Int
    ): ByteArray? {
        if (!modelsLoaded) return null
        
        val decoder = decoderSession ?: return null
        val env = ortEnvironment ?: return null
        val embedding = cachedEmbedding ?: return null
        
        Log.d(TAG, "Decoding mask at ($normalizedX, $normalizedY)")
        
        // Scale point to 1024x1024
        val scaledX = (normalizedX * INPUT_SIZE).toFloat()
        val scaledY = (normalizedY * INPUT_SIZE).toFloat()
        
        var pointCoords: OnnxTensor? = null
        var pointLabels: OnnxTensor? = null
        
        return try {
            // Create point coords tensor [1, 1, 2]
            val pointCoordsBuffer = FloatBuffer.allocate(2)
            pointCoordsBuffer.put(scaledX)
            pointCoordsBuffer.put(scaledY)
            pointCoordsBuffer.rewind()
            pointCoords = OnnxTensor.createTensor(env, pointCoordsBuffer, longArrayOf(1, 1, 2))
            
            // Create point labels tensor [1, 1] - 1 = foreground
            val pointLabelsBuffer = FloatBuffer.allocate(1)
            pointLabelsBuffer.put(1.0f)
            pointLabelsBuffer.rewind()
            pointLabels = OnnxTensor.createTensor(env, pointLabelsBuffer, longArrayOf(1, 1))
            
            // Build inputs map - only use inputs that exist in this ONNX model
            // Model inputs: image_embeddings, point_coords, point_labels
            val inputs = mutableMapOf<String, OnnxTensor>()
            inputs["image_embeddings"] = embedding
            inputs["point_coords"] = pointCoords
            inputs["point_labels"] = pointLabels
            
            Log.d(TAG, "Running decoder with inputs: ${inputs.keys}")
            
            // Run decoder
            val results = decoder.run(inputs)
            
            Log.d(TAG, "Decoder returned ${results.size()} outputs: ${results.map { it.key }}")
            
            // Get mask output - look for "masks" output
            var maskTensor: OnnxTensor? = null
            for (result in results) {
                val name = result.key
                Log.d(TAG, "Output '$name' type: ${result.value?.javaClass?.simpleName}")
                if (name.contains("mask", ignoreCase = true)) {
                    maskTensor = result.value as? OnnxTensor
                    Log.d(TAG, "Found mask output '$name' with shape: ${maskTensor?.info?.shape?.contentToString()}")
                    break
                }
            }
            
            if (maskTensor == null) {
                // Try to use any output that looks like a mask (4D tensor)
                for (result in results) {
                    val tensor = result.value as? OnnxTensor
                    val shape = tensor?.info?.shape
                    if (shape != null && shape.size >= 2) {
                        maskTensor = tensor
                        Log.d(TAG, "Using output '${result.key}' as mask, shape: ${shape.contentToString()}")
                        break
                    }
                }
            }
            
            if (maskTensor == null) {
                Log.e(TAG, "No suitable mask tensor found in decoder output")
                return null
            }
            
            // Convert mask tensor to ByteArray
            val mask = maskTensor.let { tensor ->
                val shape = tensor.info.shape
                Log.d(TAG, "Processing mask with shape: ${shape.contentToString()}")
                
                // Handle different output shapes
                // Could be [B, N, H, W] or [B, H, W] or [H, W]
                val sourceHeight = when {
                    shape.size >= 4 -> shape[shape.size - 2].toInt()
                    shape.size >= 2 -> shape[shape.size - 2].toInt()
                    else -> 256
                }
                val sourceWidth = when {
                    shape.size >= 4 -> shape[shape.size - 1].toInt()
                    shape.size >= 2 -> shape[shape.size - 1].toInt()
                    else -> 256
                }
                
                Log.d(TAG, "Source mask size: ${sourceWidth}x${sourceHeight}")
                
                val floatData = tensor.floatBuffer
                val output = ByteArray(maskWidth * maskHeight)
                
                // Scale and threshold
                val scaleX = sourceWidth.toDouble() / maskWidth
                val scaleY = sourceHeight.toDouble() / maskHeight
                
                var positiveCount = 0
                for (y in 0 until maskHeight) {
                    val srcY = min((y * scaleY).toInt(), sourceHeight - 1)
                    for (x in 0 until maskWidth) {
                        val srcX = min((x * scaleX).toInt(), sourceWidth - 1)
                        val idx = srcY * sourceWidth + srcX
                        val value = if (idx < floatData.capacity()) floatData.get(idx) else 0f
                        
                        // Threshold at 0 (logits)
                        if (value > 0f) {
                            output[y * maskWidth + x] = 1
                            positiveCount++
                        }
                    }
                }
                
                val coverage = positiveCount.toDouble() / (maskWidth * maskHeight) * 100
                Log.d(TAG, "Mask decoded: $positiveCount pixels (${String.format("%.1f", coverage)}% coverage)")
                
                output
            }
            
            mask
        } catch (e: Exception) {
            Log.e(TAG, "Mask decoding failed: ${e.message}", e)
            null
        } finally {
            // Cleanup - only close what we created, not the cached embedding
            pointCoords?.close()
            pointLabels?.close()
        }
    }

    /**
     * Release resources
     */
    fun release() {
        cachedEmbedding?.close()
        cachedEmbedding = null
        encoderSession?.close()
        encoderSession = null
        decoderSession?.close()
        decoderSession = null
        ortEnvironment?.close()
        ortEnvironment = null
        modelsLoaded = false
        loadAttempted = false
    }
}

