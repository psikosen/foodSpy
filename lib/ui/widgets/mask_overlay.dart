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
  bool _isBuilding = false;

  @override
  void initState() {
    super.initState();
    _buildMaskImage();
  }

  @override
  void didUpdateWidget(MaskOverlay oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Rebuild if mask data changed
    if (oldWidget.mask != widget.mask ||
        oldWidget.width != widget.width ||
        oldWidget.height != widget.height) {
      _buildMaskImage();
    }
  }

  Future<void> _buildMaskImage() async {
    if (_isBuilding) return;
    _isBuilding = true;

    final width = widget.width;
    final height = widget.height;
    
    if (width <= 0 || height <= 0 || widget.mask.isEmpty) {
      _isBuilding = false;
      return;
    }

    // Create RGBA pixel data with mask fill and outline
    final pixels = Uint8List(width * height * 4);
    
    // Define colors - use new color API
    const fillColor = Palette.accent;
    const outlineColor = Palette.mint;
    const fillAlpha = 80;  // Semi-transparent fill
    const outlineAlpha = 220;  // More opaque outline
    
    // Get RGB values using new API
    final fillR = (fillColor.r * 255.0).round() & 0xff;
    final fillG = (fillColor.g * 255.0).round() & 0xff;
    final fillB = (fillColor.b * 255.0).round() & 0xff;
    final outlineR = (outlineColor.r * 255.0).round() & 0xff;
    final outlineG = (outlineColor.g * 255.0).round() & 0xff;
    final outlineB = (outlineColor.b * 255.0).round() & 0xff;
    
    // First pass: fill mask regions
    for (var i = 0; i < widget.mask.length && i < width * height; i++) {
      final isMask = widget.mask[i] > 0;
      final offset = i * 4;
      
      if (isMask) {
        pixels[offset] = fillR;
        pixels[offset + 1] = fillG;
        pixels[offset + 2] = fillB;
        pixels[offset + 3] = fillAlpha;
      } else {
        pixels[offset] = 0;
        pixels[offset + 1] = 0;
        pixels[offset + 2] = 0;
        pixels[offset + 3] = 0;
      }
    }
    
    // Second pass: draw outline (where mask meets non-mask)
    for (var y = 1; y < height - 1; y++) {
      for (var x = 1; x < width - 1; x++) {
        final idx = y * width + x;
        if (idx >= widget.mask.length) continue;
        
        final current = widget.mask[idx] > 0;
        if (!current) continue;
        
        // Check 4-neighbors for edge detection
        final top = widget.mask[(y - 1) * width + x] > 0;
        final bottom = widget.mask[(y + 1) * width + x] > 0;
        final left = widget.mask[y * width + (x - 1)] > 0;
        final right = widget.mask[y * width + (x + 1)] > 0;
        
        // If any neighbor is different, this is an edge
        if (!top || !bottom || !left || !right) {
          final offset = idx * 4;
          pixels[offset] = outlineR;
          pixels[offset + 1] = outlineG;
          pixels[offset + 2] = outlineB;
          pixels[offset + 3] = outlineAlpha;
        }
      }
    }

    final completer = Completer<ui.Image>();
    ui.decodeImageFromPixels(
      pixels,
      width,
      height,
      ui.PixelFormat.rgba8888,
      completer.complete,
    );
    
    final image = await completer.future;
    _isBuilding = false;
    
    if (mounted) {
      setState(() => _image = image);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_image == null) {
      return const SizedBox.shrink();
    }
    return IgnorePointer(
      // Allow taps to pass through to camera for re-segmentation
      child: RawImage(
        image: _image,
        fit: BoxFit.cover,
      ),
    );
  }
}
