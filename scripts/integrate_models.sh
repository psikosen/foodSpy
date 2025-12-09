#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MODEL_DIR="${ROOT_DIR}/models"
IOS_RESOURCES="${ROOT_DIR}/ios/Runner"
ANDROID_ASSETS="${ROOT_DIR}/android/app/src/main/assets"

log() {
  printf "[integrate] %s\n" "$1"
}

print_usage() {
  cat <<EOF
Usage: $0 [PLATFORM]

Integrates downloaded EdgeSAM models into the platform-specific project.

Platforms:
  ios       Copy CoreML models to iOS Runner resources
  android   Copy ONNX models to Android assets
  all       Integrate for all platforms (default)

Prerequisites:
  Run ./scripts/download_models.sh first to download the models.

Examples:
  $0              # Integrate for all platforms
  $0 ios          # iOS only
  $0 android      # Android only

EOF
}

integrate_ios() {
  log "=== Integrating iOS (CoreML) Models ==="
  
  # Look for .mlpackage directories (encoder and decoder)
  local found=0
  for mlpackage in "${MODEL_DIR}"/*.mlpackage; do
    if [[ -d "$mlpackage" ]]; then
      local name=$(basename "$mlpackage")
      log "Copying ${name} to iOS project..."
      cp -R "$mlpackage" "${IOS_RESOURCES}/"
      found=$((found + 1))
    fi
  done
  
  # Also check for compiled .mlmodelc
  for mlmodel in "${MODEL_DIR}"/*.mlmodelc; do
    if [[ -d "$mlmodel" ]]; then
      local name=$(basename "$mlmodel")
      log "Copying ${name} to iOS project..."
      cp -R "$mlmodel" "${IOS_RESOURCES}/"
      found=$((found + 1))
    fi
  done
  
  if [[ $found -eq 0 ]]; then
    log "⚠ No CoreML models found in ${MODEL_DIR}"
    log "  Run: ./scripts/download_models.sh --coreml"
    return 1
  fi
  
  log "✓ Integrated ${found} CoreML model(s) to iOS"
  log ""
  log "Next steps for iOS:"
  log "  1. Open ios/Runner.xcworkspace in Xcode"
  log "  2. Add the .mlpackage files to the project (drag & drop)"
  log "  3. Ensure 'Copy items if needed' is checked"
  log "  4. Build and run on device"
}

integrate_android() {
  log "=== Integrating Android (ONNX) Models ==="
  
  mkdir -p "$ANDROID_ASSETS"
  
  local found=0
  for onnx_file in "${MODEL_DIR}"/*.onnx; do
    if [[ -f "$onnx_file" ]]; then
      local name=$(basename "$onnx_file")
      log "Copying ${name} to Android assets..."
      cp "$onnx_file" "${ANDROID_ASSETS}/"
      found=$((found + 1))
    fi
  done
  
  if [[ $found -eq 0 ]]; then
    log "⚠ No ONNX models found in ${MODEL_DIR}"
    log "  Run: ./scripts/download_models.sh --onnx"
    return 1
  fi
  
  log "✓ Integrated ${found} ONNX model(s) to Android"
  log ""
  log "Note: Android integration requires ONNX Runtime dependency."
  log "Add to android/app/build.gradle:"
  log '  implementation "com.microsoft.onnxruntime:onnxruntime-android:1.16.3"'
}

# Parse platform argument
PLATFORM="${1:-all}"

case "$PLATFORM" in
  ios)
    integrate_ios
    ;;
  android)
    integrate_android
    ;;
  all)
    integrate_ios || true
    echo ""
    integrate_android || true
    ;;
  -h|--help)
    print_usage
    exit 0
    ;;
  *)
    log "Unknown platform: $PLATFORM"
    print_usage
    exit 1
    ;;
esac

log ""
log "=== Integration Complete ==="

