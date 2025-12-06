#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MODEL_URL="${EDGE_SAM_URL:-}"  # Export EDGE_SAM_URL to point at the EdgeSAM .mlmodel file.
TARGET_PATH="${1:-${ROOT_DIR}/models/EdgeSAM.mlmodel}"
CHECKSUM="${EDGE_SAM_SHA256:-}"

log() {
  printf "[download] %s\n" "$1"
}

require_downloader() {
  if command -v curl >/dev/null 2>&1; then
    echo "curl"
  elif command -v wget >/dev/null 2>&1; then
    echo "wget"
  else
    log "Neither curl nor wget is installed. Install one to proceed."
    exit 1
  fi
}

download_with() {
  local downloader="$1"
  local url="$2"
  local output="$3"

  if [[ "$downloader" == "curl" ]]; then
    curl -L --fail --continue-at - --output "$output" "$url"
  else
    wget -c -O "$output" "$url"
  fi
}

verify_checksum() {
  local file_path="$1"
  local expected="$2"
  if [[ -z "$expected" ]]; then
    return 0
  fi
  local actual
  actual="$(shasum -a 256 "$file_path" | awk '{print $1}')"
  if [[ "$actual" != "$expected" ]]; then
    log "Checksum mismatch for $file_path. Expected $expected but found $actual."
    exit 1
  fi
  log "Checksum verified for $file_path."
}

if [[ -z "$MODEL_URL" ]]; then
  log "EDGE_SAM_URL is not set. Export the download URL for EdgeSAM.mlmodel and re-run."
  exit 1
fi

mkdir -p "$(dirname "$TARGET_PATH")"

downloader="$(require_downloader)"
log "Using ${downloader} to download model from ${MODEL_URL}"

download_with "$downloader" "$MODEL_URL" "$TARGET_PATH"
log "Model saved to $TARGET_PATH"

verify_checksum "$TARGET_PATH" "$CHECKSUM"
log "Download process completed."
