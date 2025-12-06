import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import '../../theme/palette.dart';

class MaskOverlay extends StatefulWidget {
  const MaskOverlay({
    super.key,
    required this.mask,
    required this.width,
    required this.height,
  });

  final Uint8List mask;
  final int width;
  final int height;

  @override
  State<MaskOverlay> createState() => _MaskOverlayState();
}

class _MaskOverlayState extends State<MaskOverlay> {
  ui.Image? _image;

  @override
  void initState() {
    super.initState();
    _buildMaskImage();
  }

  Future<void> _buildMaskImage() async {
    final pixels = Uint8List(widget.width * widget.height * 4);
    for (var i = 0; i < widget.mask.length; i++) {
      final value = widget.mask[i] > 0 ? 1 : 0;
      final offset = i * 4;
      pixels[offset] = (Palette.accent.red).toInt();
      pixels[offset + 1] = (Palette.accent.green).toInt();
      pixels[offset + 2] = (Palette.accent.blue).toInt();
      pixels[offset + 3] = (value * 120).toInt();
    }
    final completer = Completer<ui.Image>();
    ui.decodeImageFromPixels(
      pixels,
      widget.width,
      widget.height,
      ui.PixelFormat.rgba8888,
      completer.complete,
    );
    final image = await completer.future;
    setState(() => _image = image);
  }

  @override
  Widget build(BuildContext context) {
    if (_image == null) {
      return const SizedBox.shrink();
    }
    return RawImage(
      image: _image,
      fit: BoxFit.cover,
    );
  }
}
