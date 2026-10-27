"""Frame-level safety analysis.

Pipeline for one frame:
  1. YOLO pose model  -> people + 17 body keypoints (optionally tracked)
  2. PPE check        -> trained PPE model if present, otherwise a colour baseline
  3. COCO model       -> vehicles / machinery for proximity checks
  4. Rules            -> zone breach, harness at height, fall, machinery proximity
  5. KVKK             -> faces blurred before any image is stored or returned
"""
from __future__ import annotations

import math
import time
from dataclasses import dataclass, field
from pathlib import Path

import cv2
import numpy as np
from ultralytics import YOLO

# COCO keypoint indices
NOSE, L_EYE, R_EYE, L_EAR, R_EAR = 0, 1, 2, 3, 4
L_SHO, R_SHO, L_HIP, R_HIP, L_ANK, R_ANK = 5, 6, 11, 12, 15, 16
SKELETON = [(5, 6), (5, 7), (7, 9), (6, 8), (8, 10), (5, 11), (6, 12), (11, 12),
            (11, 13), (13, 15), (12, 14), (14, 16), (0, 5), (0, 6)]
KP_CONF = 0.35
VEHICLE_COCO = {2: "car", 5: "bus", 7: "truck"}
MIN_PERSON_PX = 60  # people smaller than this are counted but PPE is not judged

GREEN, RED, ORANGE, YELLOW, WHITE = (94, 197, 34), (68, 68, 239), (22, 115, 249), (8, 179, 234), (240, 240, 240)


@dataclass
class Person:
    idx: int
    box: tuple  # x1, y1, x2, y2 in pixels
    conf: float
    kps: np.ndarray | None
    track_id: int | None = None
    ppe: dict = field(default_factory=dict)  # item -> {"state": True/False/None, "conf": float}
    zones: list = field(default_factory=list)
    violations: list = field(default_factory=list)

    @property
    def height(self):
        return self.box[3] - self.box[1]

    @property
    def label_id(self):
        return self.track_id if self.track_id is not None else self.idx + 1


@dataclass
class FrameResult:
    persons: list
    vehicles: list
    width: int
    height: int
    latency_ms: float
    mode: str

    def violation_counts(self):
        out = {}
        for p in self.persons:
            for v in p.violations:
                out[v] = out.get(v, 0) + 1
        return out


def _kp(kps, i):
    if kps is None or kps[i][2] < KP_CONF:
        return None
    return float(kps[i][0]), float(kps[i][1])


def _mid(a, b):
    if a and b:
        return (a[0] + b[0]) / 2, (a[1] + b[1]) / 2
    return a or b


def _clip_box(x1, y1, x2, y2, w, h):
    x1, y1 = max(0, int(x1)), max(0, int(y1))
    x2, y2 = min(w, int(x2)), min(h, int(y2))
    if x2 - x1 < 2 or y2 - y1 < 2:
        return None
    return x1, y1, x2, y2


