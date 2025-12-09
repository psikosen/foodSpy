#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MODEL_DIR="${ROOT_DIR}/models"
DOWNLOADS_DIR="${ROOT_DIR}/downloads"
IOS_RUNNER_DIR="${ROOT_DIR}/ios/Runner"

# SAM 2 CoreML models from Apple on HuggingFace
# Source: https://huggingface.co/collections/apple/core-ml-segment-anything-2-66e4571a7234dc2560c3db26
# These models provide MUCH higher quality segmentation than EdgeSAM

SAM2_VARIANTS=(
  "sam2.1-tiny"    # ~78MB, faster, good quality
  "sam2.1-small"   # ~100MB, best balance of quality/speed (RECOMMENDED)
)

# Default to sam2.1-small for best quality
SAM2_VARIANT="${SAM2_VARIANT:-sam2.1-small}"

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

check_git_lfs() {
  if command -v git-lfs >/dev/null 2>&1 || git lfs version >/dev/null 2>&1; then
    return 0
  else
    return 1
  fi
}

download_sam2_coreml() {
  local variant="$1"
  local repo="apple/coreml-${variant}"
  
  log "=== Downloading SAM 2 CoreML Models (${variant}) ==="
  log "Source: https://huggingface.co/${repo}"
  log ""
  
  # SAM 2.1 has 3 separate models: image encoder, prompt encoder, mask decoder
  # Naming: SAM2_1{Size}{ModelType}FLOAT16.mlpackage
  local image_encoder_name
  local prompt_encoder_name
  local mask_decoder_name
  
  case "$variant" in
    "sam2.1-tiny")
      image_encoder_name="SAM2_1TinyImageEncoderFLOAT16"
      prompt_encoder_name="SAM2_1TinyPromptEncoderFLOAT16"
      mask_decoder_name="SAM2_1TinyMaskDecoderFLOAT16"
      ;;
    "sam2.1-small")
      image_encoder_name="SAM2_1SmallImageEncoderFLOAT16"
      prompt_encoder_name="SAM2_1SmallPromptEncoderFLOAT16"
      mask_decoder_name="SAM2_1SmallMaskDecoderFLOAT16"
      ;;
    *)
      log "Unknown variant: $variant"
      exit 1
      ;;
  esac
  
  local target_dir="${MODEL_DIR}/sam2"
  mkdir -p "$target_dir"
  
  local clone_dir="${DOWNLOADS_DIR}/hf-${variant}"
  local hf_base="https://huggingface.co/${repo}/resolve/main"
  
  # Method 1: Git clone (gets structure, but needs LFS for weights)
  if [[ ! -d "${clone_dir}/.git" ]]; then
    log "Cloning repository structure..."
    git clone --depth 1 "https://huggingface.co/${repo}" "$clone_dir" 2>/dev/null || {
      log "Git clone failed, will download files directly"
    }
  fi
  
  # Method 2: Download weights directly via curl (git-lfs alternative)
  download_model_weights() {
    local model_name="$1"
    local model_dir="${clone_dir}/${model_name}.mlpackage"
    local weights_file="${model_dir}/Data/com.apple.CoreML/weights/weight.bin"
    
    if [[ ! -d "$model_dir" ]]; then
      log "Creating directory structure for ${model_name}..."
      mkdir -p "${model_dir}/Data/com.apple.CoreML/weights"
      
      # Download manifest
      curl -L --fail --silent \
        -o "${model_dir}/Manifest.json" \
        "${hf_base}/${model_name}.mlpackage/Manifest.json" || true
      
      # Download model spec
      curl -L --fail --silent \
        -o "${model_dir}/Data/com.apple.CoreML/model.mlmodel" \
        "${hf_base}/${model_name}.mlpackage/Data/com.apple.CoreML/model.mlmodel" || true
    fi
    
    # Check if weights need downloading (LFS pointer is ~133 bytes)
    local weights_size=0
    if [[ -f "$weights_file" ]]; then
      weights_size=$(stat -c%s "$weights_file" 2>/dev/null || stat -f%z "$weights_file" 2>/dev/null || echo "0")
    fi
    
    if [[ ! -f "$weights_file" || "$weights_size" -lt 1000 ]]; then
      log "Downloading weights for ${model_name}..."
      curl -L --fail --progress-bar \
        -o "$weights_file" \
        "${hf_base}/${model_name}.mlpackage/Data/com.apple.CoreML/weights/weight.bin" || {
          log "Failed to download weights for ${model_name}"
          return 1
        }
    else
      log "Weights already downloaded: ${model_name}"
    fi
  }
  
  # Download all three models
  download_model_weights "$image_encoder_name"
  download_model_weights "$prompt_encoder_name"
  download_model_weights "$mask_decoder_name"
  
  # Copy to target directory
  for model in "$image_encoder_name" "$prompt_encoder_name" "$mask_decoder_name"; do
    if [[ -d "${clone_dir}/${model}.mlpackage" ]]; then
      log "Copying ${model}.mlpackage to target..."
      cp -R "${clone_dir}/${model}.mlpackage" "${target_dir}/"
    fi
  done
  
  # Verify all models are present
  local all_present=true
  for model in "$image_encoder_name" "$prompt_encoder_name" "$mask_decoder_name"; do
    if [[ ! -d "${target_dir}/${model}.mlpackage" ]]; then
      log "Missing: ${model}.mlpackage"
      all_present=false
    fi
  done
  
  if [[ "$all_present" == true ]]; then
    log ""
    log "SAM 2.1 CoreML models downloaded successfully!"
    log "  - Image Encoder: ${image_encoder_name}"
    log "  - Prompt Encoder: ${prompt_encoder_name}"
    log "  - Mask Decoder: ${mask_decoder_name}"
  else
    log "ERROR: Some models failed to download"
    exit 1
  fi
  
  log ""
  log "Models in: ${target_dir}"
  ls -lh "${target_dir}" 2>/dev/null || true
}

