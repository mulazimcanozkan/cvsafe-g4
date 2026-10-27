"""CVSAFE API - serves the mobile app and the web panel.

Run:  uvicorn app.main:app --host 0.0.0.0 --port 8000
"""
from __future__ import annotations

import logging
import os
import re
import tempfile
import time
from contextlib import asynccontextmanager
from pathlib import Path

import yaml
from fastapi import Depends, FastAPI, File, Form, Header, HTTPException, Query, UploadFile
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import Response
from fastapi.staticfiles import StaticFiles
from pydantic import BaseModel, Field
from starlette.concurrency import run_in_threadpool

from . import analytics as analytics_mod
from .auth import ROLES, Auth
from .report import build_pdf
from .service import SafetyService

BASE = Path(__file__).resolve().parent.parent
CONFIG = Path(os.environ.get("CVSAFE_CONFIG", BASE / "config.yaml"))
DATA = Path(os.environ.get("CVSAFE_DATA", BASE / "data"))
DATA.mkdir(parents=True, exist_ok=True)
(DATA / "media").mkdir(exist_ok=True)

DEFAULT_PASSWORD = os.environ.get("CVSAFE_ADMIN_PASSWORD", "cvsafe123")
MAX_IMAGE_MB = 15
MAX_VIDEO_MB = 300
VIDEO_EXT = {".mp4", ".mov", ".avi", ".mkv", ".3gp", ".webm", ".m4v"}
ID_RE = re.compile(r"^[A-Za-z0-9_-]{1,24}$")
log = logging.getLogger("cvsafe")

svc: SafetyService | None = None
auth: Auth | None = None


@asynccontextmanager
async def lifespan(_app):
    global svc, auth
    cfg = yaml.safe_load(CONFIG.read_text(encoding="utf-8"))
    svc = SafetyService(cfg, BASE, DATA)
    auth = Auth(svc.store)
    if auth.ensure_default_admin(DEFAULT_PASSWORD):
        print(f"\n  CVSAFE: first run - created user 'admin' with password '{DEFAULT_PASSWORD}'."
              f"\n  Log in and change it from the web panel (Users).\n", flush=True)
    if os.environ.get("CVSAFE_DEMO") == "1":
        from .seed import seed
        seed(svc)
        for uname, name, role in (("isg", "ISG Uzmani", "ohs"), ("saha", "Saha Sefi", "field")):
            try:
                auth.create_user(uname, name, role, DEFAULT_PASSWORD)
            except ValueError:
                pass  # already exists
    if os.environ.get("CVSAFE_STREAMS", "1") == "1":
        svc.start_streams()
    yield
    svc.stop_streams()


app = FastAPI(title="CVSAFE API", version="2.0.0", lifespan=lifespan)
app.add_middleware(CORSMiddleware, allow_origins=["*"], allow_methods=["*"], allow_headers=["*"])
# evidence images use long random file names; image widgets cannot send auth headers
app.mount("/media", StaticFiles(directory=str(DATA / "media")), name="media")


# -------------------------------------------------------------------- auth
def current_user(authorization: str | None = Header(None), token: str | None = Query(None)):
    """Bearer token from the header, or ?token= for links/images opened outside the app."""
    tok = token
    if authorization and authorization.lower().startswith("bearer "):
        tok = authorization[7:].strip()
    user = auth.user_for_token(tok)
    if not user:
        raise HTTPException(401, "Login required")
    user["_token"] = tok
    return user


def require(*roles):
    def dep(user=Depends(current_user)):
        if roles and user["role"] not in roles:
            raise HTTPException(403, "Your role cannot do this")
        return user
    return dep


ANY = Depends(require())
MANAGE = Depends(require("admin", "ohs"))
ADMIN = Depends(require("admin"))


class LoginBody(BaseModel):
    username: str
    password: str


class UserBody(BaseModel):
    username: str
    name: str = ""
    role: str = "field"
    password: str


class PasswordBody(BaseModel):
    password: str


class Note(BaseModel):
    note: str | None = None


class Action(BaseModel):
    kind: str  # siren | dispatch | broadcast | log
    note: str | None = None


class CameraBody(BaseModel):
    id: str
    name: str
    source: str | None = None
    subcontractor: str | None = None


