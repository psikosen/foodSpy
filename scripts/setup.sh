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
  return 0
}

missing=0
log "Preparing workspace at ${ROOT_DIR}"

check_command git "Install Git from https://git-scm.com/downloads." || missing=1
check_command curl "Install curl via your package manager." || missing=1
check_command unzip "Install unzip via your package manager." || missing=1

if check_command git-lfs "Install Git LFS from https://git-lfs.com."; then
  log "Configuring Git LFS"
  git lfs install --force
else
  missing=1
fi

if check_command flutter "Install Flutter from https://docs.flutter.dev/get-started/install."; then
  log "Flutter detected: $(flutter --version | head -n 1)"
else
  log "Flutter is not installed. Install Flutter before running builds."
  missing=1
fi

mkdir -p "${ROOT_DIR}/models" "${ROOT_DIR}/downloads"
log "Ensured model and download directories exist."

if (( missing > 0 )); then
  log "Setup finished with missing dependencies. Install the items above and re-run."
  exit 1
fi

log "Setup completed successfully."
