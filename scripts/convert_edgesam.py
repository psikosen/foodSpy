#!/usr/bin/env python3
"""Convert EdgeSAM PyTorch weights to CoreML or ONNX formats.

This script provides utilities for converting EdgeSAM models for deployment
on iOS (CoreML) or cross-platform (ONNX).

Requirements:
  pip install torch coremltools onnx

Usage:
  # Convert to CoreML (iOS/macOS)
  python convert_edgesam.py edge_sam_3x.pth --format coreml --out models/

  # Convert to ONNX (cross-platform)
  python convert_edgesam.py edge_sam_3x.pth --format onnx --out models/

Note: For most use cases, pre-converted models from HuggingFace are recommended:
  ./scripts/download_models.sh --coreml   # For iOS
  ./scripts/download_models.sh --onnx     # For Android/cross-platform

Source: https://github.com/chongzhou96/EdgeSAM
"""

import argparse
import os
import sys
from pathlib import Path


def check_dependencies(format_type: str) -> bool:
    """Check if required dependencies are installed."""
    missing = []
    
    try:
        import torch
    except ImportError:
        missing.append("torch")
    
    if format_type == "coreml":
        try:
            import coremltools
        except ImportError:
            missing.append("coremltools")
    elif format_type == "onnx":
        try:
            import onnx
        except ImportError:
            missing.append("onnx")
    
    if missing:
        print(f"Missing dependencies: {', '.join(missing)}")
        print(f"Install with: pip install {' '.join(missing)}")
        return False
    return True


def load_torch_model(weights_path: str):
    """Load EdgeSAM PyTorch model."""
    import torch
    
    if not os.path.exists(weights_path):
        raise FileNotFoundError(f"Model weights not found: {weights_path}")
    
    # Try loading as TorchScript first
    try:
        model = torch.jit.load(weights_path)
        model.eval()
        print(f"Loaded TorchScript model from {weights_path}")
        return model, "torchscript"
    except Exception:
        pass
    
    # Try loading as state dict (requires EdgeSAM library)
    try:
        from edge_sam import sam_model_registry
        model = sam_model_registry["edge_sam"](checkpoint=weights_path)
        model.eval()
        print(f"Loaded EdgeSAM model from {weights_path}")
        return model, "edgesam"
    except ImportError:
        print("EdgeSAM library not found. Install with:")
        print("  git clone https://github.com/chongzhou96/EdgeSAM.git")
        print("  cd EdgeSAM && pip install -e .")
        raise


def convert_to_coreml(model, model_type: str, output_dir: str, use_fp16: bool = True):
    """Convert model to CoreML format."""
    import torch
    import coremltools as ct
    
    output_path = Path(output_dir)
    output_path.mkdir(parents=True, exist_ok=True)
    
    # Trace the encoder
    print("Converting encoder to CoreML...")
    sample_input = torch.rand(1, 3, 1024, 1024)
    
    if model_type == "edgesam":
        encoder = model.image_encoder
        traced_encoder = torch.jit.trace(encoder, sample_input)
    else:
        traced_encoder = model
    
    mlmodel_encoder = ct.convert(
        traced_encoder,
        inputs=[ct.ImageType(name="image", shape=sample_input.shape, scale=1/255.0, bias=[0, 0, 0])],
        compute_units=ct.ComputeUnit.CPU_AND_NE,
    )
    
    if use_fp16:
        print("Quantizing encoder to FP16...")
        mlmodel_encoder = ct.models.neural_network.quantization_utils.quantize_weights(mlmodel_encoder, nbits=16)
    
    encoder_path = output_path / "EdgeSAM_encoder.mlpackage"
    mlmodel_encoder.save(str(encoder_path))
    print(f"Saved encoder to {encoder_path}")
    
    return encoder_path


def convert_to_onnx(model, model_type: str, output_dir: str):
    """Convert model to ONNX format."""
    import torch
    
    output_path = Path(output_dir)
    output_path.mkdir(parents=True, exist_ok=True)
    
    print("Converting encoder to ONNX...")
    sample_input = torch.rand(1, 3, 1024, 1024)
    
    if model_type == "edgesam":
        encoder = model.image_encoder
    else:
        encoder = model
    
    encoder_path = output_path / "EdgeSAM_encoder.onnx"
    torch.onnx.export(
        encoder,
        sample_input,
        str(encoder_path),
        input_names=["image"],
        output_names=["embedding"],
        dynamic_axes={"image": {0: "batch"}, "embedding": {0: "batch"}},
        opset_version=13,
    )
    print(f"Saved encoder to {encoder_path}")
    
    return encoder_path


def main():
    parser = argparse.ArgumentParser(
        description="Convert EdgeSAM PyTorch weights to CoreML or ONNX",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
Examples:
  %(prog)s edge_sam_3x.pth --format coreml --out models/
  %(prog)s edge_sam_3x.pth --format onnx --out models/

For pre-converted models, use download_models.sh instead:
  ./scripts/download_models.sh --coreml   # iOS
  ./scripts/download_models.sh --onnx     # Android
        """
    )
    parser.add_argument("weights", help="Path to EdgeSAM PyTorch weights (.pth)")
    parser.add_argument("--format", choices=["coreml", "onnx"], default="coreml",
                        help="Output format (default: coreml)")
    parser.add_argument("--out", default="models/", help="Output directory (default: models/)")
    parser.add_argument("--fp32", action="store_true", help="Keep FP32 precision (CoreML only)")
    
    args = parser.parse_args()
    
    if not check_dependencies(args.format):
        sys.exit(1)
    
    try:
        model, model_type = load_torch_model(args.weights)
        
        if args.format == "coreml":
            output = convert_to_coreml(model, model_type, args.out, use_fp16=not args.fp32)
        else:
            output = convert_to_onnx(model, model_type, args.out)
        
        print(f"\nConversion complete! Output: {output}")
        print("\nNote: For the decoder, use the official EdgeSAM export scripts:")
        print("  https://github.com/chongzhou96/EdgeSAM#coreml--onnx-export")
        
    except Exception as e:
        print(f"Error: {e}")
        sys.exit(1)


if __name__ == "__main__":
    main()
