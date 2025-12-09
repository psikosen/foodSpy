# PlateDepth

Pastel-themed Flutter app for food volume estimation with native iOS camera, depth capture, and CoreML segmentation.

## Quick Start

```bash
# 1. Run setup to verify dependencies
./scripts/setup.sh

# 2. Download models (choose your platform)
./scripts/download_models.sh --coreml   # For iOS
./scripts/download_models.sh --onnx     # For Android

# 3. Integrate models into the project
./scripts/integrate_models.sh

# 4. Run the app
./scripts/run.sh
```

## Models

PlateDepth uses [EdgeSAM](https://github.com/chongzhou96/EdgeSAM) for fast, on-device image segmentation. EdgeSAM achieves 30+ FPS on iPhone 14 with high accuracy.

### Model Files

| Platform | Format | Files |
| --- | --- | --- |
| iOS/macOS | CoreML | `edge_sam_3x_encoder.mlpackage`, `edge_sam_3x_decoder.mlpackage` |
| Android | ONNX | `edge_sam_3x_encoder.onnx`, `edge_sam_3x_decoder.onnx` |
| Python | PyTorch | `edge_sam_3x.pth` |

### Download Models

```bash
# All platforms
./scripts/download_models.sh --all

# iOS only
./scripts/download_models.sh --coreml

# Android only  
./scripts/download_models.sh --onnx

# View help
./scripts/download_models.sh --help
```

Models are downloaded from Hugging Face: https://huggingface.co/spaces/chongzhou/EdgeSAM

## Scripts

| Script | Purpose |
| --- | --- |
| `scripts/setup.sh` | Validates local dependencies (Git, curl, unzip, Flutter) and prepares workspace directories. |
| `scripts/download_models.sh` | Downloads EdgeSAM models (CoreML, ONNX, or PyTorch) from Hugging Face. |
| `scripts/integrate_models.sh` | Copies downloaded models to platform-specific project locations. |
| `scripts/build.sh` | Runs `flutter pub get`, `flutter analyze`, `flutter test`, and platform builds. |
| `scripts/run.sh` | Fetches dependencies and launches the Flutter client. |
| `scripts/convert_edgesam.py` | Converts PyTorch weights to CoreML/ONNX (optional, use pre-converted models). |
| `scripts/ci/run_checks.sh` | CI entrypoint that delegates to `scripts/build.sh`. |

## iOS Setup

1. Download CoreML models:
   ```bash
   ./scripts/download_models.sh --coreml
   ./scripts/integrate_models.sh ios
   ```

2. Open `ios/Runner.xcworkspace` in Xcode

3. Add the `.mlpackage` files to the Xcode project:
   - Drag `edge_sam_3x_encoder.mlpackage` and `edge_sam_3x_decoder.mlpackage` from `ios/Runner/` into the Xcode project navigator
   - Check "Copy items if needed"
   - Ensure target membership includes "Runner"

4. Build and run on device (requires real device for camera and depth)

## Android Setup

1. Download ONNX models:
   ```bash
   ./scripts/download_models.sh --onnx
   ./scripts/integrate_models.sh android
   ```

2. Add ONNX Runtime dependency to `android/app/build.gradle`:
   ```gradle
   dependencies {
       implementation "com.microsoft.onnxruntime:onnxruntime-android:1.16.3"
   }
   ```

3. Build and run:
   ```bash
   flutter build apk --debug
   flutter run
   ```

## Development

### Prerequisites

- Flutter 3.3.0+ 
- Xcode 14+ (for iOS)
- Android Studio with SDK 33+ (for Android)
- curl or wget (for model download)

### Running Tests

```bash
flutter test
```

### Building

```bash
# Full build pipeline
./scripts/build.sh

# Platform-specific
flutter build ios --no-codesign  # macOS only
flutter build apk --debug        # Android
flutter build linux              # Linux desktop
```

### Environment Variables

| Variable | Purpose |
| --- | --- |
| `PLATEDEPTH_DEVICE` | Target device ID for `flutter run` |
| `ANDROID_HOME` | Android SDK path |

## Task Tracker

See [`task.md`](task.md) for the current delivery checklist.

## Architecture

```
lib/
├── app.dart              # App root widget
├── main.dart             # Entry point
├── data/                 # Seed data
├── models/               # Data models
├── services/
│   ├── database/         # SQLite database
│   ├── native/           # Platform channels
│   └── volume_calculator.dart
├── theme/                # Pastel theme
└── ui/
    ├── screens/          # Camera screen
    └── widgets/          # UI components

ios/Runner/
├── EdgeSAMBridge.swift   # CoreML model bridge
├── NativeCameraController.swift
├── StabilityMonitor.swift
└── BlurChecker.swift

android/app/src/main/
├── assets/               # ONNX models
└── kotlin/               # Android native code
```

## Credits

- [EdgeSAM](https://github.com/chongzhou96/EdgeSAM) - Prompt-In-the-Loop Distillation for On-Device SAM
- [Segment Anything Model (SAM)](https://github.com/facebookresearch/segment-anything) - Meta AI

## License

This project uses EdgeSAM which is licensed under [NTU S-Lab License 1.0](https://github.com/chongzhou96/EdgeSAM/blob/master/LICENSE).
