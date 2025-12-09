import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Represents a single food segment detected by auto-segmentation
class FoodSegment {
  FoodSegment({
    required this.id,
    required this.mask,
    required this.bounds,
    required this.centerX,
    required this.centerY,
  });

  final int id;
  final Uint8List mask;
  final Rect bounds; // Normalized 0-1
  final double centerX;
  final double centerY;
  
  // Classification (set by user)
  String? categoryName;
  String? foodName;
  int? foodItemId;
  double? calories;
  double? volumeCm3;
  double? massG;
}

class Rect {
  const Rect({required this.x, required this.y, required this.width, required this.height});
  final double x, y, width, height;
}

class NativeChannels {
  NativeChannels({MethodChannel? methodChannel, EventChannel? stabilityChannel})
      : _methodChannel = methodChannel ?? const MethodChannel('platedepth/native'),
        _stabilityChannel = stabilityChannel ?? const EventChannel('platedepth/stability');

  final MethodChannel _methodChannel;
  final EventChannel _stabilityChannel;
  int? _textureId;

  Future<int> initializeCamera() async {
    final textureId = await _methodChannel.invokeMethod<int>('initializeCamera');
    if (textureId == null) {
      throw StateError('Texture initialization failed');
    }
    _textureId = textureId;
    return textureId;
  }

  int? get textureId => _textureId;

  Future<void> startStream() => _methodChannel.invokeMethod('startStream');

  Future<Map<String, dynamic>> captureFrame() async {
    final result = await _methodChannel.invokeMapMethod<String, dynamic>('captureFrame');
    if (result == null) {
      throw StateError('Capture failed');
    }
    return result;
  }

  Future<double> laplacianScore(Uint8List jpegBytes) async {
    final result = await _methodChannel.invokeMethod<double>('laplacianScore', jpegBytes);
    if (result == null) {
      throw StateError('Laplacian variance not available');
    }
    return result;
  }

  Future<Uint8List> decodeMask({required double x, required double y}) async {
    final result = await _methodChannel.invokeMethod<Uint8List>('decodeMask', {'x': x, 'y': y});
    if (result == null) {
      throw StateError('Decode mask failed');
    }
    return result;
  }

  /// Auto-segment the captured image to find all food regions
  Future<List<FoodSegment>> autoSegment() async {
    try {
      debugPrint('[NativeChannels] Calling autoSegment...');
      final result = await _methodChannel.invokeListMethod<Map>('autoSegment');
      
      if (result == null || result.isEmpty) {
        debugPrint('[NativeChannels] autoSegment returned null or empty');
        throw StateError('No food segments detected');
      }
      
      debugPrint('[NativeChannels] autoSegment returned ${result.length} segments');
      
      return result.map((item) {
        final map = Map<String, dynamic>.from(item);
        final boundsMap = Map<String, dynamic>.from(map['bounds'] as Map);
        
        // Handle mask data - may come as FlutterStandardTypedData or Uint8List
        final maskData = map['mask'];
        Uint8List mask;
        if (maskData is Uint8List) {
          mask = maskData;
        } else if (maskData is List) {
          mask = Uint8List.fromList(maskData.cast<int>());
        } else {
          // Fallback: treat as bytes
          mask = Uint8List.fromList(List<int>.from(maskData));
        }
        
        final segment = FoodSegment(
          id: map['id'] as int,
          mask: mask,
          bounds: Rect(
            x: (boundsMap['x'] as num).toDouble(),
            y: (boundsMap['y'] as num).toDouble(),
            width: (boundsMap['width'] as num).toDouble(),
            height: (boundsMap['height'] as num).toDouble(),
          ),
          centerX: (map['centerX'] as num).toDouble(),
          centerY: (map['centerY'] as num).toDouble(),
        );
        
        // Debug: log mask coverage
        final maskPixels = mask.where((b) => b > 0).length;
        debugPrint('[NativeChannels] Segment ${segment.id}: ${maskPixels} mask pixels (${(maskPixels * 100 / mask.length).toStringAsFixed(1)}%)');
        
        return segment;
      }).toList();
    } on PlatformException catch (e) {
      debugPrint('[NativeChannels] autoSegment PlatformException: ${e.code} - ${e.message}');
      // Re-throw with a cleaner message
      throw PlatformException(
        code: e.code,
        message: e.message ?? 'Segmentation failed',
        details: e.details,
      );
    }
  }

  /// Load an image from file path for processing
  /// Returns image info including dimensions and encoding status
  Future<Map<String, dynamic>> loadImageFromPath(String path) async {
    final result = await _methodChannel.invokeMapMethod<String, dynamic>('loadImageFromPath', path);
    if (result == null) {
      throw StateError('Failed to load image');
    }
    return result;
  }

  Stream<String> stabilityStream() {
    return _stabilityChannel.receiveBroadcastStream().map((event) => event.toString());
  }

  Future<String> testEcho() async {
    final result = await _methodChannel.invokeMethod<String>('echo');
    return result ?? 'unavailable';
  }

  /// Check EdgeSAM model status
  Future<Map<String, dynamic>> checkEdgeSAM() async {
    final result = await _methodChannel.invokeMapMethod<String, dynamic>('checkEdgeSAM');
    if (result == null) {
      return {'modelsLoaded': false, 'hasModels': false};
    }
    debugPrint('[NativeChannels] EdgeSAM status: $result');
    return result;
  }
}
