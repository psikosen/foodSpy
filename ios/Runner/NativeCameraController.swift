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
  private let edgeSAM = EdgeSAMBridge()
  private var embedding: MLMultiArray?

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

  func decodeMask(normalizedPoint: CGPoint, completion: @escaping (Data?, Error?) -> Void) {
    guard let _ = latestImage else {
      completion(nil, NSError(domain: "platedepth.camera", code: -5, userInfo: [NSLocalizedDescriptionKey: "No capture available"]))
      return
    }
    sessionQueue.async {
      let width = Int(self.latestDimensions.width)
      let height = Int(self.latestDimensions.height)
      if let embedding = self.embedding {
        do {
          let maskArray = try self.edgeSAM.decodeMask(embedding: embedding, point: normalizedPoint)
          let flattened = maskArray.flatArray(width: width, height: height)
          completion(Data(flattened), nil)
          return
        } catch {
          print("[EdgeSAM] decode failed, falling back to radial mask: \(error.localizedDescription)")
        }
      }

      var mask = [UInt8](repeating: 0, count: width * height)
      let centerX = Int(Double(width) * normalizedPoint.x)
      let centerY = Int(Double(height) * normalizedPoint.y)
      let radius = max(6, min(width, height) / 12)
      for y in max(0, centerY - radius)..<min(height, centerY + radius) {
        for x in max(0, centerX - radius)..<min(width, centerX + radius) {
          let dx = x - centerX
          let dy = y - centerY
          if dx * dx + dy * dy <= radius * radius {
            mask[y * width + x] = 1
          }
        }
      }
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
    if let cgImage = photo.cgImageRepresentation() {
      latestImage = UIImage(cgImage: cgImage.takeUnretainedValue())
      latestDimensions = CGSize(width: photo.resolvedSettings.photoDimensions.width, height: photo.resolvedSettings.photoDimensions.height)
      latestDepthData = depthData
      latestLaplacian = BlurChecker.laplacianVariance(for: latestImage!)
      do {
        embedding = try edgeSAM.encode(image: latestImage!)
      } catch {
        print("[EdgeSAM] Encode failed: \(error.localizedDescription)")
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
  func flatArray(width: Int, height: Int) -> [UInt8] {
    var output = [UInt8](repeating: 0, count: width * height)
    let count = min(output.count, self.count)
    for i in 0..<count {
      let value = self[i].doubleValue
      output[i] = value > 0.5 ? 1 : 0
    }
    return output
  }
}
