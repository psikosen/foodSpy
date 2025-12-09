import CoreGraphics
import CoreImage
import CoreML
import Foundation
import UIKit

/// Bridge for EdgeSAM CoreML models (encoder + decoder)
/// Models from: https://github.com/chongzhou96/EdgeSAM
final class EdgeSAMBridge {
  private var encoderModel: MLModel?
  private var decoderModel: MLModel?
  private var modelsAvailable = false
  private var loadAttempted = false
  
  /// Check if models are available
  var hasModels: Bool { modelsAvailable }
  
  /// Load both encoder and decoder models
  func loadModels() throws {
    if loadAttempted { 
      if !modelsAvailable {
        throw NSError(domain: "platedepth.ml", code: -14, userInfo: [NSLocalizedDescriptionKey: "EdgeSAM models not available"])
      }
      return 
    }
    loadAttempted = true
    
    do {
      let encoderURL = try EdgeSAMBridge.locateModel(name: "edge_sam_3x_encoder")
      let decoderURL = try EdgeSAMBridge.locateModel(name: "edge_sam_3x_decoder")
      
      print("[EdgeSAM] Loading encoder from: \(encoderURL.path)")
      encoderModel = try MLModel(contentsOf: encoderURL)
      
      print("[EdgeSAM] Loading decoder from: \(decoderURL.path)")
      decoderModel = try MLModel(contentsOf: decoderURL)
      
      modelsAvailable = true
      print("[EdgeSAM] Models loaded successfully")
    } catch {
      print("[EdgeSAM] Failed to load models: \(error.localizedDescription)")
      modelsAvailable = false
      throw error
    }
  }
  
  /// Try to load models without throwing (for checking availability)
  func tryLoadModels() -> Bool {
    if loadAttempted { return modelsAvailable }
    do {
      try loadModels()
      return true
    } catch {
      return false
    }
  }
  
  /// Encode image to embedding using EdgeSAM encoder
  /// Input: 1024x1024 RGB image
  /// Output: embedding tensor (typically 256x64x64 for EdgeSAM)
  func encode(image: UIImage) throws -> MLMultiArray {
    try loadModels()
    guard let encoder = encoderModel else {
      throw NSError(domain: "platedepth.ml", code: -10, userInfo: [NSLocalizedDescriptionKey: "Encoder model missing"])
    }
    
    print("[EdgeSAM] Encoding image of size: \(image.size)")
    let resized = image.resized(to: CGSize(width: 1024, height: 1024))
    guard let buffer = resized.pixelBuffer(width: 1024, height: 1024) else {
      throw NSError(domain: "platedepth.ml", code: -15, userInfo: [NSLocalizedDescriptionKey: "Failed to create pixel buffer"])
    }
    
    let input = try MLDictionaryFeatureProvider(dictionary: ["image": buffer])
    let output = try encoder.prediction(from: input)
    
    print("[EdgeSAM] Encoder output features: \(output.featureNames)")
    
    // Try common output names for embedding
    for outputName in ["embedding", "image_embedding", "image_embeddings", "output", "features"] {
      if let embedding = output.featureValue(for: outputName)?.multiArrayValue {
        print("[EdgeSAM] Found embedding '\(outputName)' with shape: \(embedding.shape)")
        return embedding
      }
    }
    
    // If no known name found, try first available MLMultiArray output
    for featureName in output.featureNames {
      if let embedding = output.featureValue(for: featureName)?.multiArrayValue {
        print("[EdgeSAM] Using fallback embedding '\(featureName)' with shape: \(embedding.shape)")
        return embedding
      }
    }
    
    throw NSError(domain: "platedepth.ml", code: -11, userInfo: [NSLocalizedDescriptionKey: "Embedding output not found. Available outputs: \(output.featureNames)"])
  }
  
