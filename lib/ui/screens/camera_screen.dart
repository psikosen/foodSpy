import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:fluttertoast/fluttertoast.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../models/food_models.dart';
import '../../services/database/food_database.dart';
import '../../services/database/food_repository.dart';
import '../../services/native/native_channels.dart';
import '../../services/volume_calculator.dart';
import '../../theme/palette.dart';
import '../widgets/food_selection_sheet.dart';
import '../widgets/multi_segment_overlay.dart';
import '../widgets/stability_reticle.dart';

enum CameraState {
  preview,       // Live camera preview
  capturing,     // Taking photo
  segmenting,    // Running auto-segmentation
  classifying,   // User classifying segments
  saving,        // Saving to history
}

class CameraScreen extends StatefulWidget {
  const CameraScreen({super.key});

  @override
  State<CameraScreen> createState() => _CameraScreenState();
}

class _CameraScreenState extends State<CameraScreen> {
  final NativeChannels _channels = NativeChannels();
  final FoodRepository _foodRepository = FoodRepository();
  final FoodDatabase _database = FoodDatabase.instance;
  final ImagePicker _imagePicker = ImagePicker();
  
  Stream<String>? _stabilityStream;
  bool _isStable = true;
  bool _hasReceivedStabilityData = false;
  bool _edgeSAMReady = false;
  
  CameraState _state = CameraState.preview;
  int? _textureId;
  
  // Segmentation state
  List<FoodSegment> _segments = [];
  int? _selectedSegmentId;
  String? _capturedImagePath;
  File? _uploadedImage; // For displaying uploaded image
  
  // Depth data for volume calculation
  double _backgroundDepth = 100.0;
  double _pixelSizeCm = 0.1;
  List<double> _depthValues = [];
  int _depthWidth = 0;
  int _depthHeight = 0;
  
  // Higher resolution masks for better quality (must match native side)
  // SAM 2 produces cleaner 1024x1024 masks vs EdgeSAM's 256->512 upscaled masks
  static const int _maskWidth = 1024;
  static const int _maskHeight = 1024;

  @override
  void initState() {
    super.initState();
    _initialize();
  }

  Future<void> _initialize() async {
    try {
      // Request camera permission first
      final status = await Permission.camera.request();
      if (!status.isGranted) {
        Fluttertoast.showToast(msg: 'Camera permission required');
        if (status.isPermanentlyDenied) {
          openAppSettings();
        }
        return;
      }

      final textureId = await _channels.initializeCamera();
      await _channels.startStream();
      setState(() {
        _textureId = textureId;
        _stabilityStream = _channels.stabilityStream();
      });
      
      // Check segmentation model status - SAM 2 preferred for quality
      try {
        final samStatus = await _channels.checkEdgeSAM();
        _edgeSAMReady = samStatus['modelsLoaded'] == true;
        final preferredModel = samStatus['preferredModel'] as String? ?? 'none';
        final sam2Available = samStatus['sam2Available'] == true;
        final sam2Variant = samStatus['sam2Variant'] as String? ?? 'none';
        
        debugPrint('[CameraScreen] Segmentation status:');
        debugPrint('  - Models loaded: $_edgeSAMReady');
        debugPrint('  - Preferred model: $preferredModel');
        debugPrint('  - SAM 2 available: $sam2Available ($sam2Variant)');
        
        if (_edgeSAMReady) {
          final modelName = sam2Available ? 'SAM 2 ($sam2Variant)' : 'EdgeSAM';
          final quality = sam2Available ? 'high-quality' : 'standard';
          Fluttertoast.showToast(
            msg: '$modelName ready - $quality segmentation',
            backgroundColor: sam2Available ? Palette.mint : Palette.lilac,
            textColor: Palette.deepText,
            toastLength: Toast.LENGTH_LONG,
          );
        } else {
          Fluttertoast.showToast(
            msg: 'Loading segmentation models...',
            backgroundColor: Palette.lilac,
          );
        }
      } catch (e) {
        debugPrint('[CameraScreen] Model check failed: $e');
        _edgeSAMReady = false;
      }
    } on PlatformException catch (e) {
      Fluttertoast.showToast(msg: 'Camera init failed: ${e.message}');
    }
  }

