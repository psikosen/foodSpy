#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

log() {
  printf "[setup] %s\n" "$1"
}

check_command() {
  local cmd="$1"
  local install_hint="$2"
  if ! command -v "$cmd" >/dev/null 2>&1; then
    log "Missing dependency: $cmd. ${install_hint}"
    return 1
  fi
  log "✓ Found: $cmd"
  return 0
}

missing=0
log "=== PlateDepth Setup ==="
log "Preparing workspace at ${ROOT_DIR}"
log ""

log "--- Checking Required Tools ---"
check_command git "Install Git from https://git-scm.com/downloads." || missing=1
check_command unzip "Install unzip via your package manager." || missing=1

# Check for at least one downloader
if command -v curl >/dev/null 2>&1; then
  log "✓ Found: curl"
elif command -v wget >/dev/null 2>&1; then
  log "✓ Found: wget"
else
  log "Missing: curl or wget. Install one via your package manager."
  missing=1
fi

log ""
log "--- Checking Optional Tools ---"

if check_command git-lfs "Install Git LFS from https://git-lfs.com (optional for large files)."; then
  log "  Configuring Git LFS"
  git lfs install --force 2>/dev/null || true
fi

log ""
log "--- Checking Flutter SDK ---"

if check_command flutter "Install Flutter from https://docs.flutter.dev/get-started/install."; then
  flutter_version=$(flutter --version 2>/dev/null | head -n 1)
  log "  Version: ${flutter_version}"
  
  # Check Flutter doctor briefly
  log "  Running flutter doctor (quick check)..."
  flutter doctor --android-licenses 2>/dev/null || true
else
  log "Flutter is not installed. Install Flutter before running builds."
  missing=1
fi

log ""
log "--- Setting Up Directories ---"
mkdir -p "${ROOT_DIR}/models" "${ROOT_DIR}/downloads" "${ROOT_DIR}/assets"
log "✓ Created: models/"
log "✓ Created: downloads/"
log "✓ Created: assets/"

log ""
log "--- Checking for Models ---"
model_count=0
if [[ -d "${ROOT_DIR}/models" ]]; then
  model_count=$(find "${ROOT_DIR}/models" -type f \( -name "*.pth" -o -name "*.onnx" -o -name "*.mlpackage" -o -name "*.mlmodel" \) 2>/dev/null | wc -l)
fi

if [[ $model_count -gt 0 ]]; then
  log "✓ Found ${model_count} model file(s) in models/"
else
  log "⚠ No models found. Run: ./scripts/download_models.sh"
fi

log ""
if (( missing > 0 )); then
  log "=== Setup finished with WARNINGS ==="
  log "Some dependencies are missing. Install the items above and re-run."
  exit 1
fi

log "=== Setup Completed Successfully ==="
log ""
log "Next steps:"
log "  1. Download models:  ./scripts/download_models.sh --coreml  (for iOS)"
log "                       ./scripts/download_models.sh --onnx    (for Android)"
log "  2. Run the app:      ./scripts/run.sh"
log "  3. Build release:    ./scripts/build.sh"