  /// Decode mask from embedding and point prompt
  /// Point: normalized (x, y) in [0,1] where (0,0) is top-left
  /// Labels: 0=negative, 1=positive, 2=box top-left, 3=box bottom-right
  func decodeMask(embedding: MLMultiArray, point: CGPoint, label: Int = 1) throws -> MLMultiArray {
    try loadModels()
    guard let decoder = decoderModel else {
      throw NSError(domain: "platedepth.ml", code: -12, userInfo: [NSLocalizedDescriptionKey: "Decoder model missing"])
    }
    
    print("[EdgeSAM] Decoding mask for point: (\(point.x), \(point.y)) with embedding shape: \(embedding.shape)")
    
    // Point coordinates - SAM uses (x, y) format scaled to image size (1024x1024)
    // Some models expect [y, x], we try [x, y] first as it's more common
    let pointCoords = try MLMultiArray(shape: [1, 1, 2], dataType: .float32)
    let scaledX = Float(point.x * 1024.0)
    let scaledY = Float(point.y * 1024.0)
    
    // Standard SAM format: [x, y]
    pointCoords[[0, 0, 0] as [NSNumber]] = NSNumber(value: scaledX)
    pointCoords[[0, 0, 1] as [NSNumber]] = NSNumber(value: scaledY)
    
    print("[EdgeSAM] Point coords: [\(scaledX), \(scaledY)]")
    
    // Point label (1 = positive/foreground click)
    let pointLabels = try MLMultiArray(shape: [1, 1], dataType: .float32)
    pointLabels[[0, 0] as [NSNumber]] = NSNumber(value: Float(label))
    
    // Build input dictionary - check what inputs the model expects
    var inputDict: [String: Any] = [:]
    
    // Add embedding with various possible input names
    inputDict["image_embedding"] = embedding
    inputDict["image_embeddings"] = embedding  // Some models use plural
    
    // Add point coordinates
    inputDict["point_coords"] = pointCoords
    inputDict["points"] = pointCoords  // Alternative name
    
    // Add point labels
    inputDict["point_labels"] = pointLabels
    inputDict["labels"] = pointLabels  // Alternative name
    
    // Mask input (zeros for no prior mask)
    let maskInput = try MLMultiArray(shape: [1, 1, 256, 256], dataType: .float32)
    for i in 0..<maskInput.count {
      maskInput[i] = 0
    }
    inputDict["mask_input"] = maskInput
    inputDict["mask_inputs"] = maskInput
    
    // Has mask flag
    let hasMask = try MLMultiArray(shape: [1], dataType: .float32)
    hasMask[0] = 0
    inputDict["has_mask_input"] = hasMask
    
    // Original image size (for scaling output if needed)
    let origSize = try MLMultiArray(shape: [1, 2], dataType: .int32)
    origSize[[0, 0] as [NSNumber]] = 1024
    origSize[[0, 1] as [NSNumber]] = 1024
    inputDict["orig_im_size"] = origSize
    
    let input = try MLDictionaryFeatureProvider(dictionary: inputDict)
    let output = try decoder.prediction(from: input)
    
    print("[EdgeSAM] Decoder output features: \(output.featureNames)")
    
    // Try common output names for mask
    for outputName in ["masks", "mask", "output", "low_res_masks", "upscaled_masks"] {
      if let mask = output.featureValue(for: outputName)?.multiArrayValue {
        print("[EdgeSAM] Found mask output '\(outputName)' with shape: \(mask.shape)")
        return mask
      }
    }
    
    // Fallback to first MLMultiArray output
    for featureName in output.featureNames {
      if let mask = output.featureValue(for: featureName)?.multiArrayValue {
        print("[EdgeSAM] Using fallback output '\(featureName)' with shape: \(mask.shape)")
        return mask
      }
    }
    
    throw NSError(domain: "platedepth.ml", code: -13, userInfo: [NSLocalizedDescriptionKey: "Mask output not found in decoder model. Available outputs: \(output.featureNames)"])
  }
  