copy_to_ios() {
  local variant="$1"
  local source_dir="${MODEL_DIR}/sam2"
  
  log "=== Copying SAM 2.1 models to iOS project ==="
  
  local image_encoder_name
  local prompt_encoder_name
  local mask_decoder_name
  
  case "$variant" in
    "sam2.1-tiny")
      image_encoder_name="SAM2_1TinyImageEncoderFLOAT16"
      prompt_encoder_name="SAM2_1TinyPromptEncoderFLOAT16"
      mask_decoder_name="SAM2_1TinyMaskDecoderFLOAT16"
      ;;
    "sam2.1-small")
      image_encoder_name="SAM2_1SmallImageEncoderFLOAT16"
      prompt_encoder_name="SAM2_1SmallPromptEncoderFLOAT16"
      mask_decoder_name="SAM2_1SmallMaskDecoderFLOAT16"
      ;;
    *)
      log "Unknown variant for iOS copy: $variant"
      return 1
      ;;
  esac
  
  # Copy all three models to iOS Runner directory
  for model in "$image_encoder_name" "$prompt_encoder_name" "$mask_decoder_name"; do
    if [[ -d "${source_dir}/${model}.mlpackage" ]]; then
      log "Copying ${model}.mlpackage to iOS..."
      cp -R "${source_dir}/${model}.mlpackage" "${IOS_RUNNER_DIR}/"
    else
      log "WARNING: ${model}.mlpackage not found in ${source_dir}"
    fi
  done
  
  log ""
  log "Models copied to: ${IOS_RUNNER_DIR}"
  ls -lh "${IOS_RUNNER_DIR}"/*.mlpackage 2>/dev/null || true
  log ""
  log "IMPORTANT: After copying, you must:"
  log "  1. Open Xcode project: ios/Runner.xcworkspace"
  log "  2. Drag ALL THREE .mlpackage folders into the Runner target"
  log "  3. Ensure 'Copy Bundle Resources' includes all models"
  log "  4. Build the project"
}

# Legacy EdgeSAM download (kept for reference/fallback)
download_edgesam_legacy() {
  log "=== Downloading Legacy EdgeSAM Models ==="
  log "Note: EdgeSAM has lower quality. Use SAM 2 for better results."
  
  local EDGESAM_BASE_URL="https://huggingface.co/spaces/chongzhou/EdgeSAM/resolve/main/weights"
  
  for model in "edge_sam_3x_encoder.mlpackage.zip" "edge_sam_3x_decoder.mlpackage.zip"; do
    if [[ ! -f "${DOWNLOADS_DIR}/${model}" ]]; then
      log "Downloading: $model"
      curl -L --fail --progress-bar -o "${DOWNLOADS_DIR}/${model}" "${EDGESAM_BASE_URL}/${model}"
    fi
    if [[ "$model" == *.zip ]]; then
      unzip -o -q "${DOWNLOADS_DIR}/${model}" -d "${MODEL_DIR}"
    fi
  done
}

print_usage() {
  cat <<EOF
Usage: $0 [OPTIONS]

Downloads SAM 2 CoreML models for FoodSpy app (high-quality segmentation).

Options:
  --sam2-tiny     Download SAM 2.1 Tiny (~78MB, faster)
  --sam2-small    Download SAM 2.1 Small (~100MB, best quality) [DEFAULT]
  --edgesam       Download legacy EdgeSAM (lower quality, faster)
  --copy-ios      Copy downloaded models to iOS project
  --all           Download SAM 2 Small and copy to iOS
  --help          Show this help message

Examples:
  $0                    # Download SAM 2.1 Small (recommended)
  $0 --sam2-tiny        # Download smaller/faster variant
  $0 --copy-ios         # Copy models to iOS after download
  
Model Quality Comparison:
  - SAM 2.1 Small: ⭐⭐⭐⭐⭐ Best quality, 1024x1024 masks
  - SAM 2.1 Tiny:  ⭐⭐⭐⭐  Good quality, faster inference
  - EdgeSAM:       ⭐⭐     Lower quality, 256x256 masks (legacy)

Source: https://huggingface.co/collections/apple/core-ml-segment-anything-2-66e4571a7234dc2560c3db26

EOF
}

# Parse arguments
ACTION="download_sam2"
COPY_IOS=false

while [[ $# -gt 0 ]]; do
  case $1 in
    --sam2-tiny)
      SAM2_VARIANT="sam2.1-tiny"
      shift
      ;;
    --sam2-small)
      SAM2_VARIANT="sam2.1-small"
      shift
      ;;
    --edgesam|--legacy)
      ACTION="download_edgesam"
      shift
      ;;
    --copy-ios)
      COPY_IOS=true
      shift
      ;;
    --all)
      ACTION="download_sam2"
      COPY_IOS=true
      shift
      ;;
    --help|-h)
      print_usage
      exit 0
      ;;
    *)
      log "Unknown option: $1"
      print_usage
      exit 1
      ;;
  esac
done

# Create directories
mkdir -p "$MODEL_DIR" "$DOWNLOADS_DIR"

# Detect downloader
DOWNLOADER="$(require_downloader)"
log "Using ${DOWNLOADER} for downloads"
log "Models directory: ${MODEL_DIR}"
log ""

# Execute action
case "$ACTION" in
  download_sam2)
    download_sam2_coreml "$SAM2_VARIANT"
    ;;
  download_edgesam)
    download_edgesam_legacy
    ;;
esac

# Copy to iOS if requested
if [[ "$COPY_IOS" == true ]]; then
  copy_to_ios "$SAM2_VARIANT"
fi

log ""
log "=== Download Summary ==="
log "SAM 2 Variant: ${SAM2_VARIANT}"
log "Models saved to: ${MODEL_DIR}/sam2"
ls -la "${MODEL_DIR}/sam2" 2>/dev/null || true
log ""
log "Download completed successfully!"
log ""
log "Next steps:"
log "  1. Run: $0 --copy-ios"
log "  2. Open Xcode and add .mlpackage files to Runner target"
log "  3. Build and run the app"
