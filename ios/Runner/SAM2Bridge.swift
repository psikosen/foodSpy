import CoreGraphics
import CoreImage
import CoreML
import Foundation
import UIKit

/// Bridge for SAM 2.1 CoreML models (Apple-optimized from HuggingFace)
/// These models provide MUCH higher quality segmentation than EdgeSAM
/// Models: https://huggingface.co/collections/apple/core-ml-segment-anything-2-66e4571a7234dc2560c3db26
///
/// SAM 2.1 Architecture (3 separate models):
/// - Image Encoder: Encodes image to feature embeddings
/// - Prompt Encoder: Encodes point/box prompts
/// - Mask Decoder: Decodes embeddings + prompts to high-quality masks
///
/// Output: High-quality 256x256 masks that upscale cleanly (much better than EdgeSAM)
final class SAM2Bridge {
    
    // Model variants supported (SAM 2.1 naming from Apple HuggingFace)
    // Models: https://huggingface.co/apple/coreml-sam2.1-small
    enum ModelVariant: String, CaseIterable {
        case small = "Small"
        case tiny = "Tiny"
        
        // Actual model names from HuggingFace apple/coreml-sam2.1-{variant}
        // Format: SAM2_1{Size}{ModelType}FLOAT16.mlpackage
        var imageEncoderName: String { "SAM2_1\(rawValue)ImageEncoderFLOAT16" }
        var promptEncoderName: String { "SAM2_1\(rawValue)PromptEncoderFLOAT16" }
        var maskDecoderName: String { "SAM2_1\(rawValue)MaskDecoderFLOAT16" }
    }
    
    private var imageEncoderModel: MLModel?
    private var promptEncoderModel: MLModel?
    private var maskDecoderModel: MLModel?
    private var modelsAvailable = false
    private var loadAttempted = false
    private var currentVariant: ModelVariant?
    
    // SAM 2 works with 1024x1024 input images
    private static let inputSize = 1024
    // Output mask size from SAM 2 decoder
    private static let maskSize = 256
    
    /// Check if models are available
    var hasModels: Bool { modelsAvailable }
    
    /// Get the currently loaded variant
    var variant: ModelVariant? { currentVariant }
    
    /// Load SAM 2 models, trying Small first, then Tiny
    func loadModels() throws {
        if loadAttempted {
            if !modelsAvailable {
                throw NSError(domain: "foodspy.ml", code: -14, 
                    userInfo: [NSLocalizedDescriptionKey: "SAM 2 models not available"])
            }
            return
        }
        loadAttempted = true
        
        // Try variants in order of quality
        let variants: [ModelVariant] = [.small, .tiny]
        
        for variant in variants {
            do {
                try loadVariant(variant)
                currentVariant = variant
                modelsAvailable = true
                print("[SAM2] Successfully loaded \(variant.rawValue) variant")
                return
            } catch {
                print("[SAM2] Failed to load \(variant.rawValue): \(error.localizedDescription)")
                continue
            }
        }
        
        // If we get here, no models loaded - try legacy EdgeSAM as fallback
        print("[SAM2] No SAM 2 models found, EdgeSAM may be used as fallback")
        modelsAvailable = false
        throw NSError(domain: "foodspy.ml", code: -14, 
            userInfo: [NSLocalizedDescriptionKey: "No SAM 2 models found in bundle"])
    }
    
    private func loadVariant(_ variant: ModelVariant) throws {
        let imageEncoderURL = try locateModel(name: variant.imageEncoderName)
        let promptEncoderURL = try locateModel(name: variant.promptEncoderName)
        let maskDecoderURL = try locateModel(name: variant.maskDecoderName)
        
        print("[SAM2] Loading \(variant.rawValue) image encoder...")
        imageEncoderModel = try MLModel(contentsOf: imageEncoderURL)
        
        print("[SAM2] Loading \(variant.rawValue) prompt encoder...")
        promptEncoderModel = try MLModel(contentsOf: promptEncoderURL)
        
        print("[SAM2] Loading \(variant.rawValue) mask decoder...")
        maskDecoderModel = try MLModel(contentsOf: maskDecoderURL)
    }
    
    /// Try to load models without throwing
    func tryLoadModels() -> Bool {
        if loadAttempted { return modelsAvailable }
        do {
            try loadModels()
            return true
        } catch {
            return false
        }
    }
    
