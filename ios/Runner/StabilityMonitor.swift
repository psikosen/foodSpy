import CoreMotion
import Flutter
import Foundation

final class StabilityMonitor: NSObject, FlutterStreamHandler {
  private let motionManager = CMMotionManager()
  private var eventSink: FlutterEventSink?
  private let queue = OperationQueue()
  private let threshold: Double = 1.5

  func start() {
    guard motionManager.isGyroAvailable else { return }
    motionManager.gyroUpdateInterval = 0.1
    motionManager.startGyroUpdates(to: queue) { [weak self] data, _ in
      guard let self, let data else { return }
      let rotationMagnitude = abs(data.rotationRate.x) + abs(data.rotationRate.y) + abs(data.rotationRate.z)
      let status = rotationMagnitude > threshold ? "unstable" : "stable"
      self.eventSink?(status)
    }
  }

  func stop() {
    motionManager.stopGyroUpdates()
  }

  func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink) -> FlutterError? {
    eventSink = events
    start()
    return nil
  }

  func onCancel(withArguments arguments: Any?) -> FlutterError? {
    stop()
    eventSink = nil
    return nil
  }
}
