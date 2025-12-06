import CoreGraphics
import CoreImage
import CoreML
import Foundation
import UIKit

final class EdgeSAMBridge {
  private var model: MLModel?

  func loadModel() throws {
    if model != nil { return }
    let modelURL = try EdgeSAMBridge.locateModel()
    model = try MLModel(contentsOf: modelURL)
  }

  func encode(image: UIImage) throws -> MLMultiArray {
    try loadModel()
    guard let model else { throw NSError(domain: "platedepth.ml", code: -10, userInfo: [NSLocalizedDescriptionKey: "Model missing"]) }
    let resized = image.resized(to: CGSize(width: 1024, height: 1024))
    let buffer = resized.pixelBuffer(width: 1024, height: 1024)
    let input = MLDictionaryFeatureProvider(dictionary: ["image": buffer as Any])
    let output = try model.prediction(from: input)
    guard let embedding = output.featureValue(for: "embedding")?.multiArrayValue else {
      throw NSError(domain: "platedepth.ml", code: -11, userInfo: [NSLocalizedDescriptionKey: "Embedding missing"])
    }
    return embedding
  }

  func decodeMask(embedding: MLMultiArray, point: CGPoint) throws -> MLMultiArray {
    try loadModel()
    guard let model else { throw NSError(domain: "platedepth.ml", code: -12, userInfo: [NSLocalizedDescriptionKey: "Model missing"]) }
    let coords = try MLMultiArray(shape: [2], dataType: .float32)
    coords[0] = NSNumber(value: Float(point.x))
    coords[1] = NSNumber(value: Float(point.y))
    let input = MLDictionaryFeatureProvider(dictionary: [
      "embedding": embedding,
      "point": coords,
    ])
    let output = try model.prediction(from: input)
    guard let mask = output.featureValue(for: "mask")?.multiArrayValue else {
      throw NSError(domain: "platedepth.ml", code: -13, userInfo: [NSLocalizedDescriptionKey: "Mask missing"])
    }
    return mask
  }

  private static func locateModel() throws -> URL {
    let fileManager = FileManager.default
    let tempModel = fileManager.temporaryDirectory.appendingPathComponent("EdgeSAM.mlmodel")
    if fileManager.fileExists(atPath: tempModel.path) { return tempModel }
    guard let bundleUrl = Bundle.main.url(forResource: "EdgeSAM", withExtension: "mlmodelc") else {
      throw NSError(domain: "platedepth.ml", code: -14, userInfo: [NSLocalizedDescriptionKey: "EdgeSAM model missing"])
    }
    return bundleUrl
  }
}

private extension UIImage {
  func resized(to target: CGSize) -> UIImage {
    UIGraphicsBeginImageContextWithOptions(target, true, 1.0)
    draw(in: CGRect(origin: .zero, size: target))
    let result = UIGraphicsGetImageFromCurrentImageContext()
    UIGraphicsEndImageContext()
    return result ?? self
  }

  func pixelBuffer(width: Int, height: Int) -> CVPixelBuffer? {
    var pixelBuffer: CVPixelBuffer?
    let attrs = [kCVPixelBufferCGImageCompatibilityKey: kCFBooleanTrue!,
                 kCVPixelBufferCGBitmapContextCompatibilityKey: kCFBooleanTrue!]
    CVPixelBufferCreate(kCFAllocatorDefault, width, height, kCVPixelFormatType_32BGRA, attrs as CFDictionary, &pixelBuffer)
    guard let buffer = pixelBuffer else { return nil }
    CVPixelBufferLockBaseAddress(buffer, .readOnly)
    let context = CIContext()
    if let cg = self.cgImage {
      context.render(CIImage(cgImage: cg), to: buffer)
    }
    CVPixelBufferUnlockBaseAddress(buffer, .readOnly)
    return pixelBuffer
  }
}