    /// Encode image to embedding using SAM 2.1 image encoder
    /// Input: 1024x1024 RGB image
    /// Output: Feature tensor for decoder
    func encode(image: UIImage) throws -> MLMultiArray {
        try loadModels()
        guard let encoder = imageEncoderModel else {
            throw NSError(domain: "foodspy.ml", code: -10, 
                userInfo: [NSLocalizedDescriptionKey: "SAM 2 image encoder not loaded"])
        }
        
        print("[SAM2] Encoding image of size: \(image.size)")
        
        // Resize and prepare image for SAM 2 (1024x1024)
        let targetSize = CGSize(width: Self.inputSize, height: Self.inputSize)
        let resized = image.resizedForSAM2(to: targetSize)
        
        guard let pixelBuffer = resized.pixelBufferRGB(width: Self.inputSize, height: Self.inputSize) else {
            throw NSError(domain: "foodspy.ml", code: -15, 
                userInfo: [NSLocalizedDescriptionKey: "Failed to create pixel buffer"])
        }
        
        // SAM 2.1 image encoder expects "image" input
        let input = try MLDictionaryFeatureProvider(dictionary: ["image": pixelBuffer])
        let output = try encoder.prediction(from: input)
        
        print("[SAM2] Image encoder output features: \(output.featureNames)")
        
        // SAM 2.1 encoder outputs image embeddings
        // Try common output names
        for name in ["image_embeddings", "image_embedding", "embeddings", "features", "output", "vision_features", "backbone_fpn"] {
            if let embedding = output.featureValue(for: name)?.multiArrayValue {
                print("[SAM2] Found embedding '\(name)' with shape: \(embedding.shape)")
                return embedding
            }
        }
        
        // Fallback to first available MLMultiArray
        for name in output.featureNames {
            if let embedding = output.featureValue(for: name)?.multiArrayValue {
                print("[SAM2] Using fallback '\(name)' with shape: \(embedding.shape)")
                return embedding
            }
        }
        
        throw NSError(domain: "foodspy.ml", code: -11,
            userInfo: [NSLocalizedDescriptionKey: "No embedding output found. Available: \(output.featureNames)"])
    }
    
    /// Decode mask from embedding and point prompt
    /// SAM 2.1 uses separate Prompt Encoder and Mask Decoder
    /// Point: normalized (x, y) in [0,1]
    func decodeMask(embedding: MLMultiArray, point: CGPoint, label: Int = 1) throws -> MLMultiArray {
        try loadModels()
        guard let promptEncoder = promptEncoderModel, let maskDecoder = maskDecoderModel else {
            throw NSError(domain: "foodspy.ml", code: -12,
                userInfo: [NSLocalizedDescriptionKey: "SAM 2 prompt encoder or mask decoder not loaded"])
        }
        
        print("[SAM2] Decoding mask for point: (\(point.x), \(point.y))")
        
        // SAM 2 uses 1024x1024 coordinate space for points
        let scaledX = Float(point.x * Double(Self.inputSize))
        let scaledY = Float(point.y * Double(Self.inputSize))
        
        // Point coordinates [1, N, 2] where N = number of points
        let pointCoords = try MLMultiArray(shape: [1, 1, 2], dataType: .float32)
        pointCoords[[0, 0, 0] as [NSNumber]] = NSNumber(value: scaledX)
        pointCoords[[0, 0, 1] as [NSNumber]] = NSNumber(value: scaledY)
        
        // Point labels [1, N] - 1 = foreground, 0 = background
        let pointLabels = try MLMultiArray(shape: [1, 1], dataType: .float32)
        pointLabels[[0, 0] as [NSNumber]] = NSNumber(value: Float(label))
        
        // Step 1: Run prompt encoder to get sparse and dense embeddings
        var promptInputDict: [String: Any] = [:]
        promptInputDict["coords"] = pointCoords
        promptInputDict["labels"] = pointLabels
        promptInputDict["point_coords"] = pointCoords
        promptInputDict["point_labels"] = pointLabels
        
        let promptInput = try MLDictionaryFeatureProvider(dictionary: promptInputDict)
        let promptOutput = try promptEncoder.prediction(from: promptInput)
        
        print("[SAM2] Prompt encoder output features: \(promptOutput.featureNames)")
        
        // Get prompt embeddings
        var sparseEmbedding: MLMultiArray?
        var denseEmbedding: MLMultiArray?
        
        for name in promptOutput.featureNames {
            if let value = promptOutput.featureValue(for: name)?.multiArrayValue {
                print("[SAM2] Prompt output '\(name)' shape: \(value.shape)")
                if name.contains("sparse") {
                    sparseEmbedding = value
                } else if name.contains("dense") {
                    denseEmbedding = value
                } else if sparseEmbedding == nil {
                    sparseEmbedding = value  // First output as fallback
                }
            }
        }
        
        // Step 2: Run mask decoder with image embeddings + prompt embeddings
        var decoderInputDict: [String: Any] = [:]
        
        // Image embeddings from encoder
        decoderInputDict["image_embeddings"] = embedding
        decoderInputDict["image_embedding"] = embedding
        
        // Prompt embeddings
        if let sparse = sparseEmbedding {
            decoderInputDict["sparse_embeddings"] = sparse
            decoderInputDict["sparse_prompt_embeddings"] = sparse
        }
        if let dense = denseEmbedding {
            decoderInputDict["dense_embeddings"] = dense
            decoderInputDict["dense_prompt_embeddings"] = dense
        }
        
        // Point prompts (some decoders want these directly too)
        decoderInputDict["point_coords"] = pointCoords
        decoderInputDict["point_labels"] = pointLabels
        
        let decoderInput = try MLDictionaryFeatureProvider(dictionary: decoderInputDict)
        let decoderOutput = try maskDecoder.prediction(from: decoderInput)
        
        print("[SAM2] Mask decoder output features: \(decoderOutput.featureNames)")
        
        // Find mask output
        for name in ["masks", "low_res_masks", "mask", "output", "pred_masks", "low_res_mask"] {
            if let mask = decoderOutput.featureValue(for: name)?.multiArrayValue {
                print("[SAM2] Found mask '\(name)' with shape: \(mask.shape)")
                return mask
            }
        }
        
        // Fallback to first MLMultiArray
        for name in decoderOutput.featureNames {
            if let mask = decoderOutput.featureValue(for: name)?.multiArrayValue {
                print("[SAM2] Using fallback mask '\(name)' with shape: \(mask.shape)")
                return mask
            }
        }
        
        throw NSError(domain: "foodspy.ml", code: -13,
            userInfo: [NSLocalizedDescriptionKey: "No mask output found. Available: \(decoderOutput.featureNames)"])
    }
    
