"""Train the PPE detector that replaces the colour baseline.

1. Download a construction PPE dataset in YOLO format (for example
   Roboflow Universe "Construction Site Safety" or SHWD) and point data.yaml at it.
   Class names may be e.g. Hardhat, NO-Hardhat, Safety Vest, NO-Safety Vest,
   harness, machinery - detector.py maps them automatically.
2. python training/train_ppe.py --data training/data.yaml --epochs 80
3. The best weights are copied to weights/ppe.pt; restart the API and
   /health reports mode "ppe-model".

A GPU (or Google Colab) is strongly recommended for training.
"""
import argparse
import shutil
from pathlib import Path

from ultralytics import YOLO

ROOT = Path(__file__).resolve().parent.parent


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--data", default=str(ROOT / "training" / "data.yaml"))
    ap.add_argument("--model", default="yolo11s.pt", help="pretrained start point (n/s/m)")
    ap.add_argument("--epochs", type=int, default=80)
    ap.add_argument("--imgsz", type=int, default=640)
    ap.add_argument("--batch", type=int, default=16)
    ap.add_argument("--device", default=None, help="0 for first GPU, cpu for CPU")
    a = ap.parse_args()

    model = YOLO(a.model)
    model.train(data=a.data, epochs=a.epochs, imgsz=a.imgsz, batch=a.batch, device=a.device,
                project=str(ROOT / "runs"), name="ppe", exist_ok=True,
                hsv_v=0.5, degrees=5, mosaic=1.0, mixup=0.1)  # light/blur robustness for site cameras
    metrics = model.val()
    print(f"mAP50: {metrics.box.map50:.3f}  mAP50-95: {metrics.box.map:.3f}  (target mAP50 >= 0.85)")
    best = ROOT / "runs" / "ppe" / "weights" / "best.pt"
    (ROOT / "weights").mkdir(exist_ok=True)
    shutil.copy(best, ROOT / "weights" / "ppe.pt")
    print("Saved weights/ppe.pt")

    # Optional: export for faster CPU / Jetson inference
    # YOLO(ROOT / "weights" / "ppe.pt").export(format="onnx")


if __name__ == "__main__":
    main()
