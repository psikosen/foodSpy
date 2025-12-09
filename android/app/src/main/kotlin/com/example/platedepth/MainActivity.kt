package com.example.platedepth

import android.os.Bundle
import android.util.Log
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    companion object {
        private const val TAG = "MainActivity"
        private const val METHOD_CHANNEL = "platedepth/native"
        private const val EVENT_CHANNEL = "platedepth/stability"
    }

    private var methodChannel: MethodChannel? = null
    private var eventChannel: EventChannel? = null
    private var cameraController: NativeCameraController? = null
    private var stabilityMonitor: StabilityMonitor? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        Log.d(TAG, "MainActivity onCreate")
    }

    override fun onDestroy() {
        cameraController?.release()
        cameraController = null
        stabilityMonitor = null
        super.onDestroy()
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        // Initialize controllers
        cameraController = NativeCameraController(this)
        stabilityMonitor = StabilityMonitor(this)

        // Setup method channel
        methodChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, METHOD_CHANNEL)
        methodChannel?.setMethodCallHandler { call, result ->
            handleMethodCall(call.method, call.arguments, result)
        }

        // Setup event channel for stability monitoring
        eventChannel = EventChannel(flutterEngine.dartExecutor.binaryMessenger, EVENT_CHANNEL)
        eventChannel?.setStreamHandler(stabilityMonitor)

        Log.d(TAG, "Flutter engine configured with native channels")
    }

    private fun handleMethodCall(method: String, arguments: Any?, result: MethodChannel.Result) {
        Log.d(TAG, "Method call: $method")
        
        when (method) {
            "initializeCamera" -> initializeCamera(result)
            "startStream" -> startStream(result)
            "captureFrame" -> captureFrame(result)
            "laplacianScore" -> laplacianScore(arguments, result)
            "decodeMask" -> decodeMask(arguments, result)
            "loadImageFromPath" -> loadImageFromPath(arguments, result)
            "autoSegment" -> autoSegment(result)
            "checkEdgeSAM" -> checkEdgeSAM(result)
            "echo" -> result.success("kotlin-bridge-ok")
            else -> result.notImplemented()
        }
    }
    
    private fun checkEdgeSAM(result: MethodChannel.Result) {
        val controller = cameraController
        val hasModels = controller?.hasEdgeSAM() ?: false
        result.success(mapOf(
            "modelsLoaded" to hasModels,
            "hasModels" to hasModels
        ))
    }

    private fun initializeCamera(result: MethodChannel.Result) {
        val controller = cameraController
        if (controller == null) {
            result.error("camera_error", "Camera controller not initialized", null)
            return
        }

        val textureRegistry = flutterEngine?.renderer
        if (textureRegistry == null) {
            result.error("registry_missing", "Texture registry not available", null)
            return
        }

        controller.initialize(textureRegistry, this) { textureId, error ->
            runOnUiThread {
                if (error != null) {
                    result.error("camera_init_failed", error, null)
                } else if (textureId != null) {
                    result.success(textureId)
                } else {
                    result.error("camera_init_failed", "Unknown error during camera initialization", null)
                }
            }
        }
    }

    private fun startStream(result: MethodChannel.Result) {
        val controller = cameraController
        if (controller == null) {
            result.error("camera_error", "Camera controller not initialized", null)
            return
        }

        controller.startStream(this) { error ->
            runOnUiThread {
                if (error != null) {
                    result.error("stream_failed", error, null)
                } else {
                    stabilityMonitor?.start()
                    result.success(null)
                }
            }
        }
    }

    private fun captureFrame(result: MethodChannel.Result) {
        val controller = cameraController
        if (controller == null) {
            result.error("camera_error", "Camera controller not initialized", null)
            return
        }

        controller.captureFrame { payload, error ->
            if (error != null) {
                result.error("capture_failed", error, null)
            } else if (payload != null) {
                result.success(payload)
            } else {
                result.error("capture_failed", "No capture payload", null)
            }
        }
    }

    private fun laplacianScore(arguments: Any?, result: MethodChannel.Result) {
        val jpegBytes = arguments as? ByteArray
        if (jpegBytes == null) {
            result.error("laplacian_error", "Invalid image data", null)
            return
        }

        try {
            val score = BlurChecker.laplacianVariance(jpegBytes)
            result.success(score)
        } catch (e: Exception) {
            result.error("laplacian_error", e.message ?: "Failed to calculate blur score", null)
        }
    }

    private fun decodeMask(arguments: Any?, result: MethodChannel.Result) {
        val args = arguments as? Map<*, *>
        val x = args?.get("x") as? Double
        val y = args?.get("y") as? Double

        if (x == null || y == null) {
            result.error("decode_args", "Missing tap coordinates", null)
            return
        }

        val controller = cameraController
        if (controller == null) {
            result.error("camera_error", "Camera controller not initialized", null)
            return
        }

        controller.decodeMask(x, y) { maskData, error ->
            if (error != null) {
                result.error("decode_failed", error, null)
            } else if (maskData != null) {
                result.success(maskData)
            } else {
                result.error("decode_failed", "No mask returned", null)
            }
        }
    }

    private fun loadImageFromPath(arguments: Any?, result: MethodChannel.Result) {
        val path = arguments as? String
        if (path == null) {
            result.error("load_image_error", "Missing image path", null)
            return
        }

        val controller = cameraController
        if (controller == null) {
            result.error("camera_error", "Camera controller not initialized", null)
            return
        }

        controller.loadImageFromPath(path) { payload, error ->
            runOnUiThread {
                if (error != null) {
                    result.error("load_image_failed", error, null)
                } else if (payload != null) {
                    result.success(payload)
                } else {
                    result.error("load_image_failed", "No image payload returned", null)
                }
            }
        }
    }

    private fun autoSegment(result: MethodChannel.Result) {
        val controller = cameraController
        if (controller == null) {
            result.error("camera_error", "Camera controller not initialized", null)
            return
        }

        controller.autoSegment { segments, error ->
            runOnUiThread {
                if (error != null) {
                    result.error("auto_segment_failed", error, null)
                } else if (segments != null) {
                    result.success(segments)
                } else {
                    result.error("auto_segment_failed", "No segments returned", null)
                }
            }
        }
    }
}
