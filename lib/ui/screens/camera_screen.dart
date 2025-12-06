import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:fluttertoast/fluttertoast.dart';

import '../../services/database/food_repository.dart';
import '../../services/native/native_channels.dart';
import '../../services/volume_calculator.dart';
import '../../theme/palette.dart';
import '../widgets/food_selection_sheet.dart';
import '../widgets/mask_overlay.dart';
import '../widgets/stability_reticle.dart';

class CameraScreen extends StatefulWidget {
  const CameraScreen({super.key});

  @override
  State<CameraScreen> createState() => _CameraScreenState();
}

class _CameraScreenState extends State<CameraScreen> {
  final NativeChannels _channels = NativeChannels();
  final FoodRepository _foodRepository = FoodRepository();
  Stream<String>? _stabilityStream;
  bool _isStable = false;
  bool _capturing = false;
  int? _textureId;
  Uint8List? _mask;
  int _maskWidth = 0;
  int _maskHeight = 0;
  double _backgroundDepth = 0;
  double _pixelSizeCm = 0.1;
  List<double> _depthValues = const [];
  int _depthWidth = 0;
  int _depthHeight = 0;

  @override
  void initState() {
    super.initState();
    _initialize();
  }

  Future<void> _initialize() async {
    try {
      final textureId = await _channels.initializeCamera();
      await _channels.startStream();
      setState(() {
        _textureId = textureId;
        _stabilityStream = _channels.stabilityStream();
      });
    } on PlatformException catch (e) {
      Fluttertoast.showToast(msg: 'Camera init failed: ${e.message}');
    }
  }

  Future<void> _capture() async {
    if (!_isStable || _capturing) return;
    setState(() => _capturing = true);
    try {
      final frame = await _channels.captureFrame();
      final double laplacian = (frame['laplacian'] as num).toDouble();
      if (laplacian < 100) {
        Fluttertoast.showToast(msg: 'Too blurry. Hold steady.');
        setState(() => _capturing = false);
        return;
      }
      final depthValues = (frame['depthValues'] as List?)
              ?.map((value) => (value as num).toDouble())
              .toList() ??
          const [];
      _backgroundDepth = (frame['backgroundDepth'] as num?)?.toDouble() ?? 0;
      _pixelSizeCm = (frame['pixelSizeCm'] as num?)?.toDouble() ?? 0.1;
      _maskWidth = frame['width'] as int? ?? 0;
      _maskHeight = frame['height'] as int? ?? 0;
      _depthWidth = frame['depthWidth'] as int? ?? 0;
      _depthHeight = frame['depthHeight'] as int? ?? 0;
      if (depthValues.isEmpty || _depthWidth == 0 || _depthHeight == 0) {
        Fluttertoast.showToast(msg: 'Depth map unavailable. Please recapture.');
        setState(() => _capturing = false);
        return;
      }
      setState(() {
        _capturing = false;
        _depthValues = depthValues;
        _mask = null;
      });
      Fluttertoast.showToast(msg: 'Capture saved. Tap to segment.');
    } catch (e) {
      Fluttertoast.showToast(msg: 'Capture failed: $e');
      setState(() => _capturing = false);
    }
  }

  Future<void> _onTapDown(TapDownDetails details, BuildContext context) async {
    if (_textureId == null) return;
    try {
      final renderBox = context.findRenderObject() as RenderBox?;
      if (renderBox == null) return;
      final local = renderBox.globalToLocal(details.globalPosition);
      final size = renderBox.size;
      final normalizedX = local.dx / size.width;
      final normalizedY = local.dy / size.height;
      final maskBytes = await _channels.decodeMask(x: normalizedX, y: normalizedY);
      setState(() => _mask = maskBytes);
    } catch (e) {
      Fluttertoast.showToast(msg: 'Segmentation failed: $e');
    }
  }

  void _openFoodSelector() {
    if (_mask == null) {
      return;
    }
    if (_maskWidth == 0 || _maskHeight == 0) {
      Fluttertoast.showToast(msg: 'Mask dimensions missing. Capture again.');
      return;
    }
    if (_depthValues.isEmpty || _depthWidth == 0 || _depthHeight == 0) {
      Fluttertoast.showToast(msg: 'Depth data missing. Capture again.');
      return;
    }
    final resizedMask = _resizeMask(
      mask: _mask!,
      sourceWidth: _maskWidth,
      sourceHeight: _maskHeight,
      targetWidth: _depthWidth,
      targetHeight: _depthHeight,
    );
    if (resizedMask.isEmpty) {
      Fluttertoast.showToast(msg: 'Failed to align mask with depth map. Recapture and retry.');
      return;
    }
    final calculator = VolumeCalculator(
      backgroundDepthCm: _backgroundDepth,
      pixelSizeCm: _pixelSizeCm,
    );
    final volume = calculator.calculate(
      _depthValues,
      resizedMask,
    );
    final area = resizedMask.where((b) => b > 0).length * _pixelSizeCm * _pixelSizeCm;
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Palette.peach.withOpacity(0.9),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
      builder: (_) => FoodSelectionSheet(
        repository: _foodRepository,
        estimatedVolume: volume,
        maskArea: area,
        onSelected: (_, __) {},
      ),
    );
  }

  List<int> _resizeMask({
    required Uint8List mask,
    required int sourceWidth,
    required int sourceHeight,
    required int targetWidth,
    required int targetHeight,
  }) {
    if (sourceWidth <= 0 || sourceHeight <= 0 || targetWidth <= 0 || targetHeight <= 0) {
      return const [];
    }
    if (sourceWidth == targetWidth && sourceHeight == targetHeight) {
      return mask.map((value) => value > 0 ? 1 : 0).toList();
    }
    final output = List<int>.filled(targetWidth * targetHeight, 0);
    for (var y = 0; y < targetHeight; y++) {
      final sourceY = (y * sourceHeight ~/ targetHeight).clamp(0, sourceHeight - 1) as int;
      for (var x = 0; x < targetWidth; x++) {
        final sourceX = (x * sourceWidth ~/ targetWidth).clamp(0, sourceWidth - 1) as int;
        output[y * targetWidth + x] = mask[sourceY * sourceWidth + sourceX] > 0 ? 1 : 0;
      }
    }
    return output;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('PlateDepth'),
        actions: [
          IconButton(
            icon: const Icon(Icons.info_outline),
            onPressed: () async {
              final echo = await _channels.testEcho();
              Fluttertoast.showToast(msg: 'Bridge: $echo');
            },
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: GestureDetector(
              onTapDown: (details) => _onTapDown(details, context),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  if (_textureId != null) Texture(textureId: _textureId!),
                  if (_mask != null)
                    Positioned.fill(
                      child: MaskOverlay(
                        mask: _mask!,
                        width: _maskWidth,
                        height: _maskHeight,
                      ),
                    ),
                  Positioned(
                    top: 20,
                    right: 20,
                    child: StreamBuilder<String>(
                      stream: _stabilityStream,
                      builder: (context, snapshot) {
                        _isStable = snapshot.data == 'stable';
                        return StabilityReticle(isStable: _isStable);
                      },
                    ),
                  ),
                ],
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                ElevatedButton.icon(
                  onPressed: _mask != null ? _openFoodSelector : null,
                  icon: const Icon(Icons.restaurant_menu),
                  label: const Text('Classify'),
                ),
                FloatingActionButton(
                  onPressed: _isStable ? _capture : null,
                  child: _capturing
                      ? const CircularProgressIndicator()
                      : const Icon(Icons.camera_alt),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
