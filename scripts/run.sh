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
  exit 1
fi

if [[ ! -f "${ROOT_DIR}/pubspec.yaml" ]]; then
  log "pubspec.yaml not found in ${ROOT_DIR}. Ensure the Flutter project exists."
  exit 1
fi

cd "${ROOT_DIR}"
log "Fetching dependencies"
flutter pub get

log "Launching ${PROJECT_NAME}"
if [[ -n "$DEVICE_ID" ]]; then
  flutter run --device-id "$DEVICE_ID"
else
  flutter run
fi