class ZoneBody(BaseModel):
    id: str | None = None
    name: str
    type: str = "restricted"  # restricted | height
    polygon: list[list[float]] = Field(..., min_length=3)


class SubBody(BaseModel):
    id: str | None = None
    name: str
    trade: str = ""
    workers: int = 0


def _flag(v: str | None, default=True):
    """Multipart booleans arrive as text; a missing field keeps the default."""
    if v is None or v == "":
        return default
    return v.strip().lower() in ("1", "true", "yes", "on")


def _slug(text: str):
    s = re.sub(r"[^a-z0-9]+", "-", text.lower()).strip("-")
    return (s or "item")[:24]


def _incident_or_404(iid: int):
    inc = svc.store.get_incident(iid)
    if not inc:
        raise HTTPException(404, "Incident not found")
    return inc


def _camera_or_404(cam_id: str):
    cam = svc.cameras.get(cam_id)
    if not cam:
        raise HTTPException(404, "Camera not found")
    return cam


@app.post("/auth/login")
def login(body: LoginBody):
    res = auth.login(body.username, body.password)
    if not res:
        raise HTTPException(401, "Wrong username or password")
    return res


@app.get("/auth/me")
def me(user=ANY):
    return {k: v for k, v in user.items() if not k.startswith("_")}


@app.post("/auth/logout")
def logout(user=ANY):
    auth.logout(user["_token"])
    return {"ok": True}


@app.post("/auth/password")
def change_own_password(body: PasswordBody, user=ANY):
    try:
        auth.set_password(user["id"], body.password)
    except ValueError as e:
        raise HTTPException(400, str(e))
    return {"ok": True}


@app.get("/users")
def users(user=ADMIN):
    return auth.list_users()


@app.post("/users")
def create_user(body: UserBody, user=ADMIN):
    try:
        return auth.create_user(body.username, body.name, body.role, body.password)
    except ValueError as e:
        raise HTTPException(400, str(e))


@app.delete("/users/{uid}")
def delete_user(uid: int, user=ADMIN):
    target = auth.get_user(uid)
    if not target:
        raise HTTPException(404, "User not found")
    if target["id"] == user["id"]:
        raise HTTPException(400, "You cannot delete yourself")
    if target["role"] == "admin" and auth.count_admins() <= 1:
        raise HTTPException(400, "At least one admin must remain")
    auth.delete_user(uid)
    return {"ok": True}


@app.post("/users/{uid}/password")
def reset_password(uid: int, body: PasswordBody, user=ADMIN):
    if not auth.get_user(uid):
        raise HTTPException(404, "User not found")
    try:
        auth.set_password(uid, body.password)
    except ValueError as e:
        raise HTTPException(400, str(e))
    return {"ok": True}


# ------------------------------------------------------------------ status
@app.get("/health")
def health():
    workers = svc.workers.values()
    return {
        "status": "ok",
        "mode": svc.detector.mode,
        "streams_total": len(workers),
        "streams_active": sum(1 for w in workers if w.online),
        "latency_ms": round(svc.detector.last_latency_ms, 1),
        "agg_fps": round(sum(w.fps for w in workers), 1),
        "server_time": time.time(),
        "roles": list(ROLES),
    }


@app.get("/site")
def site(user=ANY):
    cams = []
    for c in svc.cameras.values():
        w = svc.workers.get(c["id"])
        open_n = svc.store.query("SELECT COUNT(*) AS n FROM incidents WHERE camera_id=? AND status='open'",
                                 (c["id"],))[0]["n"]
        cam = {"id": c["id"], "name": c["name"], "subcontractor": svc.sub_name(c),
               "subcontractor_id": c.get("subcontractor"),
               "live": bool(w and w.online), "fps": w.fps if w else 0, "persons": w.persons if w else 0,
               "open_violations": open_n, "has_reference": bool(c.get("reference")),
               "zones": [{"id": z["id"], "name": z["name"], "type": z["type"], "polygon": z["polygon"]}
                         for z in c.get("zones", [])]}
        if user["role"] == "admin":
            cam["source"] = c.get("source")  # may contain camera passwords
        cams.append(cam)
    return {"site": svc.cfg.get("site", {}), "cameras": cams,
            "subcontractors": list(svc.subs.values()), "mode": svc.detector.mode}