    /// Decode mask with multiple points (for better accuracy)
    func decodeMaskMultiPoint(embedding: MLMultiArray, points: [CGPoint], labels: [Int]) throws -> MLMultiArray {
        // For simplicity, use the first point - multi-point can be added later
        guard !points.isEmpty else {
            throw NSError(domain: "foodspy.ml", code: -16,
                userInfo: [NSLocalizedDescriptionKey: "No points provided"])
        }
        
        // Use primary point (first foreground point)
        let primaryIndex = labels.firstIndex(of: 1) ?? 0
        return try decodeMask(embedding: embedding, point: points[primaryIndex], label: labels[primaryIndex])
    }
    
    /// Locate model by name in bundle
    private func locateModel(name: String) throws -> URL {
        let fileManager = FileManager.default
        
        print("[SAM2] Looking for model: \(name)")
        
        // Check for compiled model (.mlmodelc)
        if let url = Bundle.main.url(forResource: name, withExtension: "mlmodelc") {
            print("[SAM2] ✓ Found compiled: \(url.path)")
            return url
        }
        
        // Check for mlpackage
        if let url = Bundle.main.url(forResource: name, withExtension: "mlpackage") {
            print("[SAM2] ✓ Found package: \(url.path)")
            return url
        }
        
        // Direct path checks
        let paths = [
            Bundle.main.bundlePath + "/\(name).mlmodelc",
            Bundle.main.bundlePath + "/\(name).mlpackage",
            Bundle.main.bundlePath + "/Frameworks/\(name).mlmodelc"
        ]
        
        for path in paths {
            if fileManager.fileExists(atPath: path) {
                print("[SAM2] ✓ Found at: \(path)")
                return URL(fileURLWithPath: path)
            }
        }
        
        // Recursive search
        if let enumerator = fileManager.enumerator(atPath: Bundle.main.bundlePath) {
            while let element = enumerator.nextObject() as? String {
                if element.contains(name) && (element.hasSuffix(".mlmodelc") || element.hasSuffix(".mlpackage")) {
                    let fullPath = Bundle.main.bundlePath + "/" + element
                    print("[SAM2] ✓ Found via search: \(fullPath)")
                    return URL(fileURLWithPath: fullPath)
                }
            }
        }
        
        throw NSError(domain: "foodspy.ml", code: -14, userInfo: [
            NSLocalizedDescriptionKey: "Model '\(name)' not found. Add .mlpackage to Xcode Runner target."
        ])
    }
}

