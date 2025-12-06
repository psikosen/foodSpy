#!/usr/bin/env python3
"""Convert and quantize EdgeSAM PyTorch weights to CoreML.

Requirements:
  pip install coremltools torch
"""

import argparse
import coremltools as ct
import torch


def load_torch_model(weights_path: str):
    model = torch.jit.load(weights_path)
    model.eval()
    return model


def convert(weights_path: str, output_path: str):
    model = load_torch_model(weights_path)
    sample = torch.rand(1, 3, 1024, 1024)
    traced = torch.jit.trace(model, sample)
    mlmodel = ct.convert(
        traced,
        inputs=[ct.ImageType(name="image", shape=sample.shape, scale=1 / 255.0, bias=[0, 0, 0])],
        compute_units=ct.ComputeUnit.CPU_AND_NE,
    )
    compressed = ct.models.neural_network.quantization_utils.quantize_weights(mlmodel, nbits=16)
    compressed.save(output_path)
    print(f"Saved quantized model to {output_path}")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="Convert EdgeSAM Torch weights to CoreML")
    parser.add_argument("weights", help="Path to traced EdgeSAM torchscript file")
    parser.add_argument("--out", default="models/EdgeSAM.mlmodel", help="Destination mlmodel path")
    args = parser.parse_args()
    convert(args.weights, args.out)