# ----------------------------------------------------------- site management
@app.post("/cameras")
def save_camera(body: CameraBody, user=ADMIN):
    if not ID_RE.match(body.id):
        raise HTTPException(400, "Camera ID may use letters, digits, '-' and '_' (max 24)")
    if not body.name.strip():
        raise HTTPException(400, "Camera name is required")
    if body.subcontractor and body.subcontractor not in svc.subs:
        raise HTTPException(400, "Unknown subcontractor")
    svc.upsert_camera({"id": body.id, "name": body.name.strip(), "source": (body.source or "").strip() or None,
                       "subcontractor": body.subcontractor or None})
    return site(user)


@app.delete("/cameras/{cam_id}")
def delete_camera(cam_id: str, user=ADMIN):
    _camera_or_404(cam_id)
    svc.delete_camera(cam_id)
    return {"ok": True}


@app.put("/cameras/{cam_id}/zones")
def put_zones(cam_id: str, zones: list[ZoneBody], user=MANAGE):
    _camera_or_404(cam_id)
    clean, used = [], set()
    for z in zones:
        if z.type not in ("restricted", "height"):
            raise HTTPException(400, f"Unknown zone type {z.type}")
        if not z.name.strip():
            raise HTTPException(400, "Every zone needs a name")
        pts = [[round(min(1, max(0, p[0])), 4), round(min(1, max(0, p[1])), 4)] for p in z.polygon if len(p) == 2]
        if len(pts) < 3:
            raise HTTPException(400, f"Zone '{z.name}' needs at least 3 points")
        zid = z.id if z.id and ID_RE.match(z.id) else _slug(z.name)
        while zid in used:
            zid = f"{zid[:20]}-{len(used)}"
        used.add(zid)
        clean.append({"id": zid, "name": z.name.strip(), "type": z.type, "polygon": pts})
    svc.set_zones(cam_id, clean)
    return clean


@app.post("/cameras/{cam_id}/reference")
async def upload_reference(cam_id: str, file: UploadFile = File(...), user=MANAGE):
    """A still photo of the camera view, used to draw zones when no live stream is available."""
    _camera_or_404(cam_id)
    data = await file.read()
    if len(data) > MAX_IMAGE_MB * 1024 * 1024:
        raise HTTPException(413, f"Image larger than {MAX_IMAGE_MB} MB")
    try:
        svc.set_reference(cam_id, data)
    except ValueError as e:
        raise HTTPException(400, str(e))
    return {"ok": True}


@app.get("/cameras/{cam_id}/frame")
def camera_frame(cam_id: str, user=ANY):
    """Live frame if streaming, else the reference photo, else the newest evidence image."""
    cam = _camera_or_404(cam_id)
    w = svc.workers.get(cam_id)
    if w and w.latest_jpeg:
        return Response(w.latest_jpeg, media_type="image/jpeg", headers={"Cache-Control": "no-store"})
    candidates = []
    if cam.get("reference"):
        candidates.append(cam["reference"])
    last = svc.store.query("SELECT raw_image FROM incidents WHERE camera_id=? AND raw_image IS NOT NULL "
                           "ORDER BY created_at DESC LIMIT 1", (cam_id,))
    if last:
        candidates.append(last[0]["raw_image"])
    for name in candidates:
        p = svc.media / name
        if p.is_file():
            return Response(p.read_bytes(), media_type="image/jpeg", headers={"Cache-Control": "no-store"})
    raise HTTPException(404, "No image for this camera yet")


@app.get("/cameras/{cam_id}/snapshot")
def snapshot(cam_id: str, user=ANY):
    w = svc.workers.get(cam_id)
    if not w or not w.latest_jpeg:
        raise HTTPException(404, "No live frame for this camera")
    return Response(w.latest_jpeg, media_type="image/jpeg", headers={"Cache-Control": "no-store"})


@app.post("/subcontractors")
def save_sub(body: SubBody, user=MANAGE):
    if not body.name.strip():
        raise HTTPException(400, "Name is required")
    sid = body.id if body.id and ID_RE.match(body.id) else _slug(body.name)
    return svc.upsert_sub({"id": sid, "name": body.name.strip(), "trade": body.trade.strip(),
                           "workers": max(0, body.workers)})


