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
      _backgroundDepth = (frame['backgroundDepth'] as num).toDouble();
      _pixelSizeCm = (frame['pixelSizeCm'] as num).toDouble();
      _maskWidth = frame['width'] as int;
      _maskHeight = frame['height'] as int;
      setState(() => _capturing = false);
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
    if (_mask == null) return;
    final calculator = VolumeCalculator(
      backgroundDepthCm: _backgroundDepth,
      pixelSizeCm: _pixelSizeCm,
    );
    final volume = calculator.calculate(
      List<double>.filled(_mask!.length, _backgroundDepth - 0.5),
      _mask!.map((b) => b > 0 ? 1 : 0).toList(),
    );
    final area = _mask!.where((b) => b > 0).length * _pixelSizeCm * _pixelSizeCm;
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
