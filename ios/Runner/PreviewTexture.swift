import Flutter
import Foundation
import CoreVideo

final class PreviewTexture: NSObject, FlutterTexture {
  private var pixelBuffer: CVPixelBuffer?
  private let lock = DispatchQueue(label: "platedepth.texture.lock")

  func copyPixelBuffer() -> Unmanaged<CVPixelBuffer>? {
    var buffer: CVPixelBuffer?
    lock.sync { buffer = pixelBuffer }
    guard let buffer else { return nil }
    return Unmanaged.passRetained(buffer)
  }

  func updateBuffer(_ buffer: CVPixelBuffer) {
    lock.sync { pixelBuffer = buffer }
  }
}
