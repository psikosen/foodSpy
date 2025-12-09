#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROJECT_NAME="PlateDepth"

log() {
  printf "[build] %s\n" "$1"
}

if ! command -v flutter >/dev/null 2>&1; then
  log "Flutter is not installed. Please install Flutter before building ${PROJECT_NAME}."
  log "  https://docs.flutter.dev/get-started/install"
  exit 1
fi

if [[ ! -f "${ROOT_DIR}/pubspec.yaml" ]]; then
  log "pubspec.yaml not found in ${ROOT_DIR}. Create the Flutter project before running builds."
  exit 1
fi

cd "${ROOT_DIR}"

log "=== ${PROJECT_NAME} Build Pipeline ==="
log ""

# Check for models
log "--- Checking Models ---"
model_count=$(find "${ROOT_DIR}/models" -type f \( -name "*.pth" -o -name "*.onnx" -o -name "*.mlpackage" -o -name "*.mlmodel" \) 2>/dev/null | wc -l || echo "0")
if [[ $model_count -eq 0 ]]; then
  log "⚠ Warning: No models found in models/"
  log "  Run: ./scripts/download_models.sh"
  log "  Continuing build anyway..."
fi
log ""

log "--- Flutter Dependencies ---"
flutter pub get

log ""
log "--- Static Analysis ---"
flutter analyze --no-fatal-infos || {
  log "⚠ Analysis found issues. Review above."
}

log ""
log "--- Running Tests ---"
flutter test || {
  log "⚠ Some tests failed. Review above."
}

log ""
log "--- Platform Builds ---"

# Detect platform and build accordingly
case "$(uname -s)" in
  Darwin)
    log "Building iOS app (macOS detected)"
    flutter build ios --no-codesign || {
      log "⚠ iOS build failed. Check Xcode setup."
    }
    ;;
  Linux)
    log "Building Android APK (Linux detected)"
    if command -v android >/dev/null 2>&1 || [[ -n "${ANDROID_HOME:-}" ]]; then
      flutter build apk --debug || {
        log "⚠ Android build failed. Check Android SDK setup."
      }
    else
      log "Android SDK not found. Skipping APK build."
      log "Set ANDROID_HOME or install Android Studio."
    fi
    
    # Also try Linux desktop if available
    if flutter config --list 2>/dev/null | grep -q "enable-linux-desktop: true"; then
      log "Building Linux desktop app"
      flutter build linux || {
        log "⚠ Linux desktop build failed."
      }
    fi
    ;;
  MINGW*|MSYS*|CYGWIN*)
    log "Building Windows app (Windows detected)"
    flutter build windows || {
      log "⚠ Windows build failed."
    }
    
    if [[ -n "${ANDROID_HOME:-}" ]]; then
      log "Building Android APK"
      flutter build apk --debug || {
        log "⚠ Android build failed."
      }
    fi
    ;;
  *)
    log "Unknown platform: $(uname -s). Skipping native builds."
    ;;
esac

log ""
log "=== Build Pipeline Finished ==="
log ""
log "Artifacts:"
[[ -d "${ROOT_DIR}/build/ios" ]] && log "  iOS: build/ios/"
[[ -d "${ROOT_DIR}/build/app/outputs/flutter-apk" ]] && log "  Android: build/app/outputs/flutter-apk/"
[[ -d "${ROOT_DIR}/build/linux" ]] && log "  Linux: build/linux/"
[[ -d "${ROOT_DIR}/build/windows" ]] && log "  Windows: build/windows/"
