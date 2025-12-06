import 'dart:math' as math;

class VolumeCalculator {
  const VolumeCalculator({required this.backgroundDepthCm, required this.pixelSizeCm});

  final double backgroundDepthCm;
  final double pixelSizeCm;

  double calculate(List<double> depthValues, List<int> mask) {
    if (depthValues.length != mask.length) {
      throw ArgumentError('Depth values and mask must be the same length.');
    }
    final pixelArea = pixelSizeCm * pixelSizeCm;
    double volume = 0;
    for (var i = 0; i < depthValues.length; i++) {
      if (mask[i] == 0) continue;
      final delta = math.max(0, backgroundDepthCm - depthValues[i]);
      volume += delta * pixelArea;
    }
    return volume;
  }
}
