#!/usr/bin/env python3
"""Download and export Salesforce/GPA-GUI-Detector to Core ML."""

from __future__ import annotations

import argparse
import shutil
from pathlib import Path

import coremltools as ct
from huggingface_hub import hf_hub_download
from ultralytics import YOLO


PROJECT_ROOT = Path(__file__).resolve().parents[3]
MODEL_REPOSITORY = "Salesforce/GPA-GUI-Detector"
MODEL_REVISION = "d04be6b715acb517068ca15d4b79159d26292713"
DEFAULT_SOURCE = PROJECT_ROOT / "Models/Source/GPA-GUI-Detector/model.pt"
DEFAULT_OUTPUT = PROJECT_ROOT / "Models/Generated/GPA_GUI_Detector.mlpackage"


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Export Salesforce/GPA-GUI-Detector as a Vision-compatible Core ML model."
    )
    parser.add_argument(
        "--source",
        type=Path,
        default=DEFAULT_SOURCE,
        help=f"PyTorch checkpoint path (default: {DEFAULT_SOURCE})",
    )
    parser.add_argument(
        "--output",
        type=Path,
        default=DEFAULT_OUTPUT,
        help=f"Destination .mlpackage path (default: {DEFAULT_OUTPUT})",
    )
    parser.add_argument(
        "--image-size",
        type=int,
        default=1280,
        help="Square Core ML input size; 640, 960, and 1280 are useful comparison points.",
    )
    parser.add_argument(
        "--confidence",
        type=float,
        default=0.05,
        help="Confidence floor embedded in exported NMS.",
    )
    parser.add_argument(
        "--iou",
        type=float,
        default=0.7,
        help="IoU threshold embedded in exported NMS.",
    )
    parser.add_argument(
        "--revision",
        default=MODEL_REVISION,
        help="Pinned Hugging Face revision used when the source checkpoint is absent.",
    )
    parser.add_argument(
        "--force",
        action="store_true",
        help="Replace an existing output package.",
    )
    return parser.parse_args()


def validate_args(args: argparse.Namespace) -> None:
    if args.image_size <= 0 or args.image_size % 32 != 0:
        raise SystemExit("--image-size must be positive and divisible by 32")
    if not 0 <= args.confidence <= 1:
        raise SystemExit("--confidence must be between 0 and 1")
    if not 0 <= args.iou <= 1:
        raise SystemExit("--iou must be between 0 and 1")
    if args.output.suffix != ".mlpackage":
        raise SystemExit("--output must end in .mlpackage")


def source_checkpoint(path: Path, revision: str) -> Path:
    if path.exists():
        return path.resolve()

    path.parent.mkdir(parents=True, exist_ok=True)
    downloaded = Path(
        hf_hub_download(
            repo_id=MODEL_REPOSITORY,
            filename="model.pt",
            revision=revision,
            local_dir=path.parent,
        )
    )
    if downloaded.resolve() != path.resolve():
        shutil.copy2(downloaded, path)
    return path.resolve()


def export_model(checkpoint: Path, args: argparse.Namespace) -> Path:
    model = YOLO(str(checkpoint))
    exported = model.export(
        format="coreml",
        imgsz=args.image_size,
        nms=True,
        quantize=16,
        conf=args.confidence,
        iou=args.iou,
        batch=1,
        device="cpu",
    )
    exported_path = Path(exported).resolve()
    if exported_path.suffix != ".mlpackage" or not exported_path.is_dir():
        raise RuntimeError(f"Ultralytics returned an unexpected export path: {exported_path}")
    return exported_path


def install_export(exported: Path, output: Path, force: bool) -> None:
    output = output.resolve()
    if output.exists():
        if not force:
            raise SystemExit(f"output already exists: {output}; pass --force to replace it")
        if output.is_dir():
            shutil.rmtree(output)
        else:
            output.unlink()

    output.parent.mkdir(parents=True, exist_ok=True)
    shutil.copytree(exported, output)


def validate_export(output: Path) -> None:
    model = ct.models.MLModel(str(output.resolve()), compute_units=ct.ComputeUnit.CPU_ONLY)
    spec = model.get_spec()
    input_names = {feature.name for feature in spec.description.input}
    output_names = {feature.name for feature in spec.description.output}
    if spec.WhichOneof("Type") != "pipeline":
        raise RuntimeError("Core ML export does not contain the expected NMS pipeline")
    if "image" not in input_names:
        raise RuntimeError(f"Core ML export has no image input: {sorted(input_names)}")
    if not {"confidence", "coordinates"}.issubset(output_names):
        raise RuntimeError(f"Core ML export has unexpected outputs: {sorted(output_names)}")


def main() -> None:
    args = parse_args()
    validate_args(args)
    checkpoint = source_checkpoint(args.source, args.revision)
    print(f"Using checkpoint: {checkpoint}")
    exported = export_model(checkpoint, args)
    install_export(exported, args.output, args.force)
    validate_export(args.output)
    print(f"Core ML model written to: {args.output.resolve()}")


if __name__ == "__main__":
    main()