@app.delete("/subcontractors/{sub_id}")
def delete_sub(sub_id: str, user=MANAGE):
    if not svc.delete_sub(sub_id):
        raise HTTPException(404, "Subcontractor not found")
    return {"ok": True}


# --------------------------------------------------------------- incidents
@app.get("/incidents")
def incidents(status: str | None = Query(None, description="open|acknowledged|false_alarm|active"),
              category: str | None = Query(None, description="ppe|zone|height|fall|proximity"),
              camera_id: str | None = None, limit: int = Query(50, le=500), offset: int = Query(0, ge=0),
              since: float | None = None, user=ANY):
    return svc.store.list_incidents(status=status, category=category, limit=limit, since=since,
                                    camera_id=camera_id, offset=offset)


@app.get("/incidents/{iid}")
def incident(iid: int, user=ANY):
    return _incident_or_404(iid)


@app.post("/incidents/{iid}/ack")
def acknowledge(iid: int, body: Note | None = None, user=ANY):
    _incident_or_404(iid)
    svc.store.set_status(iid, "acknowledged", body.note if body else None, actor=user["name"])
    return svc.store.get_incident(iid)


@app.post("/incidents/{iid}/false_alarm")
def false_alarm(iid: int, body: Note | None = None, user=ANY):
    _incident_or_404(iid)
    svc.store.set_status(iid, "false_alarm", body.note if body else None, actor=user["name"])
    return svc.store.get_incident(iid)


@app.post("/incidents/{iid}/action")
def action(iid: int, body: Action, user=ANY):
    if body.kind not in {"siren", "dispatch", "broadcast", "log"}:
        raise HTTPException(400, "Unknown action")
    _incident_or_404(iid)
    svc.store.log_action(iid, body.kind, body.note, actor=user["name"])
    return svc.store.get_incident(iid)


# ----------------------------------------------------------------- analysis
@app.post("/analyze/image")
async def analyze_image(file: UploadFile = File(...), camera_id: str | None = Form(None),
                        create_incidents: str | None = Form(None), user=ANY):
    data = await file.read()
    if len(data) > MAX_IMAGE_MB * 1024 * 1024:
        raise HTTPException(413, f"Image larger than {MAX_IMAGE_MB} MB")
    try:
        return await run_in_threadpool(svc.analyze_image, data, camera_id or None, _flag(create_incidents))
    except ValueError as e:
        raise HTTPException(400, str(e))


@app.post("/analyze/video")
async def analyze_video(file: UploadFile = File(...), camera_id: str | None = Form(None),
                        create_incidents: str | None = Form(None), user=ANY):
    ext = Path(file.filename or "").suffix.lower() or ".mp4"
    if ext not in VIDEO_EXT:
        raise HTTPException(400, f"Unsupported video type {ext}")
    tmp = tempfile.NamedTemporaryFile(delete=False, suffix=ext, dir=str(DATA))
    size = 0
    with tmp:
        while chunk := await file.read(1024 * 1024):
            size += len(chunk)
            if size > MAX_VIDEO_MB * 1024 * 1024:
                tmp.close()
                Path(tmp.name).unlink(missing_ok=True)
                raise HTTPException(413, f"Video larger than {MAX_VIDEO_MB} MB")
            tmp.write(chunk)
    return svc.start_video_job(tmp.name, camera_id or None, _flag(create_incidents))


@app.get("/jobs/{job_id}")
def job(job_id: str, user=ANY):
    j = svc.jobs.get(job_id)
    if not j:
        raise HTTPException(404, "Job not found")
    return j


# ---------------------------------------------------------------- analytics
@app.get("/analytics")
def analytics(range: str = Query("today", pattern="^(today|week|month)$"), user=ANY):
    return analytics_mod.compute(svc.store, svc.cfg, range)


@app.get("/reports/summary.pdf")
def report(range: str = Query("today", pattern="^(today|week|month)$"), user=ANY):
    stats = analytics_mod.compute(svc.store, svc.cfg, range)
    since = time.time() - analytics_mod.RANGES[range]
    incs = svc.store.list_incidents(limit=200, since=since)
    pdf = build_pdf(stats, incs, svc.cfg, str(svc.media))
    return Response(pdf, media_type="application/pdf",
                    headers={"Content-Disposition": f'inline; filename="cvsafe_{range}.pdf"'})
