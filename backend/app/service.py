"""Glue between the detector, the incident store and the API."""
from __future__ import annotations

import threading
import time
import uuid
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path

import cv2
import numpy as np

from .detector import Detector, FrameResult, person_json
from .rules import VIOLATIONS, incident_title, incident_severity
from .store import Store
from .tracking import ViolationTracker

MAX_SIDE = 1920
PPE_TYPES = {"no_hardhat", "no_vest", "no_harness_at_height"}


class SafetyService:
    def __init__(self, cfg: dict, base_dir: Path, data_dir: Path):
        self.cfg = cfg
        self.base = base_dir
        self.media = data_dir / "media"
        self.media.mkdir(parents=True, exist_ok=True)
        self.store = Store(str(data_dir / "cvsafe.db"))
        self.det_cfg = cfg.get("detection", {})
        self.detector = Detector(self.det_cfg, base_dir)
        self.detector_lock = threading.Lock()  # YOLO models are not thread-safe
        # cameras, zones and subcontractors are edited from the web panel and live in the
        # database; config.yaml only seeds them on the very first run
        cams = self.store.get_setting("cameras")
        subs = self.store.get_setting("subcontractors")
        if cams is None:
            cams = cfg.get("cameras", [])
            self.store.set_setting("cameras", cams)
        if subs is None:
            subs = cfg.get("subcontractors", [])
            self.store.set_setting("subcontractors", subs)
        self.cameras = {c["id"]: c for c in cams}
        self.subs = {s["id"]: s for s in subs}
        self._sync_cfg()
        self.jobs: dict[str, dict] = {}
        self.pool = ThreadPoolExecutor(max_workers=1)
        self.workers: dict[str, "CameraWorker"] = {}
        self.streams_enabled = False

    # ------------------------------------------------------- site management
    def _sync_cfg(self):
        self.cfg["cameras"] = list(self.cameras.values())
        self.cfg["subcontractors"] = list(self.subs.values())

    def _save_cameras(self):
        self.store.set_setting("cameras", list(self.cameras.values()))
        self._sync_cfg()

    def _save_subs(self):
        self.store.set_setting("subcontractors", list(self.subs.values()))
        self._sync_cfg()

    def upsert_camera(self, cam: dict):
        old = self.cameras.get(cam["id"], {})
        merged = {**old, **cam}
        merged.setdefault("zones", [])
        self.cameras[cam["id"]] = merged
        self._save_cameras()
        if old.get("source") != merged.get("source") or cam["id"] not in self.workers:
            self.restart_worker(cam["id"])
        return merged

    def delete_camera(self, cam_id):
        if cam_id not in self.cameras:
            return False
        w = self.workers.pop(cam_id, None)
        if w:
            w.stop()
        del self.cameras[cam_id]
        self._save_cameras()
        return True

    def set_zones(self, cam_id, zones):
        self.cameras[cam_id]["zones"] = zones
        self._save_cameras()  # running workers read zones on every frame

    def set_reference(self, cam_id, data: bytes):
        img = self.decode_image(data)
        name = f"ref_{cam_id}_{uuid.uuid4().hex[:6]}.jpg"
        cv2.imwrite(str(self.media / name), img, [cv2.IMWRITE_JPEG_QUALITY, 88])
        old = self.cameras[cam_id].get("reference")
        if old:
            (self.media / old).unlink(missing_ok=True)
        self.cameras[cam_id]["reference"] = name
        self._save_cameras()
        return name

    def upsert_sub(self, sub: dict):
        self.subs[sub["id"]] = {**self.subs.get(sub["id"], {}), **sub}
        self._save_subs()
        return self.subs[sub["id"]]

    def delete_sub(self, sub_id):
        if sub_id not in self.subs:
            return False
        del self.subs[sub_id]
        for c in self.cameras.values():
            if c.get("subcontractor") == sub_id:
                c["subcontractor"] = None
        self._save_subs()
        self._save_cameras()
        return True

    def restart_worker(self, cam_id):
        w = self.workers.pop(cam_id, None)
        if w:
            w.stop()
        cam = self.cameras.get(cam_id)
        if cam and cam.get("source") and self.streams_enabled:
            nw = CameraWorker(self, cam)
            self.workers[cam_id] = nw
            nw.start()

    # ---------------------------------------------------------------- helpers
    def camera(self, cam_id):
        return self.cameras.get(cam_id) if cam_id else None

    def sub_name(self, cam):
        if cam and cam.get("subcontractor") in self.subs:
            return self.subs[cam["subcontractor"]]["name"]
        return None

    def save_jpeg(self, img, prefix):
        name = f"{prefix}_{uuid.uuid4().hex[:10]}.jpg"
        cv2.imwrite(str(self.media / name), img, [cv2.IMWRITE_JPEG_QUALITY, 85])
        return name

    @staticmethod
    def decode_image(data: bytes):
        arr = np.frombuffer(data, dtype=np.uint8)
        img = cv2.imdecode(arr, cv2.IMREAD_COLOR)
        if img is None:
            raise ValueError("Could not read image")
        h, w = img.shape[:2]
        if max(h, w) > MAX_SIDE:
            s = MAX_SIDE / max(h, w)
            img = cv2.resize(img, (int(w * s), int(h * s)), interpolation=cv2.INTER_AREA)
        return img

    def _evidence(self, img, res: FrameResult, zones):
        blurred = self.detector.blur_faces(img, res.persons) if self.det_cfg.get("blur_faces", True) else img
        annotated = self.detector.annotate(blurred, res, zones)
        return annotated, blurred

    def _record_scan(self, res: FrameResult, cam, source):
        judged = [p for p in res.persons]
        if not judged:
            return
        compliant = sum(1 for p in judged if not p.violations)
        ppe_ok = sum(1 for p in judged if not (set(p.violations) & PPE_TYPES))
        self.store.add_scan(persons=len(judged), compliant=compliant, ppe_ok=ppe_ok,
                            camera_id=cam["id"] if cam else None,
                            subcontractor=cam.get("subcontractor") if cam else None, source=source)

    @staticmethod
    def _summary(res: FrameResult):
        counts = res.violation_counts()
        return {
            "persons": len(res.persons),
            "compliant": sum(1 for p in res.persons if not p.violations),
            "violations": [{"type": t, "title": VIOLATIONS[t]["title"], "severity": VIOLATIONS[t]["severity"],
                            "count": c} for t, c in sorted(counts.items(), key=lambda x: -x[1])],
        }

    # ------------------------------------------------------------ image scan
    def analyze_image(self, data: bytes, camera_id=None, create_incidents=True):
        img = self.decode_image(data)
        cam = self.camera(camera_id)
        zones = cam.get("zones", []) if cam else []
        with self.detector_lock:
            res = self.detector.analyze(img, zones)
            annotated, blurred = self._evidence(img, res, zones)
        ann_name, raw_name = self.save_jpeg(annotated, "scan"), self.save_jpeg(blurred, "raw")
        self._record_scan(res, cam, "upload")

        incident_ids = []
        if create_incidents:
            groups: dict[tuple, list] = {}
            for p in res.persons:
                if p.violations:
                    groups.setdefault(tuple(p.violations), []).append(p)
            for types, people in groups.items():
                zone = next((z for p in people for z in p.zones), None)
                conf = max((p.ppe.get(i, {}).get("conf", 0) for p in people for i in ("hardhat", "vest")),
                           default=0) or max(p.conf for p in people)
                incident_ids.append(self.store.add_incident(
                    types=types, camera=cam, zone_name=zone, subcontractor=self.sub_name(cam),
                    confidence=round(conf, 3), person_ids=[p.label_id for p in people], count=len(people),
                    source="upload", image=ann_name, raw_image=raw_name,
                    meta={"mode": res.mode, "persons": [person_json(p, res.width, res.height) for p in people]}))
        return {
            "kind": "image",
            "mode": res.mode,
            "width": res.width,
            "height": res.height,
            "latency_ms": round(res.latency_ms, 1),
            "image_url": f"/media/{ann_name}",
            "raw_url": f"/media/{raw_name}",
            "persons": [person_json(p, res.width, res.height) for p in res.persons],
            "vehicles": [{"label": v["label"], "conf": round(v["conf"], 3)} for v in res.vehicles],
            "summary": self._summary(res),
            "incident_ids": incident_ids,
        }

    # ------------------------------------------------------------ video scan
    def start_video_job(self, path: str, camera_id=None, create_incidents=True):
        job_id = uuid.uuid4().hex[:12]
        self.jobs[job_id] = {"id": job_id, "status": "queued", "progress": 0.0, "result": None, "error": None}
        self.pool.submit(self._run_video, job_id, path, camera_id, create_incidents)
        return self.jobs[job_id]

    def _run_video(self, job_id, path, camera_id, create_incidents):
        job = self.jobs[job_id]
        job["status"] = "running"
        try:
            job["result"] = self.analyze_video(path, camera_id, create_incidents,
                                               progress=lambda f: job.__setitem__("progress", round(f, 3)))
            job["status"], job["progress"] = "done", 1.0
        except Exception as e:  # report the failure to the app instead of hanging
            job["status"], job["error"] = "error", str(e)
        finally:
            Path(path).unlink(missing_ok=True)

    def analyze_video(self, path, camera_id=None, create_incidents=True, progress=None):
        vcfg = self.det_cfg.get("video", {})
        cap = cv2.VideoCapture(path)
        if not cap.isOpened():
            raise ValueError("Could not open video")
        fps = cap.get(cv2.CAP_PROP_FPS) or 25.0
        total = int(cap.get(cv2.CAP_PROP_FRAME_COUNT) or 0)
        step = max(1, round(fps / vcfg.get("sample_fps", 3)))
        max_frames = int(vcfg.get("max_seconds", 180) * fps)
        limit = min(total, max_frames) if total > 0 else max_frames
        cam = self.camera(camera_id)
        zones = cam.get("zones", []) if cam else []
        tracker = ViolationTracker(vcfg.get("min_frames", 3))
        track_model = self.detector.new_tracking_model()
        found: dict[int, dict] = {}   # track id -> incident record
        frames, idx, latencies = 0, 0, []
        persons_frames = compliant_frames = ppe_frames = 0
        while idx < limit:
            ok = cap.grab()
            if not ok:
                break
            if idx % step == 0:
                ok, frame = cap.retrieve()
                if not ok:
                    break
                h, w = frame.shape[:2]
                if max(h, w) > 1280:
                    s = 1280 / max(h, w)
                    frame = cv2.resize(frame, (int(w * s), int(h * s)), interpolation=cv2.INTER_AREA)
                with self.detector_lock:
                    res = self.detector.analyze(frame, zones, track_model=track_model)
                latencies.append(res.latency_ms)
                frames += 1
                persons_frames += len(res.persons)
                compliant_frames += sum(1 for p in res.persons if not p.violations)
                ppe_frames += sum(1 for p in res.persons if not (set(p.violations) & PPE_TYPES))
                new = tracker.update(res.persons)
                if new:
                    with self.detector_lock:
                        annotated, blurred = self._evidence(frame, res, zones)
                    t_off = idx / fps
                    for tid, types in new.items():
                        person = next((p for p in res.persons if (p.track_id if p.track_id is not None
                                                                   else -(p.idx + 1)) == tid), None)
                        rec = found.get(tid)
                        if rec is None:
                            found[tid] = {"track_id": tid, "types": set(types), "t_offset": round(t_off, 2),
                                          "frame": annotated, "raw": blurred,
                                          "zone": person.zones[0] if person and person.zones else None,
                                          "conf": person.conf if person else None}
                        else:
                            rec["types"] |= set(types)
                            rec["frame"], rec["raw"] = annotated, blurred
                if progress and limit:
                    progress(min(0.99, idx / limit))
            idx += 1
        cap.release()

        # statistics for the analytics dashboard: one scan per tracked person
        stats = tracker.stats()
        if stats["persons_tracked"]:
            violators_ppe = sum(1 for r in found.values() if r["types"] & PPE_TYPES)
            self.store.add_scan(persons=stats["persons_tracked"], compliant=stats["persons_compliant"],
                                ppe_ok=stats["persons_tracked"] - violators_ppe,
                                camera_id=cam["id"] if cam else None,
                                subcontractor=cam.get("subcontractor") if cam else None, source="video")

        incidents = []
        for rec in sorted(found.values(), key=lambda r: r["t_offset"]):
            types = sorted(rec["types"])
            ann_name, raw_name = self.save_jpeg(rec["frame"], "vid"), self.save_jpeg(rec["raw"], "raw")
            iid = None
            if create_incidents:
                iid = self.store.add_incident(
                    types=types, camera=cam, zone_name=rec["zone"], subcontractor=self.sub_name(cam),
                    confidence=round(rec["conf"], 3) if rec["conf"] else None, person_ids=[rec["track_id"]],
                    source="video", image=ann_name, raw_image=raw_name,
                    meta={"t_offset": rec["t_offset"], "mode": self.detector.mode})
            incidents.append({"incident_id": iid, "track_id": rec["track_id"], "t_offset": rec["t_offset"],
                              "types": types, "title": incident_title(types), "severity": incident_severity(types),
                              "image_url": f"/media/{ann_name}"})
        counts = {}
        for r in found.values():
            for t in r["types"]:
                counts[t] = counts.get(t, 0) + 1
        return {
            "kind": "video",
            "mode": self.detector.mode,
            "duration_s": round((total or idx) / fps, 1),
            "analyzed_s": round(idx / fps, 1),
            "frames_analyzed": frames,
            "sample_fps": round(fps / step, 2),
            "latency_ms": round(sum(latencies) / len(latencies), 1) if latencies else 0,
            "persons_tracked": stats["persons_tracked"],
            "persons_compliant": stats["persons_compliant"],
            "frame_compliance": round(compliant_frames / persons_frames, 3) if persons_frames else None,
            "summary": {"violations": [{"type": t, "title": VIOLATIONS[t]["title"],
                                        "severity": VIOLATIONS[t]["severity"], "count": c}
                                       for t, c in sorted(counts.items(), key=lambda x: -x[1])]},
            "incidents": incidents,
        }

    # -------------------------------------------------------------- streams
    def start_streams(self):
        self.streams_enabled = True
        for cam in self.cameras.values():
            if cam.get("source"):
                w = CameraWorker(self, cam)
                self.workers[cam["id"]] = w
                w.start()

    def stop_streams(self):
        for w in self.workers.values():
            w.stop()