  Future<void> _captureAndSegment() async {
    if (_state != CameraState.preview) return;
    
    setState(() => _state = CameraState.capturing);
    
    try {
      // Capture photo
      final frame = await _channels.captureFrame();
      final double laplacian = (frame['laplacian'] as num).toDouble();
      if (laplacian < 50) {
        Fluttertoast.showToast(msg: 'Image may be blurry');
      }
      
      // Store depth data
      _depthValues = (frame['depthValues'] as List?)
          ?.map((v) => (v as num).toDouble())
          .toList() ?? [];
      _backgroundDepth = (frame['backgroundDepth'] as num?)?.toDouble() ?? 100.0;
      _pixelSizeCm = (frame['pixelSizeCm'] as num?)?.toDouble() ?? 0.1;
      _depthWidth = frame['depthWidth'] as int? ?? 0;
      _depthHeight = frame['depthHeight'] as int? ?? 0;
      _capturedImagePath = frame['imagePath'] as String?;
      _uploadedImage = null; // Clear any uploaded image
      
      await _runSegmentation();
    } catch (e) {
      Fluttertoast.showToast(msg: 'Capture failed: $e');
      _reset();
    }
  }

  Future<void> _pickAndSegment() async {
    if (_state != CameraState.preview) return;
    
    try {
      final pickedFile = await _imagePicker.pickImage(
        source: ImageSource.gallery,
        maxWidth: 2048,
        maxHeight: 2048,
        imageQuality: 90,
      );
      
      if (pickedFile == null) return;
      
      setState(() {
        _state = CameraState.capturing;
        _uploadedImage = File(pickedFile.path);
      });
      
      Fluttertoast.showToast(msg: 'Loading image...');
      
      // Load and encode the image
      final imageInfo = await _channels.loadImageFromPath(pickedFile.path);
      
      final double laplacian = (imageInfo['laplacian'] as num?)?.toDouble() ?? 100.0;
      if (laplacian < 50) {
        Fluttertoast.showToast(msg: 'Image may be blurry');
      }
      
      // Store image path and use default depth values for uploaded images
      _capturedImagePath = pickedFile.path;
      _depthWidth = _maskWidth ~/ 2;
      _depthHeight = _maskHeight ~/ 2;
      _depthValues = List.filled(_depthWidth * _depthHeight, _backgroundDepth);
      _backgroundDepth = 100.0;
      _pixelSizeCm = 0.1;
      
      await _runSegmentation();
    } catch (e) {
      Fluttertoast.showToast(msg: 'Failed to load image: $e');
      _reset();
    }
  }

  Future<void> _runSegmentation() async {
    // Generate mock depth if not available
    if (_depthValues.isEmpty) {
      _depthWidth = _maskWidth ~/ 2;
      _depthHeight = _maskHeight ~/ 2;
      _depthValues = List.filled(_depthWidth * _depthHeight, _backgroundDepth);
    }
    
    setState(() => _state = CameraState.segmenting);
    Fluttertoast.showToast(msg: 'Detecting food regions...');
    
    try {
      // Auto-segment the image
      final segments = await _channels.autoSegment();
      
      if (segments.isEmpty) {
        Fluttertoast.showToast(msg: 'No food detected. Try again with clearer image.');
        _reset();
        return;
      }
      
      // Check mask coverage to verify segmentation quality
      var totalMaskPixels = 0;
      for (final seg in segments) {
        totalMaskPixels += seg.mask.where((b) => b > 0).length;
      }
      final coverage = totalMaskPixels / (_maskWidth * _maskHeight) * 100;
      debugPrint('[Segmentation] Found ${segments.length} segments with ${coverage.toStringAsFixed(1)}% total coverage');
      
      Fluttertoast.showToast(
        msg: 'Found ${segments.length} food regions. Tap each to classify.',
        backgroundColor: Palette.mint,
        textColor: Palette.deepText,
      );
      
      setState(() {
        _segments = segments;
        _state = CameraState.classifying;
      });
    } on PlatformException catch (e) {
      debugPrint('[Segmentation] PlatformException: ${e.code} - ${e.message}');
      // Show a user-friendly error message
      final errorMsg = e.message ?? 'Analysis failed';
      Fluttertoast.showToast(
        msg: errorMsg,
        backgroundColor: Colors.red.shade400,
        textColor: Colors.white,
        toastLength: Toast.LENGTH_LONG,
      );
      _reset();
    } catch (e) {
      debugPrint('[Segmentation] Failed: $e');
      Fluttertoast.showToast(
        msg: 'Analysis failed. Please try again.',
        backgroundColor: Colors.red.shade400,
        textColor: Colors.white,
      );
      _reset();
    }
  }

