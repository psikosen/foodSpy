import AVFoundation
import CoreImage
import CoreML
import Flutter
import UIKit

final class NativeCameraController: NSObject, AVCapturePhotoCaptureDelegate, AVCaptureVideoDataOutputSampleBufferDelegate {
  private let session = AVCaptureSession()
  private let photoOutput = AVCapturePhotoOutput()
  private let videoOutput = AVCaptureVideoDataOutput()
  private let sessionQueue = DispatchQueue(label: "platedepth.camera.queue")
  private var textureId: Int64?
  private var texture: PreviewTexture?
  private var registry: FlutterTextureRegistry?
  private var latestImage: UIImage?
  private var latestDimensions: CGSize = .zero
  private var latestDepthData: AVDepthData?
  private var latestLaplacian: Double = 0
  
  // Use SAM 2 for high-quality segmentation (fallback to EdgeSAM if unavailable)
  private let sam2 = SAM2Bridge()
  private let edgeSAM = EdgeSAMBridge()  // Legacy fallback
  private var embedding: MLMultiArray?
  private var useSAM2 = true  // Prefer SAM 2 for quality

  func initialize(textureRegistry: FlutterTextureRegistry, completion: @escaping (Int64?, Error?) -> Void) {
    sessionQueue.async {
      do {
        self.session.beginConfiguration()
        self.session.sessionPreset = .photo

        guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back) else {
          throw NSError(domain: "platedepth.camera", code: -1, userInfo: [NSLocalizedDescriptionKey: "Camera unavailable"])
        }
        let input = try AVCaptureDeviceInput(device: device)
        if self.session.canAddInput(input) { self.session.addInput(input) }

        self.photoOutput.isHighResolutionCaptureEnabled = true
        self.photoOutput.isDepthDataDeliveryEnabled = self.photoOutput.isDepthDataDeliverySupported
        if self.session.canAddOutput(self.photoOutput) { self.session.addOutput(self.photoOutput) }

        self.videoOutput.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: Int(kCVPixelFormatType_32BGRA)]
        self.videoOutput.setSampleBufferDelegate(self, queue: self.sessionQueue)
        if self.session.canAddOutput(self.videoOutput) { self.session.addOutput(self.videoOutput) }

        let preview = PreviewTexture()
        let id = textureRegistry.register(preview)
        self.texture = preview
        self.textureId = id
        self.registry = textureRegistry
        self.session.commitConfiguration()
        completion(id, nil)
      } catch {
        completion(nil, error)
      }
    }
  }

  func startSession() {
    sessionQueue.async {
      if !self.session.isRunning {
        self.session.startRunning()
      }
    }
  }

  func capturePhoto(completion: @escaping ([String: Any]?, Error?) -> Void) {
    sessionQueue.async {
      let settings = AVCapturePhotoSettings(format: [AVVideoCodecKey: AVVideoCodecType.jpeg])
      settings.isHighResolutionPhotoEnabled = true
      settings.isDepthDataDeliveryEnabled = self.photoOutput.isDepthDataDeliverySupported
      self.photoOutput.capturePhoto(with: settings, delegate: PhotoDelegateWrapper(parent: self, completion: completion))
    }
  }

  // Higher resolution masks for better quality (SAM 2 can handle this)
  // SAM 2 produces native 256x256 masks that upscale beautifully to 1024
  private static let maskOutputWidth = 1024
  private static let maskOutputHeight = 1024
  
  /// Load and encode an image from file path for segmentation
  func loadImageFromPath(_ path: String, completion: @escaping (Error?) -> Void) {
    sessionQueue.async { [weak self] in
      guard let self = self else {
        completion(NSError(domain: "platedepth.camera", code: -30, userInfo: [NSLocalizedDescriptionKey: "Controller deallocated"]))
        return
      }
      
      guard let image = UIImage(contentsOfFile: path) else {
        completion(NSError(domain: "platedepth.camera", code: -31, userInfo: [NSLocalizedDescriptionKey: "Failed to load image from path"]))
        return
      }
      
      print("[LoadImage] Loaded image from path: \(path), size: \(image.size)")
      
      // Store as latest image
      self.latestImage = image
      self.latestDimensions = CGSize(width: image.size.width * image.scale, height: image.size.height * image.scale)
      self.latestLaplacian = BlurChecker.laplacianVariance(for: image)
      
      // Encode the image - prefer SAM 2 for higher quality
      do {
        if self.sam2.tryLoadModels() {
          self.useSAM2 = true
          let encoded = try self.sam2.encode(image: image)
          self.embedding = encoded
          print("[LoadImage] SAM 2 encoding complete, shape: \(encoded.shape)")
        } else {
          self.useSAM2 = false
          let encoded = try self.edgeSAM.encode(image: image)
          self.embedding = encoded
          print("[LoadImage] EdgeSAM fallback encoding, shape: \(encoded.shape)")
        }
        completion(nil)
      } catch {
        print("[LoadImage] Encoding failed: \(error.localizedDescription)")
        completion(error)
      }
    }
  }
  
  /// Get info about the currently loaded image
  func getLoadedImageInfo() -> [String: Any]? {
    guard let image = latestImage else { return nil }
    return [
      "width": Int(latestDimensions.width),
      "height": Int(latestDimensions.height),
      "laplacian": latestLaplacian,
      "hasEmbedding": embedding != nil
    ]
  }
  
  /// Auto-segment the entire image to find all distinct food regions using EdgeSAM
  /// Returns array of segment data, each containing mask bytes and bounding box
  func autoSegment(completion: @escaping ([[String: Any]]?, Error?) -> Void) {
    guard latestImage != nil else {
      completion(nil, NSError(domain: "platedepth.camera", code: -5, userInfo: [NSLocalizedDescriptionKey: "No capture available. Please take a photo first."]))
      return
    }
    
    sessionQueue.async { [weak self] in
      guard let self = self else {
        completion(nil, NSError(domain: "platedepth.camera", code: -30, userInfo: [NSLocalizedDescriptionKey: "Controller deallocated"]))
        return
      }
      
      let width = Self.maskOutputWidth
      let height = Self.maskOutputHeight
      
      // Check model status - prefer SAM 2 for quality
      let hasSAM2 = self.sam2.hasModels
      let hasEdgeSAM = self.edgeSAM.hasModels
      let hasEmbedding = self.embedding != nil
      
      print("[AutoSegment] Model Status:")
      print("  - SAM 2 available: \(hasSAM2) (variant: \(self.sam2.variant?.rawValue ?? "none"))")
      print("  - EdgeSAM available: \(hasEdgeSAM)")
      print("  - Using SAM 2: \(self.useSAM2)")
      print("  - Embedding available: \(hasEmbedding)")
      if let emb = self.embedding {
        print("  - Embedding shape: \(emb.shape)")
      }
      
      guard hasSAM2 || hasEdgeSAM else {
        let error = NSError(domain: "foodspy.ml", code: -40, userInfo: [
          NSLocalizedDescriptionKey: "No segmentation models loaded. Add SAM 2 or EdgeSAM .mlpackage files to Xcode."
        ])
        completion(nil, error)
        return
      }
      
      guard hasEmbedding else {
        let error = NSError(domain: "foodspy.ml", code: -41, userInfo: [
          NSLocalizedDescriptionKey: "Image encoding failed. Try capturing again."
        ])
        completion(nil, error)
        return
      }
      
      if self.useSAM2 && hasSAM2 {
        print("[AutoSegment] Running SAM 2 segmentation (high quality)...")
        self.autoSegmentWithSAM2(width: width, height: height, completion: completion)
      } else {
        print("[AutoSegment] Running EdgeSAM segmentation (fallback)...")
        self.autoSegmentWithEdgeSAM(width: width, height: height, completion: completion)
      }
    }
  }
  
  /// SAM 2 high-quality segmentation with denser grid sampling
  private func autoSegmentWithSAM2(width: Int, height: Int, completion: @escaping ([[String: Any]]?, Error?) -> Void) {
    guard let embedding = self.embedding else {
      completion(nil, NSError(domain: "foodspy.ml", code: -20, userInfo: [NSLocalizedDescriptionKey: "No embedding available"]))
      return
    }
    
    print("[SAM2] Starting high-quality segmentation")
    print("[SAM2] Embedding shape: \(embedding.shape)")
    print("[SAM2] Output size: \(width)x\(height)")
    
    // Denser grid for SAM 2 - 6x6 = 36 points for better coverage
    let gridSize = 6
    let margin: Double = 0.12  // Slightly smaller margin for better edge detection
    let step = (1.0 - 2 * margin) / Double(gridSize - 1)
    
    var allMasks: [(mask: [UInt8], bounds: CGRect, centerPoint: CGPoint, coverage: Double, score: Double)] = []
    var successCount = 0
    var failCount = 0
    
    // Sample masks at grid points
    for row in 0..<gridSize {
      for col in 0..<gridSize {
        let x = margin + Double(col) * step
        let y = margin + Double(row) * step
        let point = CGPoint(x: x, y: y)
        
        do {
          let maskArray = try self.sam2.decodeMask(embedding: embedding, point: point)
          let flatMask = maskArray.sam2FlatArray(width: width, height: height)
          
          // Calculate coverage, bounds, and quality metrics
          var minX = width, maxX = 0, minY = height, maxY = 0
          var count = 0
          var sumX = 0, sumY = 0
          
          for py in 0..<height {
            for px in 0..<width {
              if flatMask[py * width + px] > 0 {
                count += 1
                minX = min(minX, px)
                maxX = max(maxX, px)
                minY = min(minY, py)
                maxY = max(maxY, py)
                sumX += px
                sumY += py
              }
            }
          }
          
          let coverage = Double(count) / Double(width * height)
          successCount += 1
          
          // Filter masks by coverage - SAM 2 produces cleaner masks so we can be stricter
          // Food items typically cover 1-50% of the image
          if coverage >= 0.01 && coverage <= 0.50 && maxX > minX && maxY > minY {
            let bounds = CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
            let centroidX = Double(sumX) / Double(count) / Double(width)
            let centroidY = Double(sumY) / Double(count) / Double(height)
            
            // Calculate compactness score (how "blob-like" the mask is)
            let boundingArea = Double((maxX - minX) * (maxY - minY))
            let compactness = boundingArea > 0 ? Double(count) / boundingArea : 0
            
            allMasks.append((
              mask: flatMask,
              bounds: bounds,
              centerPoint: CGPoint(x: centroidX, y: centroidY),
              coverage: coverage,
              score: compactness
            ))
            
            print("[SAM2] Point (\(String(format: "%.2f", x)), \(String(format: "%.2f", y))) -> \(String(format: "%.1f", coverage * 100))% coverage, compactness: \(String(format: "%.2f", compactness))")
          } else {
            print("[SAM2] Point (\(String(format: "%.2f", x)), \(String(format: "%.2f", y))) -> filtered (coverage: \(String(format: "%.1f", coverage * 100))%)")
          }
        } catch {
          failCount += 1
          print("[SAM2] Point (\(String(format: "%.2f", x)), \(String(format: "%.2f", y))) -> failed: \(error.localizedDescription)")
        }
      }
    }
    
    print("[SAM2] Grid sampling: \(successCount) success, \(failCount) failed, \(allMasks.count) valid masks")
    
    if allMasks.isEmpty {
      // Fallback to EdgeSAM if SAM 2 fails
      print("[SAM2] No masks found, trying EdgeSAM fallback...")
      self.autoSegmentWithEdgeSAM(width: width, height: height, completion: completion)
      return
    }
    
    // Cluster and deduplicate masks with stricter IoU for SAM 2
    let clustered = self.clusterMasksSAM2(allMasks.map { ($0.mask, $0.bounds, $0.centerPoint, $0.score) }, width: width, height: height)
    
    print("[SAM2] Clustered into \(clustered.count) distinct segments")
    
    // Apply post-processing for cleaner boundaries
    let processed = clustered.map { segment -> (mask: [UInt8], bounds: CGRect, centerPoint: CGPoint) in
      let smoothedMask = self.smoothMask(segment.mask, width: width, height: height)
      return (mask: smoothedMask, bounds: segment.bounds, centerPoint: segment.centerPoint)
    }
    
    let response = self.segmentsToResponse(processed, width: width, height: height)
    completion(response, nil)
  }
  
  /// Cluster SAM 2 masks with quality scoring
  private func clusterMasksSAM2(_ masks: [(mask: [UInt8], bounds: CGRect, centerPoint: CGPoint, score: Double)], width: Int, height: Int) -> [(mask: [UInt8], bounds: CGRect, centerPoint: CGPoint)] {
    guard !masks.isEmpty else { return [] }
    
    // Sort by quality score (compactness) descending - prefer well-formed masks
    let sorted = masks.sorted { $0.score > $1.score }
    
    var used = [Bool](repeating: false, count: sorted.count)
    var clusters: [(mask: [UInt8], bounds: CGRect, centerPoint: CGPoint)] = []
    let iouThreshold: Double = 0.6  // Higher threshold for SAM 2's cleaner masks
    
    for i in 0..<sorted.count {
      if used[i] { continue }
      
      used[i] = true
      
      // Find all masks similar to this one
      for j in (i + 1)..<sorted.count {
        if used[j] { continue }
        
        let iou = calculateIoU(sorted[i].mask, sorted[j].mask)
        if iou > iouThreshold {
          used[j] = true
        }
      }
      
      // Use the highest-scoring mask in this cluster
      clusters.append((mask: sorted[i].mask, bounds: sorted[i].bounds, centerPoint: sorted[i].centerPoint))
    }
    
    // Return top 8 segments by quality
    return Array(clusters.prefix(8))
  }
  
  /// Smooth mask boundaries using morphological operations
  private func smoothMask(_ mask: [UInt8], width: Int, height: Int) -> [UInt8] {
    var result = mask
    
    // Simple 3x3 median filter for smoothing
    for y in 1..<(height - 1) {
      for x in 1..<(width - 1) {
        var neighbors: [UInt8] = []
        for dy in -1...1 {
          for dx in -1...1 {
            neighbors.append(mask[(y + dy) * width + (x + dx)])
          }
        }
        neighbors.sort()
        result[y * width + x] = neighbors[4]  // Median of 9
      }
    }
    
    return result
  }
  
  /// EdgeSAM-based auto-segmentation using grid point sampling (legacy fallback)
  private func autoSegmentWithEdgeSAM(width: Int, height: Int, completion: @escaping ([[String: Any]]?, Error?) -> Void) {
    guard let embedding = self.embedding else {
      completion(nil, NSError(domain: "platedepth.ml", code: -20, userInfo: [NSLocalizedDescriptionKey: "No embedding available"]))
      return
    }
    
    print("[EdgeSAM] Starting point-grid segmentation (fallback)")
    print("[EdgeSAM] Embedding shape: \(embedding.shape)")
    
    // Grid of points to sample - 5x5 = 25 points focused on center
    let gridSize = 5
    let margin: Double = 0.15 // Avoid edges where plate rim usually is
    let step = (1.0 - 2 * margin) / Double(gridSize - 1)
    
    var allMasks: [(mask: [UInt8], bounds: CGRect, centerPoint: CGPoint, coverage: Double)] = []
    var successCount = 0
    var failCount = 0
    
    // Sample masks at grid points
    for row in 0..<gridSize {
      for col in 0..<gridSize {
        let x = margin + Double(col) * step
        let y = margin + Double(row) * step
        let point = CGPoint(x: x, y: y)
        
        do {
          let maskArray = try self.edgeSAM.decodeMask(embedding: embedding, point: point)
          let flatMask = maskArray.flatArray(width: width, height: height)
          
          // Calculate coverage and bounds
          var minX = width, maxX = 0, minY = height, maxY = 0
          var count = 0
          var sumX = 0, sumY = 0
          
          for py in 0..<height {
            for px in 0..<width {
              if flatMask[py * width + px] > 0 {
                count += 1
                minX = min(minX, px)
                maxX = max(maxX, px)
                minY = min(minY, py)
                maxY = max(maxY, py)
                sumX += px
                sumY += py
              }
            }
          }
          
          let coverage = Double(count) / Double(width * height)
          successCount += 1
          
          // Filter: ignore too small (<0.5%) or too large (>70%) masks
          if coverage >= 0.005 && coverage <= 0.70 && maxX > minX && maxY > minY {
            let bounds = CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
            // Use actual mask centroid, not the query point
            let centroidX = Double(sumX) / Double(count) / Double(width)
            let centroidY = Double(sumY) / Double(count) / Double(height)
            allMasks.append((mask: flatMask, bounds: bounds, centerPoint: CGPoint(x: centroidX, y: centroidY), coverage: coverage))
            print("[EdgeSAM] Point (\(String(format: "%.2f", x)), \(String(format: "%.2f", y))) -> mask \(String(format: "%.1f", coverage * 100))% coverage")
          } else {
            print("[EdgeSAM] Point (\(String(format: "%.2f", x)), \(String(format: "%.2f", y))) -> filtered (coverage: \(String(format: "%.1f", coverage * 100))%)")
          }
        } catch {
          failCount += 1
          print("[EdgeSAM] Point (\(String(format: "%.2f", x)), \(String(format: "%.2f", y))) -> decode failed: \(error.localizedDescription)")
        }
      }
    }
    
    print("[EdgeSAM] Grid sampling complete: \(successCount) success, \(failCount) failed, \(allMasks.count) valid masks")
    
    if allMasks.isEmpty {
      completion(nil, NSError(domain: "platedepth.ml", code: -21, userInfo: [
        NSLocalizedDescriptionKey: "No food segments detected. Try repositioning the camera."
      ]))
      return
    }
    
    // Cluster similar masks using IoU (Intersection over Union)
    let segments = self.clusterMasks(allMasks.map { ($0.mask, $0.bounds, $0.centerPoint) }, width: width, height: height)
    
    print("[EdgeSAM] Clustered \(allMasks.count) masks into \(segments.count) distinct segments")
    
    // Convert to response format
    let response = self.segmentsToResponse(segments, width: width, height: height)
    completion(response, nil)
  }
  
  
  /// Convert segments to response format
  private func segmentsToResponse(_ segments: [(mask: [UInt8], bounds: CGRect, centerPoint: CGPoint)], width: Int, height: Int) -> [[String: Any]] {
    var response: [[String: Any]] = []
    for (index, segment) in segments.enumerated() {
      response.append([
        "id": index,
        "mask": Data(segment.mask),
        "bounds": [
          "x": segment.bounds.origin.x / CGFloat(width),
          "y": segment.bounds.origin.y / CGFloat(height),
          "width": segment.bounds.width / CGFloat(width),
          "height": segment.bounds.height / CGFloat(height)
        ],
        "centerX": segment.centerPoint.x,
        "centerY": segment.centerPoint.y
      ])
    }
    return response
  }
  
  /// Cluster masks by IoU similarity, keeping the best representative of each cluster
  private func clusterMasks(_ masks: [(mask: [UInt8], bounds: CGRect, centerPoint: CGPoint)], width: Int, height: Int) -> [(mask: [UInt8], bounds: CGRect, centerPoint: CGPoint)] {
    guard !masks.isEmpty else { return [] }
    
    var used = [Bool](repeating: false, count: masks.count)
    var clusters: [(mask: [UInt8], bounds: CGRect, centerPoint: CGPoint)] = []
    let iouThreshold: Double = 0.5 // Masks with >50% IoU are considered same object
    
    for i in 0..<masks.count {
      if used[i] { continue }
      
      var clusterMasks: [Int] = [i]
      used[i] = true
      
      // Find all masks similar to this one
      for j in (i + 1)..<masks.count {
        if used[j] { continue }
        
        let iou = calculateIoU(masks[i].mask, masks[j].mask)
        if iou > iouThreshold {
          clusterMasks.append(j)
          used[j] = true
        }
      }
      
      // Use the first mask in cluster (usually good quality since grid is systematic)
      clusters.append(masks[i])
    }
    
    // Limit to reasonable number of segments (max 8)
    return Array(clusters.prefix(8))
  }
  
  /// Calculate Intersection over Union for two binary masks
  private func calculateIoU(_ mask1: [UInt8], _ mask2: [UInt8]) -> Double {
    var intersection = 0
    var union = 0
    
    for i in 0..<min(mask1.count, mask2.count) {
      let a = mask1[i] > 0
      let b = mask2[i] > 0
      if a && b { intersection += 1 }
      if a || b { union += 1 }
    }
    
    return union > 0 ? Double(intersection) / Double(union) : 0.0
  }
  
  func decodeMask(normalizedPoint: CGPoint, completion: @escaping (Data?, Error?) -> Void) {
    guard let image = latestImage else {
      completion(nil, NSError(domain: "foodspy.camera", code: -5, userInfo: [NSLocalizedDescriptionKey: "No capture available. Please take a photo first."]))
      return
    }
    sessionQueue.async {
      let width = Self.maskOutputWidth
      let height = Self.maskOutputHeight
      
      print("[decodeMask] Generating mask at \(width)x\(height) for tap at (\(normalizedPoint.x), \(normalizedPoint.y))")
      
      // Try SAM 2 first for better quality masks
      if let embedding = self.embedding, self.useSAM2 && self.sam2.hasModels {
        do {
          let maskArray = try self.sam2.decodeMask(embedding: embedding, point: normalizedPoint)
          let flattened = maskArray.sam2FlatArray(width: width, height: height)
          
          let positivePixels = flattened.filter { $0 > 0 }.count
          let coverage = Double(positivePixels) / Double(flattened.count)
          
          if coverage >= 0.001 && coverage <= 0.95 {
            print("[SAM2] decode success: \(positivePixels) pixels (\(String(format: "%.1f", coverage * 100))% coverage)")
            // Apply smoothing for cleaner edges
            let smoothed = self.smoothMask(flattened, width: width, height: height)
            completion(Data(smoothed), nil)
            return
          } else {
            print("[SAM2] Warning: Mask coverage \(String(format: "%.1f", coverage * 100))% outside expected range")
          }
        } catch {
          print("[SAM2] decode failed: \(error.localizedDescription)")
        }
      }
      
      // Fallback to EdgeSAM
      if let embedding = self.embedding {
        do {
          let maskArray = try self.edgeSAM.decodeMask(embedding: embedding, point: normalizedPoint)
          let flattened = maskArray.flatArray(width: width, height: height)
          
          // Verify mask has actual content (not all zeros or all ones)
          let positivePixels = flattened.filter { $0 > 0 }.count
          let coverage = Double(positivePixels) / Double(flattened.count)
          
          if coverage < 0.001 {
            print("[EdgeSAM] Warning: Mask appears empty, falling back to radial mask")
          } else if coverage > 0.95 {
            print("[EdgeSAM] Warning: Mask covers >95% of image, model may have failed")
          } else {
            print("[EdgeSAM] decode success: \(positivePixels) pixels (\(String(format: "%.1f", coverage * 100))% coverage)")
            completion(Data(flattened), nil)
            return
          }
        } catch {
          print("[EdgeSAM] decode failed: \(error.localizedDescription)")
        }
      } else {
        print("[decodeMask] No embedding available, using radial fallback mask")
      }

      // Fallback: create radial mask at tap point
      var mask = [UInt8](repeating: 0, count: width * height)
      let centerX = Int(Double(width) * normalizedPoint.x)
      let centerY = Int(Double(height) * normalizedPoint.y)
      let radius = max(30, min(width, height) / 6) // Visible radius for fallback
      
      for y in max(0, centerY - radius)..<min(height, centerY + radius) {
        for x in max(0, centerX - radius)..<min(width, centerX + radius) {
          let dx = x - centerX
          let dy = y - centerY
          if dx * dx + dy * dy <= radius * radius {
            mask[y * width + x] = 1
          }
        }
      }
      print("[decodeMask] Created fallback radial mask at (\(centerX), \(centerY)) radius=\(radius)")
      completion(Data(mask), nil)
    }
  }

  func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
    guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
    texture?.updateBuffer(pixelBuffer)
    if let textureId = textureId {
      registry?.textureFrameAvailable(textureId)
    }
  }

  private func cacheCapture(photo: AVCapturePhoto, depthData: AVDepthData?) {
    // iOS 15+ returns CGImage? directly, no need for takeUnretainedValue()
    guard let cgImage = photo.cgImageRepresentation() else {
      print("[cacheCapture] Failed to get CGImage from photo")
      // Try alternative: get from file data
      if let imageData = photo.fileDataRepresentation(), let uiImage = UIImage(data: imageData) {
        latestImage = uiImage
        latestDimensions = CGSize(width: uiImage.size.width * uiImage.scale, height: uiImage.size.height * uiImage.scale)
        latestDepthData = depthData
        latestLaplacian = BlurChecker.laplacianVariance(for: uiImage)
        print("[cacheCapture] Used fileDataRepresentation fallback, dimensions: \(latestDimensions)")
        encodeImageAsync()
      }
      return
    }
    
    latestImage = UIImage(cgImage: cgImage)
    latestDimensions = CGSize(
      width: CGFloat(photo.resolvedSettings.photoDimensions.width),
      height: CGFloat(photo.resolvedSettings.photoDimensions.height)
    )
    latestDepthData = depthData
    latestLaplacian = BlurChecker.laplacianVariance(for: latestImage!)
    print("[cacheCapture] Captured image: \(latestDimensions.width)x\(latestDimensions.height), laplacian: \(latestLaplacian)")
    encodeImageAsync()
  }
  
  private func encodeImageAsync() {
    guard let image = latestImage else { return }
    // Run encoding on background to not block capture completion
    DispatchQueue.global(qos: .userInitiated).async { [weak self] in
      guard let self = self else { return }
      
      // Try SAM 2 first for better quality
      if self.sam2.tryLoadModels() {
        do {
          let encoded = try self.sam2.encode(image: image)
          self.embedding = encoded
          self.useSAM2 = true
          print("[SAM2] Encode success, embedding shape: \(encoded.shape)")
          return
        } catch {
          print("[SAM2] Encode failed: \(error.localizedDescription)")
        }
      }
      
      // Fallback to EdgeSAM
      do {
        let encoded = try self.edgeSAM.encode(image: image)
        self.embedding = encoded
        self.useSAM2 = false
        print("[EdgeSAM] Fallback encode success, embedding shape: \(encoded.shape)")
      } catch {
        print("[EdgeSAM] Encode failed: \(error.localizedDescription)")
        self.embedding = nil
      }
    }
  }

  fileprivate func saveCaptureAndRespond(depthData: AVDepthData?, completion: @escaping ([String: Any]?, Error?) -> Void) {
    guard let image = latestImage else {
      completion(nil, NSError(domain: "platedepth.capture", code: -2, userInfo: [NSLocalizedDescriptionKey: "Missing image"]))
      return
    }
    let tempDir = FileManager.default.temporaryDirectory
    let imageURL = tempDir.appendingPathComponent("capture.jpg")
    let depthURL = tempDir.appendingPathComponent("depth_map.tif")
    var depthValues: [Double] = []
    var depthWidth = 0
    var depthHeight = 0
    var pixelSizeCm = 0.05
    var backgroundDepth = 0.0
    do {
      try image.jpegData(compressionQuality: 0.95)?.write(to: imageURL)
      if let depth = depthData {
        let converted = depth.converting(toDepthDataType: kCVPixelFormatType_DepthFloat32)
        if let depthBuffer = converted.depthDataMap {
          let ciImage = CIImage(cvPixelBuffer: depthBuffer)
          let context = CIContext(options: nil)
          if let depthTiff = context.tiffRepresentation(of: ciImage, format: .Lf, colorSpace: CGColorSpaceCreateDeviceGray()) {
            try depthTiff.write(to: depthURL)
          }
          let export = Self.exportDepthBuffer(depthBuffer)
          depthValues = export.values
          depthWidth = export.width
          depthHeight = export.height
          pixelSizeCm = export.pixelSizeCm
          backgroundDepth = export.backgroundDepth
        }
      }
      let payload: [String: Any] = [
        "imagePath": imageURL.path,
        "depthPath": depthURL.path,
        "width": Int(latestDimensions.width),
        "height": Int(latestDimensions.height),
        "laplacian": latestLaplacian,
        "backgroundDepth": backgroundDepth,
        "pixelSizeCm": pixelSizeCm,
        "depthValues": depthValues,
        "depthWidth": depthWidth,
        "depthHeight": depthHeight,
      ]
      completion(payload, nil)
    } catch {
      completion(nil, error)
    }
  }

  private static func exportDepthBuffer(_ buffer: CVPixelBuffer) -> (values: [Double], width: Int, height: Int, pixelSizeCm: Double, backgroundDepth: Double) {
    CVPixelBufferLockBaseAddress(buffer, .readOnly)
    defer { CVPixelBufferUnlockBaseAddress(buffer, .readOnly) }

    guard let baseAddress = CVPixelBufferGetBaseAddress(buffer)?.assumingMemoryBound(to: Float32.self) else {
      return ([], 0, 0, 0.0, 0.0)
    }

    let width = CVPixelBufferGetWidth(buffer)
    let height = CVPixelBufferGetHeight(buffer)
    let stride = CVPixelBufferGetBytesPerRow(buffer) / MemoryLayout<Float32>.size

    let downsampleFactor = max(1, width / 256)
    let targetWidth = max(1, width / downsampleFactor)
    let targetHeight = max(1, height / downsampleFactor)

    var output = [Double]()
    output.reserveCapacity(targetWidth * targetHeight)

    for y in stride(from: 0, to: height, by: downsampleFactor) {
      let row = baseAddress.advanced(by: y * stride)
      for x in stride(from: 0, to: width, by: downsampleFactor) {
        let depthMeters = Double(row[x])
        output.append(depthMeters * 100.0) // convert to centimeters for Flutter-side math
      }
    }

    let backgroundDepth = output.max() ?? 0.0
    let pixelSizeCm = 0.05 * Double(downsampleFactor)

    return (output, targetWidth, targetHeight, pixelSizeCm, backgroundDepth)
  }

  private class PhotoDelegateWrapper: NSObject, AVCapturePhotoCaptureDelegate {
    private weak var parent: NativeCameraController?
    private let completion: ([String: Any]?, Error?) -> Void

    init(parent: NativeCameraController, completion: @escaping ([String: Any]?, Error?) -> Void) {
      self.parent = parent
      self.completion = completion
    }

    func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?) {
      if let error {
        completion(nil, error)
        return
      }
      parent?.cacheCapture(photo: photo, depthData: photo.depthData)
    }

    func photoOutput(_ output: AVCapturePhotoOutput, didFinishCaptureFor resolvedSettings: AVCaptureResolvedPhotoSettings, error: Error?) {
      if let error {
        completion(nil, error)
        return
      }
      parent?.saveCaptureAndRespond(depthData: parent?.latestDepthData, completion: completion)
    }
  }
}

