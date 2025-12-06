import 'package:flutter_test/flutter_test.dart';
import 'package:platedepth/services/volume_calculator.dart';

void main() {
  test('calculates volume for flat object', () {
    final calculator = VolumeCalculator(backgroundDepthCm: 3.0, pixelSizeCm: 0.1);
    final depth = List<double>.filled(4, 2.9);
    final mask = [1, 1, 1, 1];
    final volume = calculator.calculate(depth, mask);
    expect(volume, closeTo(0.04, 0.001));
  });

  test('returns higher volume for taller object', () {
    final calculator = VolumeCalculator(backgroundDepthCm: 5.0, pixelSizeCm: 0.2);
    final depth = [4.5, 4.0, 3.5, 5.0];
    final mask = [1, 1, 1, 0];
    final volume = calculator.calculate(depth, mask);
    expect(volume, greaterThan(0.2));
  });
}