// MARK: - UIImage Extensions for SAM 2

private extension UIImage {
    /// Resize image maintaining aspect ratio for SAM 2
    func resizedForSAM2(to target: CGSize) -> UIImage {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1.0
        format.opaque = true
        
        let renderer = UIGraphicsImageRenderer(size: target, format: format)
        return renderer.image { context in
            // Fill with black to handle aspect ratio letterboxing
            UIColor.black.setFill()
            context.fill(CGRect(origin: .zero, size: target))
            
            // Calculate aspect-fit rect
            let aspectWidth = target.width / size.width
            let aspectHeight = target.height / size.height
            let aspectRatio = min(aspectWidth, aspectHeight)
            
            let scaledWidth = size.width * aspectRatio
            let scaledHeight = size.height * aspectRatio
            let x = (target.width - scaledWidth) / 2
            let y = (target.height - scaledHeight) / 2
            
            draw(in: CGRect(x: x, y: y, width: scaledWidth, height: scaledHeight))
        }
    }
    
    /// Create RGB pixel buffer for SAM 2 (expects RGB, not BGRA)
    func pixelBufferRGB(width: Int, height: Int) -> CVPixelBuffer? {
        var pixelBuffer: CVPixelBuffer?
        let attrs: [CFString: Any] = [
            kCVPixelBufferCGImageCompatibilityKey: true,
            kCVPixelBufferCGBitmapContextCompatibilityKey: true,
            kCVPixelBufferWidthKey: width,
            kCVPixelBufferHeightKey: height
        ]
        
        // Create BGRA buffer (what iOS uses natively)
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

// MARK: - MLMultiArray Extension for SAM 2 mask processing

extension MLMultiArray {
    /// Convert SAM 2 mask output to flat UInt8 array
    /// SAM 2 outputs higher quality masks than EdgeSAM
    /// Shape is typically [1, num_masks, H, W] where H,W = 256
    func sam2FlatArray(width targetWidth: Int, height targetHeight: Int) -> [UInt8] {
        let shapeCount = shape.count
        print("[SAM2 Mask] Shape: \(shape), target: \(targetWidth)x\(targetHeight)")
        
        // Get source dimensions
        let sourceHeight: Int
        let sourceWidth: Int
        
        switch shapeCount {
        case 4:
            // [batch, num_masks, H, W]
            sourceHeight = shape[2].intValue
            sourceWidth = shape[3].intValue
        case 3:
            // [num_masks, H, W]
            sourceHeight = shape[1].intValue
            sourceWidth = shape[2].intValue
        case 2:
            // [H, W]
            sourceHeight = shape[0].intValue
            sourceWidth = shape[1].intValue
        default:
            let side = Int(sqrt(Double(count)))
            sourceHeight = side
            sourceWidth = side
        }
        
        print("[SAM2 Mask] Source size: \(sourceWidth)x\(sourceHeight)")
        
        var output = [UInt8](repeating: 0, count: targetWidth * targetHeight)
        
        let scaleX = Double(sourceWidth) / Double(targetWidth)
        let scaleY = Double(sourceHeight) / Double(targetHeight)
        
        var positiveCount = 0
        
        // SAM 2 typically outputs multiple masks - use the first (highest quality)
        for y in 0..<targetHeight {
            let srcY = min(Int(Double(y) * scaleY), sourceHeight - 1)
            for x in 0..<targetWidth {
                let srcX = min(Int(Double(x) * scaleX), sourceWidth - 1)
                
                let value: Double
                switch shapeCount {
                case 4:
                    // Use first batch, first mask (usually best quality)
                    value = self[[0, 0, srcY, srcX] as [NSNumber]].doubleValue
                case 3:
                    value = self[[0, srcY, srcX] as [NSNumber]].doubleValue
                case 2:
                    value = self[[srcY, srcX] as [NSNumber]].doubleValue
                default:
                    let flatIdx = srcY * sourceWidth + srcX
                    value = flatIdx < count ? self[flatIdx].doubleValue : 0.0
                }
                
                // SAM 2 outputs logits - positive = inside mask
                // Use a slightly lower threshold for better boundary detection
                if value > -0.5 {
                    output[y * targetWidth + x] = 1
                    positiveCount += 1
                }
            }
        }
        
        let coverage = Double(positiveCount) / Double(targetWidth * targetHeight) * 100.0
        print("[SAM2 Mask] Coverage: \(String(format: "%.1f", coverage))%")
        
        return output
    }
}