private extension MLMultiArray {
  /// Convert EdgeSAM mask output to flat UInt8 array, properly handling multi-dimensional output
  /// EdgeSAM outputs shape: [1, num_masks, H, W] where H,W are typically 256x256
  /// We take the first mask (index 0) which is usually the best quality
  func flatArray(width targetWidth: Int, height targetHeight: Int) -> [UInt8] {
    let shapeCount = shape.count
    print("[MLMultiArray] Converting mask with shape: \(shape), total count: \(count)")
    
    // Determine source dimensions based on shape
    let sourceHeight: Int
    let sourceWidth: Int
    
    if shapeCount == 4 {
      // Shape: [batch, num_masks, H, W] - EdgeSAM typical output
      sourceHeight = shape[2].intValue
      sourceWidth = shape[3].intValue
      print("[MLMultiArray] 4D mask detected: \(sourceHeight)x\(sourceWidth), \(shape[1]) masks available")
    } else if shapeCount == 3 {
      // Shape: [num_masks, H, W] or [batch, H, W]
      sourceHeight = shape[1].intValue
      sourceWidth = shape[2].intValue
      print("[MLMultiArray] 3D mask detected: \(sourceHeight)x\(sourceWidth)")
    } else if shapeCount == 2 {
      // Shape: [H, W]
      sourceHeight = shape[0].intValue
      sourceWidth = shape[1].intValue
      print("[MLMultiArray] 2D mask detected: \(sourceHeight)x\(sourceWidth)")
    } else {
      // Fallback: assume 1D, try to interpret as square
      let side = Int(sqrt(Double(count)))
      sourceHeight = side
      sourceWidth = side
      print("[MLMultiArray] Unknown shape, assuming \(side)x\(side)")
    }
    
    // Create output array at target size
    var output = [UInt8](repeating: 0, count: targetWidth * targetHeight)
    
    // Scale and threshold: map source mask to target dimensions
    let scaleX = Double(sourceWidth) / Double(targetWidth)
    let scaleY = Double(sourceHeight) / Double(targetHeight)
    
    var positiveCount = 0
    
    for y in 0..<targetHeight {
      let srcY = min(Int(Double(y) * scaleY), sourceHeight - 1)
      for x in 0..<targetWidth {
        let srcX = min(Int(Double(x) * scaleX), sourceWidth - 1)
        
        // Get value using proper multi-dimensional indexing
        let value: Double
        if shapeCount == 4 {
          // Index: [batch=0, mask=0, y, x]
          let idx = [0, 0, srcY, srcX] as [NSNumber]
          value = self[idx].doubleValue
        } else if shapeCount == 3 {
          // Index: [mask=0, y, x]
          let idx = [0, srcY, srcX] as [NSNumber]
          value = self[idx].doubleValue
        } else if shapeCount == 2 {
          // Index: [y, x]
          let idx = [srcY, srcX] as [NSNumber]
          value = self[idx].doubleValue
        } else {
          // 1D fallback
          let flatIdx = srcY * sourceWidth + srcX
          value = flatIdx < count ? self[flatIdx].doubleValue : 0.0
        }
        
        // EdgeSAM outputs logits; positive values = inside mask
        if value > 0.0 {
          output[y * targetWidth + x] = 1
          positiveCount += 1
        }
      }
    }
    
    let coverage = Double(positiveCount) / Double(targetWidth * targetHeight) * 100.0
    print("[MLMultiArray] Mask processed: \(positiveCount)/\(targetWidth * targetHeight) pixels positive (\(String(format: "%.1f", coverage))% coverage)")
    
    return output
  }
}
