import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/services.dart';

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

  Stream<String> stabilityStream() {
    return _stabilityChannel.receiveBroadcastStream().map((event) => event.toString());
  }

  Future<String> testEcho() async {
    final result = await _methodChannel.invokeMethod<String>('echo');
    return result ?? 'unavailable';
  }
}
