#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROJECT_NAME="PlateDepth"
DEVICE_ID="${PLATEDEPTH_DEVICE:-}"

log() {
  printf "[run] %s\n" "$1"
}

if ! command -v flutter >/dev/null 2>&1; then
  log "Flutter is not installed. Install Flutter before running ${PROJECT_NAME}."
  log "  https://docs.flutter.dev/get-started/install"
  exit 1
fi

if [[ ! -f "${ROOT_DIR}/pubspec.yaml" ]]; then
  log "pubspec.yaml not found in ${ROOT_DIR}. Ensure the Flutter project exists."
  exit 1
fi

cd "${ROOT_DIR}"

log "=== ${PROJECT_NAME} Runner ==="
log ""

# Check for models
model_count=$(find "${ROOT_DIR}/models" -type f \( -name "*.pth" -o -name "*.onnx" -o -name "*.mlpackage" -o -name "*.mlmodel" \) 2>/dev/null | wc -l || echo "0")
if [[ $model_count -eq 0 ]]; then
  log "⚠ Warning: No models found in models/"
  log "  The app requires EdgeSAM models for segmentation."
  log "  Run: ./scripts/download_models.sh"
  log ""
fi

log "Fetching dependencies..."
flutter pub get

log ""
log "Available devices:"
flutter devices 2>/dev/null || true

log ""
log "Launching ${PROJECT_NAME}..."
if [[ -n "$DEVICE_ID" ]]; then
  log "Using device: $DEVICE_ID"
  flutter run --device-id "$DEVICE_ID"
else
  flutter run
fi
