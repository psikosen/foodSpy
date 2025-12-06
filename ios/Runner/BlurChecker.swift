import CoreImage
import UIKit

enum BlurChecker {
  static func laplacianVariance(for image: UIImage) -> Double {
    guard let cgImage = image.cgImage else { return 0 }
    let ciImage = CIImage(cgImage: cgImage).applyingFilter("CIPhotoEffectMono")
    let kernel: [Float] = [
      -1, -1, -1,
      -1, 8, -1,
      -1, -1, -1,
    ]
    guard let filter = CIFilter(name: "CIConvolution3X3", parameters: [
      kCIInputImageKey: ciImage,
      "inputWeights": CIVector(values: kernel, count: 9),
      "inputBias": 0,
    ]) else { return 0 }
    guard let output = filter.outputImage else { return 0 }
    let context = CIContext(options: [CIContextOption.useSoftwareRenderer: false])
    guard let bitmap = context.createCGImage(output, from: output.extent) else { return 0 }

    let width = bitmap.width
    let height = bitmap.height
    let colorSpace = CGColorSpaceCreateDeviceGray()
    var data = [UInt8](repeating: 0, count: width * height)
    let contextRef = CGContext(
      data: &data,
      width: width,
      height: height,
      bitsPerComponent: 8,
      bytesPerRow: width,
      space: colorSpace,
      bitmapInfo: CGImageAlphaInfo.none.rawValue
    )
    contextRef?.draw(bitmap, in: CGRect(x: 0, y: 0, width: width, height: height))

    let mean = data.reduce(0.0) { $0 + Double($1) } / Double(data.count)
    let variance = data.reduce(0.0) { $0 + pow(Double($1) - mean, 2.0) } / Double(data.count)
    return variance
  }
}