  /// Locate model by name in bundle or temp directory
  private static func locateModel(name: String) throws -> URL {
    let fileManager = FileManager.default
    
    print("[EdgeSAM] ========================================")
    print("[EdgeSAM] Looking for model: \(name)")
    print("[EdgeSAM] Bundle path: \(Bundle.main.bundlePath)")
    
    // List all contents for debugging
    let bundleContents = (try? fileManager.contentsOfDirectory(atPath: Bundle.main.bundlePath)) ?? []
    let mlAssets = bundleContents.filter { $0.contains("edge_sam") || $0.contains("mlmodel") }
    print("[EdgeSAM] ML assets in bundle: \(mlAssets)")
    
    // Check for compiled model in bundle (.mlmodelc) - Xcode compiles mlpackage to this
    if let bundleURL = Bundle.main.url(forResource: name, withExtension: "mlmodelc") {
      print("[EdgeSAM] ✓ Found compiled model at: \(bundleURL.path)")
      return bundleURL
    }
    
    // Check for mlpackage in bundle
    if let bundleURL = Bundle.main.url(forResource: name, withExtension: "mlpackage") {
      print("[EdgeSAM] ✓ Found mlpackage at: \(bundleURL.path)")
      return bundleURL
    }
    
    // Direct path checks
    let directCompiledPath = Bundle.main.bundlePath + "/\(name).mlmodelc"
    if fileManager.fileExists(atPath: directCompiledPath) {
      print("[EdgeSAM] ✓ Found at direct compiled path: \(directCompiledPath)")
      return URL(fileURLWithPath: directCompiledPath)
    }
    
    let directPackagePath = Bundle.main.bundlePath + "/\(name).mlpackage"
    if fileManager.fileExists(atPath: directPackagePath) {
      print("[EdgeSAM] ✓ Found at direct package path: \(directPackagePath)")
      return URL(fileURLWithPath: directPackagePath)
    }
    
    // Check in Frameworks directory (sometimes models end up here)
    let frameworksPath = Bundle.main.bundlePath + "/Frameworks/\(name).mlmodelc"
    if fileManager.fileExists(atPath: frameworksPath) {
      print("[EdgeSAM] ✓ Found in Frameworks: \(frameworksPath)")
      return URL(fileURLWithPath: frameworksPath)
    }
    
    // Search recursively in bundle
    if let enumerator = fileManager.enumerator(atPath: Bundle.main.bundlePath) {
      while let element = enumerator.nextObject() as? String {
        if element.contains(name) && (element.hasSuffix(".mlmodelc") || element.hasSuffix(".mlpackage")) {
          let fullPath = Bundle.main.bundlePath + "/" + element
          print("[EdgeSAM] ✓ Found via search: \(fullPath)")
          return URL(fileURLWithPath: fullPath)
        }
      }
    }
    
    print("[EdgeSAM] ✗ ERROR: Model '\(name)' not found in bundle")
    print("[EdgeSAM] All bundle contents: \(bundleContents)")
    print("[EdgeSAM] Make sure:")
    print("[EdgeSAM]   1. The .mlpackage files are added to Xcode project")
    print("[EdgeSAM]   2. They are included in 'Copy Bundle Resources' build phase")
    print("[EdgeSAM]   3. Build the project in Xcode (not just Flutter)")
    print("[EdgeSAM] ========================================")
    
    throw NSError(domain: "platedepth.ml", code: -14, userInfo: [
      NSLocalizedDescriptionKey: "\(name) model not found in app bundle. Open Xcode, add the .mlpackage to the Runner target's 'Copy Bundle Resources'."
    ])
  }
}

// MARK: - UIImage Extensions

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
    let attrs: [CFString: Any] = [
      kCVPixelBufferCGImageCompatibilityKey: true,
      kCVPixelBufferCGBitmapContextCompatibilityKey: true,
      kCVPixelBufferWidthKey: width,
      kCVPixelBufferHeightKey: height
    ]
    
    let status = CVPixelBufferCreate(
      kCFAllocatorDefault,
      width,
      height,
      kCVPixelFormatType_32BGRA,
      attrs as CFDictionary,
      &pixelBuffer
    )
    
    guard status == kCVReturnSuccess, let buffer = pixelBuffer else {
      return nil
    }
    
    CVPixelBufferLockBaseAddress(buffer, [])
    defer { CVPixelBufferUnlockBaseAddress(buffer, []) }
    
    guard let context = CGContext(
      data: CVPixelBufferGetBaseAddress(buffer),
      width: width,
      height: height,
      bitsPerComponent: 8,
      bytesPerRow: CVPixelBufferGetBytesPerRow(buffer),
      space: CGColorSpaceCreateDeviceRGB(),
      bitmapInfo: CGImageAlphaInfo.noneSkipFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
    ) else {
      return nil
    }
    
    if let cgImage = self.cgImage {
      context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))
    }
    
    return buffer
  }
}
