#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROJECT_NAME="PlateDepth"

log() {
  printf "[build] %s\n" "$1"
}

if ! command -v flutter >/dev/null 2>&1; then
  log "Flutter is not installed. Please install Flutter before building ${PROJECT_NAME}."
  exit 1
fi

if [[ ! -f "${ROOT_DIR}/pubspec.yaml" ]]; then
  log "pubspec.yaml not found in ${ROOT_DIR}. Create the Flutter project before running builds."
  exit 1
fi

cd "${ROOT_DIR}"
log "Running flutter pub get"
flutter pub get

log "Running flutter analyze"
flutter analyze

log "Running flutter test"
flutter test

if [[ "$(uname -s)" == "Darwin" ]]; then
  log "Building iOS app without codesign"
  flutter build ios --no-codesign
else
  log "Skipping iOS build because host platform is not macOS."
fi

log "Build pipeline finished."
