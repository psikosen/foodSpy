import UIKit
import Flutter

@UIApplicationMain
@objc class AppDelegate: FlutterAppDelegate {
  private var methodChannel: FlutterMethodChannel?
  private var eventChannel: FlutterEventChannel?
  private let cameraController = NativeCameraController()
  private let stabilityMonitor = StabilityMonitor()

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    let controller: FlutterViewController = window?.rootViewController as! FlutterViewController
    methodChannel = FlutterMethodChannel(name: "platedepth/native", binaryMessenger: controller.binaryMessenger)
    eventChannel = FlutterEventChannel(name: "platedepth/stability", binaryMessenger: controller.binaryMessenger)

    methodChannel?.setMethodCallHandler(handle(_:result:))
    eventChannel?.setStreamHandler(stabilityMonitor)

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
    case "echo":
      result("swift-bridge-ok")
    default:
      result(FlutterMethodNotImplemented)
    }
  }
}
