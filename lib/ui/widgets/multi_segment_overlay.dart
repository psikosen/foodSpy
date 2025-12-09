import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import '../../services/native/native_channels.dart';

/// Overlay that displays multiple food segments with different colors
/// Segments should follow actual food boundaries from EdgeSAM or color detection
class MultiSegmentOverlay extends StatefulWidget {
  const MultiSegmentOverlay({
    super.key,
    required this.segments,
    required this.maskWidth,
    required this.maskHeight,
    required this.onSegmentTapped,
    this.selectedSegmentId,
  });

  final List<FoodSegment> segments;
  final int maskWidth;
  final int maskHeight;
  final void Function(FoodSegment segment) onSegmentTapped;
  final int? selectedSegmentId;

  @override
  State<MultiSegmentOverlay> createState() => _MultiSegmentOverlayState();
}

class _MultiSegmentOverlayState extends State<MultiSegmentOverlay> {
  ui.Image? _image;
  bool _isBuilding = false;
  int _totalMaskPixels = 0;

  // Distinct vibrant colors for different segments
  static const List<Color> segmentColors = [
    Color(0xFF7CC5C0), // Teal
    Color(0xFFE57373), // Coral Red  
    Color(0xFF81C784), // Soft Green
    Color(0xFFFFD54F), // Amber Yellow
    Color(0xFF64B5F6), // Sky Blue
    Color(0xFFBA68C8), // Lavender Purple
    Color(0xFFFF8A65), // Peach Orange
    Color(0xFF4DB6AC), // Aqua
  ];

  @override
  void initState() {
    super.initState();
    _buildCombinedImage();
  }

  @override
  void didUpdateWidget(MultiSegmentOverlay oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.segments != widget.segments ||
        oldWidget.selectedSegmentId != widget.selectedSegmentId) {
      _buildCombinedImage();
    }
  }

  Future<void> _buildCombinedImage() async {
    if (_isBuilding || widget.segments.isEmpty) return;
    _isBuilding = true;

    final width = widget.maskWidth;
    final height = widget.maskHeight;
    final pixels = Uint8List(width * height * 4);
    var totalMaskPixels = 0;

    // Draw each segment with its unique color
    for (var segIdx = 0; segIdx < widget.segments.length; segIdx++) {
      final segment = widget.segments[segIdx];
      final color = segmentColors[segIdx % segmentColors.length];
      final isSelected = segment.id == widget.selectedSegmentId;
      final isClassified = segment.foodName != null;
      
      // Alpha based on state - more visible for unclassified
      final fillAlpha = isSelected ? 160 : (isClassified ? 110 : 90);
      
      // Get RGB values
      final r = (color.r * 255.0).round() & 0xff;
      final g = (color.g * 255.0).round() & 0xff;
      final b = (color.b * 255.0).round() & 0xff;

      var segmentPixels = 0;
      
      // Draw the mask pixels
      for (var i = 0; i < segment.mask.length && i < width * height; i++) {
        if (segment.mask[i] > 0) {
          segmentPixels++;
          final offset = i * 4;
          // Only draw if pixel is not already set (first segment wins for overlaps)
          if (pixels[offset + 3] == 0) {
            pixels[offset] = r;
            pixels[offset + 1] = g;
            pixels[offset + 2] = b;
            pixels[offset + 3] = fillAlpha;
            totalMaskPixels++;
          }
        }
      }

      // Draw thicker outline for this segment (2px wide)
      final outlineAlpha = isSelected ? 255 : 220;
      for (var y = 2; y < height - 2; y++) {
        for (var x = 2; x < width - 2; x++) {
          final idx = y * width + x;
          if (idx >= segment.mask.length) continue;
          
          if (segment.mask[idx] > 0) {
            // Check for edge - any neighbor within 2px that's outside mask
            var isEdge = false;
            for (var dy = -2; dy <= 2 && !isEdge; dy++) {
              for (var dx = -2; dx <= 2 && !isEdge; dx++) {
                if (dx == 0 && dy == 0) continue;
                final nIdx = (y + dy) * width + (x + dx);
                if (nIdx >= 0 && nIdx < segment.mask.length && segment.mask[nIdx] == 0) {
                  isEdge = true;
                }
              }
            }
            
            if (isEdge) {
              final offset = idx * 4;
              pixels[offset] = 255;
              pixels[offset + 1] = 255;
              pixels[offset + 2] = 255;
              pixels[offset + 3] = outlineAlpha;
            }
          }
        }
      }
      
      debugPrint('[MultiSegmentOverlay] Segment $segIdx: $segmentPixels mask pixels');
    }

    _totalMaskPixels = totalMaskPixels;
    debugPrint('[MultiSegmentOverlay] Total mask coverage: $totalMaskPixels pixels (${(totalMaskPixels * 100 / (width * height)).toStringAsFixed(1)}%)');

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
    return LayoutBuilder(
      builder: (context, constraints) {
        return GestureDetector(
          onTapDown: (details) => _handleTap(details, context),
          child: Stack(
            fit: StackFit.expand,
            children: [
              // Combined mask image showing actual segment boundaries
              if (_image != null)
                RawImage(
                  image: _image,
                  fit: BoxFit.cover,
                ),
              // Segment labels positioned at mask centroids
              ...widget.segments.asMap().entries.map((entry) {
                final idx = entry.key;
                final segment = entry.value;
                final color = segmentColors[idx % segmentColors.length];
                final isClassified = segment.foodName != null;
                final isSelected = segment.id == widget.selectedSegmentId;
                
                // Position label at segment center
                final labelX = segment.centerX * constraints.maxWidth;
                final labelY = segment.centerY * constraints.maxHeight;
                
                return Positioned(
                  left: labelX - 24,
                  top: labelY - 14,
                  child: GestureDetector(
                    onTap: () => widget.onSegmentTapped(segment),
                    child: Container(
                      constraints: BoxConstraints(
                        minWidth: 28,
                        maxWidth: isClassified ? 120 : 48,
                      ),
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                      decoration: BoxDecoration(
                        color: isClassified 
                            ? color.withValues(alpha: 0.9) 
                            : Colors.black.withValues(alpha: 0.75),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                          color: isSelected ? Colors.white : color,
                          width: isSelected ? 2.5 : 1.5,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.4),
                            blurRadius: 4,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                      child: Text(
                        isClassified ? segment.foodName! : '${idx + 1}',
                        textAlign: TextAlign.center,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: isClassified ? 11 : 13,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
                );
              }),
            ],
          ),
        );
      },
    );
  }

  void _handleTap(TapDownDetails details, BuildContext context) {
    final renderBox = context.findRenderObject() as RenderBox?;
    if (renderBox == null) return;

    final localPos = renderBox.globalToLocal(details.globalPosition);
    final size = renderBox.size;
    final normalizedX = localPos.dx / size.width;
    final normalizedY = localPos.dy / size.height;

    // Find which segment was tapped based on mask
    for (final segment in widget.segments) {
      final maskX = (normalizedX * widget.maskWidth).toInt();
      final maskY = (normalizedY * widget.maskHeight).toInt();
      final maskIdx = maskY * widget.maskWidth + maskX;

      if (maskIdx >= 0 && maskIdx < segment.mask.length && segment.mask[maskIdx] > 0) {
        widget.onSegmentTapped(segment);
        return;
      }
    }
  }
}

