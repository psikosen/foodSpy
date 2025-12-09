import UIKit
import Flutter

@UIApplicationMain
@objc class AppDelegate: FlutterAppDelegate {
  private var methodChannel: FlutterMethodChannel?
  private var eventChannel: FlutterEventChannel?
  private let cameraController = NativeCameraController()
  private let stabilityMonitor = StabilityMonitor()
  
  // SAM 2 for high-quality segmentation, EdgeSAM as fallback
  private let sam2 = SAM2Bridge()
  private let edgeSAM = EdgeSAMBridge()

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    let controller: FlutterViewController = window?.rootViewController as! FlutterViewController
    methodChannel = FlutterMethodChannel(name: "platedepth/native", binaryMessenger: controller.binaryMessenger)
    eventChannel = FlutterEventChannel(name: "platedepth/stability", binaryMessenger: controller.binaryMessenger)

    methodChannel?.setMethodCallHandler(handle(_:result:))
    eventChannel?.setStreamHandler(stabilityMonitor)
    
    // Pre-load segmentation models in background - prefer SAM 2 for quality
    DispatchQueue.global(qos: .userInitiated).async { [weak self] in
      print("[AppDelegate] Pre-loading segmentation models...")
      
      // Try SAM 2 first (higher quality)
      let sam2Loaded = self?.sam2.tryLoadModels() ?? false
      if sam2Loaded {
        print("[AppDelegate] ✓ SAM 2 loaded (variant: \(self?.sam2.variant?.rawValue ?? "unknown"))")
      } else {
        print("[AppDelegate] SAM 2 not available, trying EdgeSAM...")
        let edgeSAMLoaded = self?.edgeSAM.tryLoadModels() ?? false
        print("[AppDelegate] EdgeSAM loaded: \(edgeSAMLoaded)")
      }
    }

    GeneratedPluginRegistrant.register(with: self)
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  private func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "initializeCamera":
      guard let textureRegistry = (window?.rootViewController as? FlutterViewController)?.textureRegistry else {
        result(FlutterError(code: "registry_missing", message: "Texture registry missing", details: nil))
        return
      }
      cameraController.initialize(textureRegistry: textureRegistry) { textureId, error in
        if let error { result(FlutterError(code: "camera_init_failed", message: error.localizedDescription, details: nil)) }
        else if let textureId { result(textureId) }
        else { result(FlutterError(code: "camera_init_failed", message: "Unknown camera init failure", details: nil)) }
      }
    case "startStream":
      cameraController.startSession()
      stabilityMonitor.start()
      result(nil)
    case "captureFrame":
      cameraController.capturePhoto { payload, error in
        if let error { result(FlutterError(code: "capture_failed", message: error.localizedDescription, details: nil)) }
        else if let payload { result(payload) }
        else { result(FlutterError(code: "capture_failed", message: "No capture payload", details: nil)) }
      }
    case "laplacianScore":
      if let data = call.arguments as? FlutterStandardTypedData, let image = UIImage(data: data.data) {
        let score = BlurChecker.laplacianVariance(for: image)
        result(score)
      } else {
        result(FlutterError(code: "laplacian_error", message: "Invalid image", details: nil))
      }
    case "decodeMask":
      guard let args = call.arguments as? [String: Any],
            let x = args["x"] as? Double,
            let y = args["y"] as? Double else {
        result(FlutterError(code: "decode_args", message: "Missing tap coordinates", details: nil))
        return
      }
      cameraController.decodeMask(normalizedPoint: CGPoint(x: x, y: y)) { data, error in
        if let error { result(FlutterError(code: "decode_failed", message: error.localizedDescription, details: nil)) }
        else if let data { result(FlutterStandardTypedData(bytes: data)) }
        else { result(FlutterError(code: "decode_failed", message: "No mask returned", details: nil)) }
      }
    case "autoSegment":
      cameraController.autoSegment { segments, error in
        if let error {
          result(FlutterError(code: "autosegment_failed", message: error.localizedDescription, details: nil))
        } else if let segments {
          // Convert to Flutter-compatible format
          var flutterSegments: [[String: Any]] = []
          for segment in segments {
            var seg: [String: Any] = [
              "id": segment["id"] as Any,
              "centerX": segment["centerX"] as Any,
              "centerY": segment["centerY"] as Any,
              "bounds": segment["bounds"] as Any
            ]
            if let maskData = segment["mask"] as? Data {
              seg["mask"] = FlutterStandardTypedData(bytes: maskData)
            }
            flutterSegments.append(seg)
          }
          result(flutterSegments)
        } else {
          result(FlutterError(code: "autosegment_failed", message: "No segments returned", details: nil))
        }
      }
    case "loadImageFromPath":
      guard let path = call.arguments as? String else {
        result(FlutterError(code: "load_args", message: "Missing image path", details: nil))
        return
      }
      cameraController.loadImageFromPath(path) { error in
        if let error {
          result(FlutterError(code: "load_failed", message: error.localizedDescription, details: nil))
        } else {
          // Return image info
          if let info = self.cameraController.getLoadedImageInfo() {
            result(info)
          } else {
            result(FlutterError(code: "load_failed", message: "Failed to get image info", details: nil))
          }
        }
      }
    case "checkEdgeSAM":
      // Check segmentation model status - SAM 2 preferred, EdgeSAM fallback
      let sam2Loaded = sam2.tryLoadModels()
      let edgeSAMLoaded = edgeSAM.tryLoadModels()
      let anyLoaded = sam2Loaded || edgeSAMLoaded
      
      result([
        "modelsLoaded": anyLoaded,
        "hasModels": anyLoaded,
        "sam2Available": sam2Loaded,
        "sam2Variant": sam2.variant?.rawValue ?? "none",
        "edgeSAMAvailable": edgeSAMLoaded,
        "preferredModel": sam2Loaded ? "SAM2" : (edgeSAMLoaded ? "EdgeSAM" : "none")
      ])
    case "echo":
      result("swift-bridge-ok")
    default:
      result(FlutterMethodNotImplemented)
    }
  }
}