class Detector:
    def __init__(self, cfg: dict, base_dir: Path):
        self.cfg = cfg
        self.base = base_dir
        self.pose_path = str(base_dir / cfg["pose_model"])
        self.pose = YOLO(self.pose_path)
        obj = base_dir / cfg.get("object_model", "")
        self.objects = YOLO(str(obj)) if obj.is_file() else None
        ppe = base_dir / cfg.get("ppe_model", "")
        self.ppe = YOLO(str(ppe)) if ppe.is_file() else None
        self.mode = "ppe-model" if self.ppe else "baseline"
        self.ppe_classes = self._map_ppe_classes() if self.ppe else {}
        self.last_latency_ms = 0.0

    # ------------------------------------------------------------------ models
    def new_tracking_model(self):
        """A fresh pose model so every video / stream gets its own tracker state."""
        return YOLO(self.pose_path)

    def _map_ppe_classes(self):
        """Map whatever class names the trained PPE model uses onto our items."""
        mapping = {}
        for cid, name in self.ppe.names.items():
            n = name.lower().replace("_", "-").replace(" ", "-")
            neg = n.startswith("no-") or n.startswith("without") or n == "head"
            if any(k in n for k in ("hardhat", "helmet", "hard-hat")) or n == "head":
                mapping[cid] = ("hardhat", not neg)
            elif "vest" in n:
                mapping[cid] = ("vest", not neg)
            elif "harness" in n:
                mapping[cid] = ("harness", not neg)
            elif n in ("machinery", "vehicle", "excavator", "truck", "crane"):
                mapping[cid] = ("vehicle", True)
        return mapping

    # -------------------------------------------------------------- analysis
    def analyze(self, img, zones=None, track_model=None) -> FrameResult:
        t0 = time.perf_counter()
        h, w = img.shape[:2]
        persons = self._detect_persons(img, track_model)
        vehicles = self._detect_vehicles(img)
        ppe_boxes = self._detect_ppe(img)
        for p in persons:
            self._judge_ppe(img, p, ppe_boxes)
        self._apply_rules(persons, vehicles, zones or [], w, h)
        latency = (time.perf_counter() - t0) * 1000
        self.last_latency_ms = latency
        return FrameResult(persons, vehicles, w, h, latency, self.mode)

    def _detect_persons(self, img, track_model):
        conf = self.cfg.get("person_conf", 0.4)
        imgsz = self.cfg.get("imgsz", 640)
        if track_model is not None:
            res = track_model.track(img, persist=True, conf=conf, imgsz=imgsz, verbose=False,
                                    tracker="bytetrack.yaml")[0]
        else:
            res = self.pose.predict(img, conf=conf, imgsz=imgsz, verbose=False)[0]
        if res.boxes is None or len(res.boxes) == 0:
            return []
        boxes = res.boxes.xyxy.cpu().numpy()
        confs = res.boxes.conf.cpu().numpy()
        ids = res.boxes.id.cpu().numpy().astype(int) if res.boxes.id is not None else None
        kps = res.keypoints.data.cpu().numpy() if res.keypoints is not None else None
        out = []
        for i, b in enumerate(boxes):
            out.append(Person(idx=i, box=tuple(float(v) for v in b), conf=float(confs[i]),
                              kps=kps[i] if kps is not None else None,
                              track_id=int(ids[i]) if ids is not None else None))
        return out

    def _detect_vehicles(self, img):
        out = []
        if self.objects is not None:
            res = self.objects.predict(img, conf=0.35, imgsz=self.cfg.get("imgsz", 640),
                                       classes=list(VEHICLE_COCO), verbose=False)[0]
            for b, c, k in zip(res.boxes.xyxy.cpu().numpy(), res.boxes.conf.cpu().numpy(),
                               res.boxes.cls.cpu().numpy().astype(int)):
                out.append({"label": VEHICLE_COCO.get(int(k), "vehicle"), "box": tuple(map(float, b)),
                            "conf": float(c)})
        return out

    def _detect_ppe(self, img):
        if self.ppe is None:
            return []
        res = self.ppe.predict(img, conf=self.cfg.get("ppe_conf", 0.4),
                               imgsz=self.cfg.get("imgsz", 640), verbose=False)[0]
        out = []
        for b, c, k in zip(res.boxes.xyxy.cpu().numpy(), res.boxes.conf.cpu().numpy(),
                           res.boxes.cls.cpu().numpy().astype(int)):
            if int(k) in self.ppe_classes:
                item, positive = self.ppe_classes[int(k)]
                out.append({"item": item, "positive": positive, "box": tuple(map(float, b)),
                            "conf": float(c)})
        return out

    # ------------------------------------------------------------ body parts
    def head_box(self, p: Person):
        """Approximate head box from face keypoints, else the top of the body box."""
        x1, y1, x2, y2 = p.box
        pts = [_kp(p.kps, i) for i in (NOSE, L_EYE, R_EYE, L_EAR, R_EAR)]
        pts = [q for q in pts if q]
        sho = [_kp(p.kps, i) for i in (L_SHO, R_SHO)]
        if len(pts) >= 2:
            xs, ys = [q[0] for q in pts], [q[1] for q in pts]
            size = max(max(xs) - min(xs), 0.0) * 1.8
            if sho[0] and sho[1]:
                size = max(size, abs(sho[0][0] - sho[1][0]) * 0.55)
            size = max(size, (x2 - x1) * 0.25)
            cx, cy = sum(xs) / len(xs), sum(ys) / len(ys)
            return cx - size / 2, cy - size * 0.65, cx + size / 2, cy + size * 0.55, True
        bw = x2 - x1
        return x1 + bw * 0.25, y1, x2 - bw * 0.25, y1 + (y2 - y1) * 0.16, False

    def torso_polygon(self, p: Person):
        pts = [_kp(p.kps, i) for i in (L_SHO, R_SHO, R_HIP, L_HIP)]
        if all(pts):
            return np.array(pts, dtype=np.int32)
        x1, y1, x2, y2 = p.box
        bh, bw = y2 - y1, x2 - x1
        return np.array([[x1 + bw * 0.2, y1 + bh * 0.2], [x2 - bw * 0.2, y1 + bh * 0.2],
                         [x2 - bw * 0.2, y1 + bh * 0.55], [x1 + bw * 0.2, y1 + bh * 0.55]],
                        dtype=np.int32)

    def foot_point(self, p: Person):
        ank = _mid(_kp(p.kps, L_ANK), _kp(p.kps, R_ANK))
        if ank:
            return ank
        return (p.box[0] + p.box[2]) / 2, p.box[3]

    # ------------------------------------------------------------------ PPE
    def _judge_ppe(self, img, p: Person, ppe_boxes):
        if p.height < MIN_PERSON_PX:
            p.ppe = {k: {"state": None, "conf": 0.0} for k in ("hardhat", "vest", "harness")}
            return
        if self.ppe is not None:
            p.ppe = self._ppe_from_model(p, ppe_boxes)
        else:
            p.ppe = self._ppe_from_colour(img, p)

    def _ppe_from_model(self, p: Person, ppe_boxes):
        hx1, hy1, hx2, hy2, _ = self.head_box(p)
        hy1 -= (hy2 - hy1) * 0.6  # helmets sit above the head keypoints
        x1, y1, x2, y2 = p.box
        result = {}
        for item in ("hardhat", "vest", "harness"):
            best = None
            for d in ppe_boxes:
                if d["item"] != item:
                    continue
                cx, cy = (d["box"][0] + d["box"][2]) / 2, (d["box"][1] + d["box"][3]) / 2
                if item == "hardhat":
                    inside = hx1 <= cx <= hx2 and hy1 <= cy <= hy2
                else:
                    inside = x1 <= cx <= x2 and y1 <= cy <= y2
                if inside and (best is None or d["conf"] > best["conf"]):
                    best = d
            if best is not None:
                result[item] = {"state": best["positive"], "conf": round(best["conf"], 3)}
            elif item == "harness" and not any(v[0] == "harness" for v in self.ppe_classes.values()):
                result[item] = {"state": None, "conf": 0.0}  # model cannot see harnesses
            else:
                result[item] = {"state": False, "conf": 0.5}
        return result

    @staticmethod
    def _ratio(mask_region, roi_mask=None):
        if roi_mask is not None:
            total = int(np.count_nonzero(roi_mask))
            hit = int(np.count_nonzero(mask_region & roi_mask))
        else:
            total = mask_region.size
            hit = int(np.count_nonzero(mask_region))
        return (hit / total if total else 0.0), total

    def _ppe_from_colour(self, img, p: Person):
        """Baseline until a PPE model is trained: look for helmet / hi-vis colours."""
        h, w = img.shape[:2]
        hsv = cv2.cvtColor(img, cv2.COLOR_BGR2HSV)
        H, S, V = hsv[..., 0], hsv[..., 1], hsv[..., 2]
        result = {"harness": {"state": None, "conf": 0.0}}

        # Hard hat: the area just above the eyes.
        hx1, hy1, hx2, hy2, from_kps = self.head_box(p)
        hh = hy2 - hy1
        cap = _clip_box(hx1 - (hx2 - hx1) * 0.1, hy1 - hh * 0.35, hx2 + (hx2 - hx1) * 0.1,
                        hy1 + hh * 0.35, w, h)
        if cap:
            cx1, cy1, cx2, cy2 = cap
            hs, ss, vs = H[cy1:cy2, cx1:cx2], S[cy1:cy2, cx1:cx2], V[cy1:cy2, cx1:cx2]
            white = (ss <= 45) & (vs >= 185)
            coloured = (ss >= 110) & (vs >= 120) & ((hs <= 35) | (hs >= 165) | ((hs >= 95) & (hs <= 130)))
            ratio, n = self._ratio(white | coloured)
            if n < 80:
                result["hardhat"] = {"state": None, "conf": 0.0}
            elif ratio >= 0.30:
                result["hardhat"] = {"state": True, "conf": round(min(0.95, 0.5 + ratio / 2), 3)}
            elif ratio <= 0.12:
                result["hardhat"] = {"state": False, "conf": round(min(0.9, 0.6 + (0.12 - ratio) * 2), 3)}
            else:
                result["hardhat"] = {"state": None, "conf": 0.0}
        else:
            result["hardhat"] = {"state": None, "conf": 0.0}

        # High-vis vest: fluorescent yellow / lime / orange share of the torso.
        poly = self.torso_polygon(p)
        roi = np.zeros((h, w), dtype=np.uint8)
        cv2.fillPoly(roi, [poly], 1)
        x, y, bw, bh = cv2.boundingRect(poly)
        box = _clip_box(x, y, x + bw, y + bh, w, h)
        if box:
            bx1, by1, bx2, by2 = box
            hs, ss, vs = H[by1:by2, bx1:bx2], S[by1:by2, bx1:bx2], V[by1:by2, bx1:bx2]
            hivis = (((hs >= 22) & (hs <= 45) & (ss >= 90) & (vs >= 140))
                     | ((hs >= 5) & (hs <= 18) & (ss >= 150) & (vs >= 150)))
            ratio, n = self._ratio(hivis, roi[by1:by2, bx1:bx2].astype(bool))
            if n < 150:
                result["vest"] = {"state": None, "conf": 0.0}
            elif ratio >= 0.12:
                result["vest"] = {"state": True, "conf": round(min(0.95, 0.55 + ratio), 3)}
            elif ratio <= 0.04:
                result["vest"] = {"state": False, "conf": round(min(0.9, 0.6 + (0.04 - ratio) * 5), 3)}
            else:
                result["vest"] = {"state": None, "conf": 0.0}
        else:
            result["vest"] = {"state": None, "conf": 0.0}
        return result

    # ----------------------------------------------------------------- rules
    def _apply_rules(self, persons, vehicles, zones, w, h):
        polys = []
        for z in zones:
            pts = np.array([[px * w, py * h] for px, py in z["polygon"]], dtype=np.float32)
            polys.append((z, pts))
        ratio = self.cfg.get("proximity_ratio", 0.6)
        for p in persons:
            v = []
            if p.ppe.get("hardhat", {}).get("state") is False:
                v.append("no_hardhat")
            if p.ppe.get("vest", {}).get("state") is False:
                v.append("no_vest")
            fx, fy = self.foot_point(p)
            for z, pts in polys:
                if cv2.pointPolygonTest(pts, (float(fx), float(fy)), False) >= 0:
                    p.zones.append(z["name"])
                    if z.get("type") == "restricted":
                        v.append("zone_breach")
                    elif z.get("type") == "height" and p.ppe.get("harness", {}).get("state") is False:
                        v.append("no_harness_at_height")
            if self._is_fallen(p):
                v.append("fall")
            for veh in vehicles:
                if self._gap(p, (fx, fy), veh["box"]) < ratio * max(p.height, 1):
                    v.append("vehicle_proximity")
                    break
            p.violations = sorted(set(v))

    @staticmethod
    def _gap(p, foot, vbox):
        # A person standing inside the vehicle box (in front of / on it) is not a pedestrian hazard
        # unless their feet are on the ground near it; use the foot point against the box edges.
        x1, y1, x2, y2 = vbox
        fx, fy = foot
        if p.box[0] >= x1 and p.box[2] <= x2 and p.box[1] >= y1 and p.box[3] <= y2:
            return float("inf")  # e.g. a driver inside the cab
        dx = max(x1 - fx, 0, fx - x2)
        dy = max(y1 - fy, 0, fy - y2)
        return math.hypot(dx, dy)

    @staticmethod
    def _is_fallen(p: Person):
        sho = _mid(_kp(p.kps, L_SHO), _kp(p.kps, R_SHO))
        hip = _mid(_kp(p.kps, L_HIP), _kp(p.kps, R_HIP))
        # Bending over (pointing, lifting) also tilts the torso. Only judge a fall when the
        # legs are in view, so a body cut off by the frame edge is not mistaken for one.
        legs_visible = any(_kp(p.kps, i) for i in (13, 14, 15, 16))
        if p.kps is not None and not legs_visible:
            return False
        if sho and hip:
            dx, dy = hip[0] - sho[0], hip[1] - sho[1]
            if math.hypot(dx, dy) < 10:
                return False
            return math.degrees(math.atan2(abs(dx), abs(dy))) > 60
        x1, y1, x2, y2 = p.box
        return (x2 - x1) > 1.6 * (y2 - y1)

    # -------------------------------------------------------------- imagery
    def blur_faces(self, img, persons):
        """KVKK: blur every visible face. Helmets above the eyes stay visible."""
        out = img.copy()
        h, w = out.shape[:2]
        for p in persons:
            hx1, hy1, hx2, hy2, from_kps = self.head_box(p)
            if from_kps:
                hh = hy2 - hy1
                box = _clip_box(hx1, hy1 + hh * 0.25, hx2, hy2 + hh * 0.15, w, h)
            else:
                box = _clip_box(hx1, hy1 + (hy2 - hy1) * 0.3, hx2, hy2 + (hy2 - hy1) * 0.4, w, h)
            if not box:
                continue
            x1, y1, x2, y2 = box
            roi = out[y1:y2, x1:x2]
            k = max(15, (min(x2 - x1, y2 - y1) // 2) | 1)
            out[y1:y2, x1:x2] = cv2.GaussianBlur(roi, (k, k), 0)
        return out

    def annotate(self, img, res: FrameResult, zones=None, skeleton=True):
        out = img.copy()
        h, w = out.shape[:2]
        th = max(1, round(min(w, h) / 400))
        fs = max(0.45, min(w, h) / 1100)
        overlay = out.copy()
        for z in zones or []:
            pts = np.array([[px * w, py * h] for px, py in z["polygon"]], dtype=np.int32)
            col = RED if z.get("type") == "restricted" else ORANGE
            cv2.fillPoly(overlay, [pts], col)
        out = cv2.addWeighted(overlay, 0.12, out, 0.88, 0)
        for z in zones or []:
            pts = np.array([[px * w, py * h] for px, py in z["polygon"]], dtype=np.int32)
            col = RED if z.get("type") == "restricted" else ORANGE
            cv2.polylines(out, [pts], True, col, th + 1, cv2.LINE_AA)
            _label(out, f"ZONE: {z['name']}".upper(), tuple(pts[0]), col, fs * 0.9, th)
        for v in res.vehicles:
            x1, y1, x2, y2 = map(int, v["box"])
            cv2.rectangle(out, (x1, y1), (x2, y2), YELLOW, th + 1)
            _label(out, f"{v['label'].upper()} {v['conf']:.0%}", (x1, y1), YELLOW, fs, th)
        for p in res.persons:
            col = RED if p.violations else GREEN
            x1, y1, x2, y2 = map(int, p.box)
            cv2.rectangle(out, (x1, y1), (x2, y2), col, th + 1)
            if skeleton and p.kps is not None:
                for a, b in SKELETON:
                    pa, pb = _kp(p.kps, a), _kp(p.kps, b)
                    if pa and pb:
                        cv2.line(out, tuple(map(int, pa)), tuple(map(int, pb)), ORANGE, th, cv2.LINE_AA)
            lines = [f"[W-{p.label_id}] " + ("VIOLATION" if p.violations else "PASS")]
            for item, name in (("hardhat", "HARD HAT"), ("vest", "HI-VIS VEST"), ("harness", "HARNESS")):
                st = p.ppe.get(item, {})
                if st.get("state") is True:
                    lines.append(f"+ {name} {st['conf']:.0%}")
                elif st.get("state") is False:
                    lines.append(f"x NO {name} {st['conf']:.0%}")
            if "zone_breach" in p.violations:
                lines.append("x DANGER ZONE")
            if "fall" in p.violations:
                lines.append("x POSSIBLE FALL")
            if "vehicle_proximity" in p.violations:
                lines.append("x NEAR MACHINERY")
            if "no_harness_at_height" in p.violations:
                lines.append("x NO HARNESS AT HEIGHT")
            yy = y1
            for i, line in enumerate(lines):
                c = col if i == 0 else (RED if line.startswith("x") else GREEN)
                yy = _label(out, line, (x1, yy if i == 0 else yy), c, fs, th, below=i > 0)
        return out


def _label(img, text, org, color, fs, th, below=False):
    """Draw a filled label; returns the y just below it so labels can stack."""
    (tw, tht), base = cv2.getTextSize(text, cv2.FONT_HERSHEY_SIMPLEX, fs, th)
    x, y = int(org[0]), int(org[1])
    pad = 3
    if below:
        top = y
    else:
        top = max(0, y - tht - base - 2 * pad)
    x = min(max(0, x), max(0, img.shape[1] - tw - 2 * pad))
    cv2.rectangle(img, (x, top), (x + tw + 2 * pad, top + tht + base + 2 * pad), (20, 17, 15), -1)
    cv2.rectangle(img, (x, top), (x + tw + 2 * pad, top + tht + base + 2 * pad), color, 1)
    cv2.putText(img, text, (x + pad, top + tht + pad), cv2.FONT_HERSHEY_SIMPLEX, fs, color, th, cv2.LINE_AA)
    return top + tht + base + 2 * pad


def person_json(p: Person, w, h):
    x1, y1, x2, y2 = p.box
    return {
        "id": p.label_id,
        "box": [round(x1 / w, 4), round(y1 / h, 4), round(x2 / w, 4), round(y2 / h, 4)],
        "conf": round(p.conf, 3),
        "ppe": p.ppe,
        "zones": p.zones,
        "violations": p.violations,
    }
