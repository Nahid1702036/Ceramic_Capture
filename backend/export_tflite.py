#!/usr/bin/env python3
# backend/export_tflite.py
#
# Exports yolo26m.pt → yolov8_ceramic.tflite
# Place the output in: flutter_app/assets/models/yolov8_ceramic.tflite
#
# Usage:
#   python backend/export_tflite.py --model yolo26m.pt --imgsz 640
#
# Requirements:
#   pip install ultralytics tensorflow

import argparse
import shutil
from pathlib import Path


def export(model_path: str, imgsz: int, output_dir: str) -> None:
    from ultralytics import YOLO

    print(f"[1/3] Loading {model_path}…")
    model = YOLO(model_path)

    print(f"[2/3] Exporting to TFLite (imgsz={imgsz})…")
    # Export returns path to the TFLite file
    export_path = model.export(
        format="tflite",
        imgsz=imgsz,
        int8=False,       # Set True for faster inference at slight accuracy cost
        data=None,        # No calibration dataset needed for fp16/fp32
        nms=False,        # Handle NMS in Dart for flexibility
    )

    src = Path(export_path)
    dst = Path(output_dir) / "yolov8_ceramic.tflite"
    dst.parent.mkdir(parents=True, exist_ok=True)
    shutil.copy(src, dst)

    print(f"[3/3] Done → {dst}")
    print()
    print("Next steps:")
    print(f"  1. Copy {dst} into your Flutter project:")
    print(f"     cp {dst} ../lib/  # or assets/models/")
    print("  2. Update pubspec.yaml assets section if needed")
    print("  3. In Flutter, set InferenceMode.tflite in YoloService")
    print()
    size_mb = dst.stat().st_size / 1024 / 1024
    print(f"  Model size: {size_mb:.1f} MB")
    if size_mb > 30:
        print("  ⚠ Large model — consider int8 quantisation:")
        print("    model.export(format='tflite', int8=True, data='path/to/calib.yaml')")


def verify(tflite_path: str, imgsz: int) -> None:
    """Quick sanity check — run inference on a blank image."""
    import numpy as np

    try:
        import tensorflow as tf
        interpreter = tf.lite.Interpreter(model_path=tflite_path)
        interpreter.allocate_tensors()

        input_details = interpreter.get_input_details()
        output_details = interpreter.get_output_details()

        # Blank image
        dummy = np.zeros((1, imgsz, imgsz, 3), dtype=np.float32)
        interpreter.set_tensor(input_details[0]["index"], dummy)
        interpreter.invoke()

        output = interpreter.get_tensor(output_details[0]["index"])
        print(f"  ✓ TFLite sanity check passed — output shape: {output.shape}")
    except ImportError:
        print("  (tensorflow not installed — skipping verification)")
    except Exception as e:
        print(f"  ✗ Verification failed: {e}")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="Export YOLO → TFLite")
    parser.add_argument("--model", default="yolo26m.pt")
    parser.add_argument("--imgsz", type=int, default=640)
    parser.add_argument("--output", default="assets/models",
                        help="Output directory (relative to project root)")
    args = parser.parse_args()

    export(args.model, args.imgsz, args.output)
    print("Verifying exported model…")
    verify(str(Path(args.output) / "yolov8_ceramic.tflite"), args.imgsz)