class CameraWorker(threading.Thread):
    """Reads an RTSP stream (or a looping video file), analyses a few frames per
    second and raises incidents for violations that persist."""

    def __init__(self, svc: SafetyService, cam: dict, process_fps=2.0):
        super().__init__(daemon=True)
        self.svc, self.cam = svc, cam
        self.interval = 1.0 / process_fps
        self.running = True
        self.latest_jpeg: bytes | None = None
        self.fps = 0.0
        self.latency_ms = 0.0
        self.persons = 0
        self.online = False

    def stop(self):
        self.running = False

    def run(self):
        src = self.cam["source"]
        model = self.svc.detector.new_tracking_model()
        tracker = ViolationTracker(self.svc.det_cfg.get("video", {}).get("min_frames", 3))
        open_by_track: dict[int, int] = {}
        last_scan = 0.0
        while self.running:
            cap = cv2.VideoCapture(src)
            self.online = cap.isOpened()
            if not self.online:
                time.sleep(5)
                continue
            # a local video file is replayed in real time to simulate a camera
            is_file = not str(src).lower().startswith(("rtsp://", "http://", "https://"))
            frame_dt = 1.0 / (cap.get(cv2.CAP_PROP_FPS) or 25.0) if is_file else 0.0
            last = 0.0
            while self.running:
                ok, frame = cap.read()
                if not ok:
                    break  # stream dropped or file ended -> reopen (files loop)
                if is_file:
                    time.sleep(frame_dt)
                now = time.time()
                if now - last < self.interval:
                    continue
                self.fps = round(1.0 / max(now - last, 1e-3), 1) if last else 0.0
                last = now
                cam = self.svc.cameras.get(self.cam["id"], self.cam)  # zones may be edited live
                zones = cam.get("zones", [])
                with self.svc.detector_lock:
                    res = self.svc.detector.analyze(frame, zones, track_model=model)
                    annotated, blurred = self.svc._evidence(frame, res, zones)
                self.latency_ms, self.persons = res.latency_ms, len(res.persons)
                ok, buf = cv2.imencode(".jpg", annotated, [cv2.IMWRITE_JPEG_QUALITY, 75])
                if ok:
                    self.latest_jpeg = buf.tobytes()
                if now - last_scan > 10:  # one statistics sample every 10 s
                    self.svc._record_scan(res, cam, "camera")
                    last_scan = now
                for tid, types in tracker.update(res.persons).items():
                    ann, raw = self.svc.save_jpeg(annotated, "cam"), self.svc.save_jpeg(blurred, "raw")
                    person = next((p for p in res.persons if p.track_id == tid), None)
                    iid = open_by_track.get(tid)
                    if iid and self.svc.store.get_incident(iid)["status"] == "open":
                        self.svc.store.bump_incident(iid, types, ann, raw)
                    else:
                        open_by_track[tid] = self.svc.store.add_incident(
                            types=types, camera=cam,
                            zone_name=person.zones[0] if person and person.zones else None,
                            subcontractor=self.svc.sub_name(cam),
                            confidence=round(person.conf, 3) if person else None, person_ids=[tid],
                            source="camera", image=ann, raw_image=raw, meta={"mode": res.mode})
            cap.release()
            self.online = False