  void _onSegmentTapped(FoodSegment segment) {
    if (_state != CameraState.classifying) return;
    
    setState(() => _selectedSegmentId = segment.id);
    _showClassificationSheet(segment);
  }

  void _showClassificationSheet(FoodSegment segment) {
    // Calculate volume for this segment
    final resizedMask = _resizeMask(
      mask: segment.mask,
      sourceWidth: _maskWidth,
      sourceHeight: _maskHeight,
      targetWidth: _depthWidth,
      targetHeight: _depthHeight,
    );
    
    final calculator = VolumeCalculator(
      backgroundDepthCm: _backgroundDepth,
      pixelSizeCm: _pixelSizeCm,
    );
    
    final volume = resizedMask.isNotEmpty && _depthValues.isNotEmpty
        ? calculator.calculate(_depthValues, resizedMask)
        : 50.0; // Default volume if depth unavailable
    
    final area = resizedMask.where((b) => b > 0).length * _pixelSizeCm * _pixelSizeCm;
    
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Palette.peach.withValues(alpha: 0.95),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
      builder: (_) => FoodSelectionSheet(
        repository: _foodRepository,
        estimatedVolume: volume,
        maskArea: area,
        onSelected: (item, nutrition) {
          // Update segment with classification
          final idx = _segments.indexWhere((s) => s.id == segment.id);
          if (idx >= 0) {
            _segments[idx].categoryName = _getCategoryName(item.categoryId);
            _segments[idx].foodName = item.name;
            _segments[idx].foodItemId = item.id;
            _segments[idx].calories = nutrition['calories'];
            _segments[idx].volumeCm3 = nutrition['volume_cm3'];
            _segments[idx].massG = nutrition['mass_g'];
          }
          setState(() => _selectedSegmentId = null);
          Navigator.pop(context);
          _checkAllClassified();
        },
      ),
    );
  }

  String _getCategoryName(int categoryId) {
    // Simple mapping - in real app, fetch from DB
    const categories = {
      1: 'Protein',
      2: 'Grain',
      3: 'Vegetable',
      4: 'Fruit',
      5: 'Dairy',
      6: 'Beverage',
    };
    return categories[categoryId] ?? 'Other';
  }

  void _checkAllClassified() {
    final allClassified = _segments.every((s) => s.foodName != null);
    if (allClassified && _segments.isNotEmpty) {
      Fluttertoast.showToast(msg: 'All items classified! Tap Save to log meal.');
    }
  }

  Future<void> _saveMeal() async {
    final classifiedSegments = _segments.where((s) => s.foodName != null).toList();
    if (classifiedSegments.isEmpty) {
      Fluttertoast.showToast(msg: 'Please classify at least one item');
      return;
    }
    
    setState(() => _state = CameraState.saving);
    
    try {
      // Copy image to permanent storage
      String imagePath = '';
      if (_capturedImagePath != null) {
        final appDir = await getApplicationDocumentsDirectory();
        final timestamp = DateTime.now().millisecondsSinceEpoch;
        imagePath = '${appDir.path}/meals/meal_$timestamp.jpg';
        
        final dir = Directory('${appDir.path}/meals');
        if (!await dir.exists()) {
          await dir.create(recursive: true);
        }
        
        await File(_capturedImagePath!).copy(imagePath);
      }
      
      // Create meal entry
      final totalCalories = classifiedSegments.fold<double>(
        0, (sum, s) => sum + (s.calories ?? 0),
      );
      
      final meal = MealEntry(
        id: 0,
        imagePath: imagePath,
        timestamp: DateTime.now(),
        totalCalories: totalCalories,
      );
      
      // Create segments for DB
      final dbSegments = classifiedSegments.asMap().entries.map((e) => MealSegment(
        id: 0,
        mealId: 0,
        foodItemId: e.value.foodItemId ?? 0,
        foodName: e.value.foodName ?? '',
        categoryName: e.value.categoryName ?? '',
        volumeCm3: e.value.volumeCm3 ?? 0,
        massG: e.value.massG ?? 0,
        calories: e.value.calories ?? 0,
        segmentIndex: e.key,
      )).toList();
      
      await _database.saveMealEntry(meal, dbSegments);
      
      Fluttertoast.showToast(
        msg: 'Meal saved! ${totalCalories.toStringAsFixed(0)} kcal',
        backgroundColor: Palette.mint,
        textColor: Palette.deepText,
      );
      
      _reset();
    } catch (e) {
      Fluttertoast.showToast(msg: 'Save failed: $e');
      setState(() => _state = CameraState.classifying);
    }
  }

  void _reset() {
    setState(() {
      _state = CameraState.preview;
      _segments = [];
      _selectedSegmentId = null;
      _capturedImagePath = null;
      _uploadedImage = null;
    });
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
      return mask.map((v) => v > 0 ? 1 : 0).toList();
    }
    final output = List<int>.filled(targetWidth * targetHeight, 0);
    for (var y = 0; y < targetHeight; y++) {
      final sourceY = (y * sourceHeight ~/ targetHeight).clamp(0, sourceHeight - 1);
      for (var x = 0; x < targetWidth; x++) {
        final sourceX = (x * sourceWidth ~/ targetWidth).clamp(0, sourceWidth - 1);
        output[y * targetWidth + x] = mask[sourceY * sourceWidth + sourceX] > 0 ? 1 : 0;
      }
    }
    return output;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('FoodSpy'),
        actions: [
          if (_state == CameraState.classifying)
            TextButton.icon(
              onPressed: _reset,
              icon: const Icon(Icons.refresh, color: Colors.white),
              label: const Text('Reset', style: TextStyle(color: Colors.white)),
            ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: Stack(
              fit: StackFit.expand,
              children: [
                // Show uploaded image or camera preview
                if (_uploadedImage != null)
                  Image.file(
                    _uploadedImage!,
                    fit: BoxFit.cover,
                  )
                else if (_textureId != null) 
                  Texture(textureId: _textureId!),
                
                // Dimmed overlay when not in preview mode
                if (_state != CameraState.preview)
                  Container(color: Colors.black.withValues(alpha: 0.4)),
                
                // Multi-segment overlay during classification
                if (_state == CameraState.classifying && _segments.isNotEmpty)
                  MultiSegmentOverlay(
                    segments: _segments,
                    maskWidth: _maskWidth,
                    maskHeight: _maskHeight,
                    selectedSegmentId: _selectedSegmentId,
                    onSegmentTapped: _onSegmentTapped,
                  ),
                
                // Loading indicator
                if (_state == CameraState.capturing || _state == CameraState.segmenting)
                  Center(
                    child: Container(
                      padding: const EdgeInsets.all(24),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.7),
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const CircularProgressIndicator(color: Palette.mint),
                          const SizedBox(height: 16),
                          Text(
                            _state == CameraState.capturing ? 'Loading...' : 'Analyzing plate...',
                            style: const TextStyle(color: Colors.white, fontSize: 16),
                          ),
                        ],
                      ),
                    ),
                  ),
                
                // Stability indicator (only in preview with camera)
                if (_state == CameraState.preview && _uploadedImage == null)
                  Positioned(
                    top: 20,
                    right: 20,
                    child: StreamBuilder<String>(
                      stream: _stabilityStream,
                      builder: (context, snapshot) {
                        if (snapshot.hasData) {
                          _hasReceivedStabilityData = true;
                          _isStable = snapshot.data == 'stable';
                        }
                        final displayStable = _hasReceivedStabilityData ? _isStable : true;
                        return StabilityReticle(isStable: displayStable);
                      },
                    ),
                  ),
                
                // Classification progress badge
                if (_state == CameraState.classifying)
                  Positioned(
                    top: 20,
                    left: 20,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      decoration: BoxDecoration(
                        color: Palette.mint,
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.restaurant, color: Palette.deepText, size: 18),
                          const SizedBox(width: 6),
                          Text(
                            '${_segments.where((s) => s.foodName != null).length}/${_segments.length} classified',
                            style: TextStyle(
                              color: Palette.deepText,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                
                // Source indicator (uploaded vs captured)
                if (_state == CameraState.classifying && _uploadedImage != null)
                  Positioned(
                    top: 20,
                    right: 20,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                      decoration: BoxDecoration(
                        color: Palette.lilac,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.photo_library, color: Palette.deepText, size: 16),
                          const SizedBox(width: 4),
                          Text(
                            'Uploaded',
                            style: TextStyle(
                              color: Palette.deepText,
                              fontSize: 12,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ),
          
          // Bottom controls
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
              child: _buildBottomControls(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBottomControls() {
    switch (_state) {
      case CameraState.preview:
        return Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            // Gallery upload button
            FloatingActionButton(
              heroTag: 'gallery',
              onPressed: _pickAndSegment,
              backgroundColor: Palette.lilac,
              child: const Icon(Icons.photo_library, size: 28),
            ),
            // Camera capture button
            FloatingActionButton.large(
              heroTag: 'capture',
              onPressed: _captureAndSegment,
              child: const Icon(Icons.camera_alt, size: 36),
            ),
            // Placeholder for symmetry
            const SizedBox(width: 56),
          ],
        );
        
      case CameraState.capturing:
      case CameraState.segmenting:
      case CameraState.saving:
        return const Center(
          child: Text(
            'Please wait...',
            style: TextStyle(color: Colors.grey, fontSize: 16),
          ),
        );
        
      case CameraState.classifying:
        final classifiedCount = _segments.where((s) => s.foodName != null).length;
        final totalCalories = _segments.fold<double>(0, (sum, s) => sum + (s.calories ?? 0));
        
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Instructions
            Text(
              classifiedCount == 0
                  ? 'Tap each food region to classify'
                  : classifiedCount < _segments.length
                      ? 'Tap unclassified regions (numbered)'
                      : 'All items classified!',
              style: TextStyle(
                color: classifiedCount == _segments.length ? Palette.mint : Colors.white,
                fontSize: 16,
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(height: 8),
            // Calorie summary
            if (classifiedCount > 0)
              Text(
                'Total: ${totalCalories.toStringAsFixed(0)} kcal',
                style: const TextStyle(
                  color: Palette.peach,
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                ),
              ),
            const SizedBox(height: 16),
            // Save button
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                ElevatedButton.icon(
                  onPressed: classifiedCount > 0 ? _saveMeal : null,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Palette.mint,
                    foregroundColor: Palette.deepText,
                    padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
                  ),
                  icon: const Icon(Icons.save),
                  label: const Text('Save Meal', style: TextStyle(fontSize: 16)),
                ),
              ],
            ),
          ],
        );
    }
  }
}
