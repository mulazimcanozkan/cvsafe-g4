"""End-to-end API test. Needs two sample images in tests/samples/ (any photos with people):
   people.jpg and street.jpg. A short video is synthesised from people.jpg.
Run:  pytest -q tests
"""
import os
import shutil
import tempfile
import time
from pathlib import Path

import cv2
import numpy as np
import pytest

SAMPLES = Path(__file__).parent / "samples"
DATA = Path(tempfile.mkdtemp(prefix="cvsafe_test_"))
os.environ["CVSAFE_DATA"] = str(DATA)
os.environ["CVSAFE_DEMO"] = "1"
os.environ["CVSAFE_STREAMS"] = "0"

from fastapi.testclient import TestClient  # noqa: E402

from app.main import app  # noqa: E402


@pytest.fixture(scope="module")
def client():
    with TestClient(app) as c:
        tok = c.post("/auth/login", json={"username": "admin", "password": "cvsafe123"}).json()["token"]
        c.headers["Authorization"] = f"Bearer {tok}"
        yield c
    shutil.rmtree(DATA, ignore_errors=True)


def login_as(client, username):
    r = client.post("/auth/login", json={"username": username, "password": "cvsafe123"})
    assert r.status_code == 200, r.text
    return {"Authorization": f"Bearer {r.json()['token']}"}


def make_video(src: Path, dst: Path, seconds=4, fps=25):
    img = cv2.imread(str(src))
    h, w = img.shape[:2]
    out = cv2.VideoWriter(str(dst), cv2.VideoWriter_fourcc(*"mp4v"), fps, (w, h))
    for i in range(seconds * fps):
        m = np.float32([[1, 0, int(10 * np.sin(i / 10))], [0, 1, 0]])  # slight camera shake
        out.write(cv2.warpAffine(img, m, (w, h), borderMode=cv2.BORDER_REFLECT))
    out.release()


def test_health_and_site(client):
    h = client.get("/health").json()
    assert h["status"] == "ok" and h["mode"] in ("baseline", "ppe-model")
    s = client.get("/site").json()
    assert len(s["cameras"]) == 4 and s["cameras"][0]["zones"] is not None


def test_demo_seed_and_analytics(client):
    incs = client.get("/incidents").json()
    assert len(incs) >= 3
    a = client.get("/analytics", params={"range": "week"}).json()
    assert 0 <= a["compliance_index"] <= 100 and a["total_scanned"] > 0
    assert a["leaderboard"] and a["breakdown"]


def test_image_analysis_creates_incident(client):
    with open(SAMPLES / "street.jpg", "rb") as f:
        r = client.post("/analyze/image", files={"file": ("street.jpg", f, "image/jpeg")},
                        data={"camera_id": "CAM-01"})
    assert r.status_code == 200, r.text
    body = r.json()
    assert body["summary"]["persons"] >= 1
    assert client.get(body["image_url"]).status_code == 200
    assert body["incident_ids"]
    inc = client.get(f"/incidents/{body['incident_ids'][0]}").json()
    assert inc["source"] == "upload" and inc["image_url"] and inc["timeline"]


def test_incident_workflow(client):
    iid = client.get("/incidents", params={"status": "open"}).json()[0]["id"]
    assert client.post(f"/incidents/{iid}/action", json={"kind": "siren"}).status_code == 200
    r = client.post(f"/incidents/{iid}/ack", json={"note": "worker warned"}).json()
    assert r["status"] == "acknowledged" and r["ack_at"]
    assert any("siren" in e["text"].lower() for e in r["timeline"])
    iid2 = client.get("/incidents", params={"status": "open"}).json()[0]["id"]
    assert client.post(f"/incidents/{iid2}/false_alarm", json={}).json()["status"] == "false_alarm"


def test_video_job(client, tmp_path):
    vid = tmp_path / "clip.mp4"
    make_video(SAMPLES / "people.jpg", vid)
    with open(vid, "rb") as f:
        job = client.post("/analyze/video", files={"file": ("clip.mp4", f, "video/mp4")}).json()
    for _ in range(240):
        j = client.get(f"/jobs/{job['id']}").json()
        if j["status"] in ("done", "error"):
            break
        time.sleep(0.5)
    assert j["status"] == "done", j
    res = j["result"]
    assert res["frames_analyzed"] >= 10 and res["persons_tracked"] >= 1
    assert res["incidents"], "persistent violations should become incidents"
    assert res["incidents"][0]["incident_id"]


def test_bad_inputs(client):
    r = client.post("/analyze/image", files={"file": ("x.jpg", b"not an image", "image/jpeg")})
    assert r.status_code == 400
    r = client.post("/analyze/video", files={"file": ("x.exe", b"123", "application/octet-stream")})
    assert r.status_code == 400
    assert client.get("/incidents/999999").status_code == 404


def test_pdf_report(client):
    r = client.get("/reports/summary.pdf", params={"range": "week"})
    assert r.status_code == 200 and r.content[:4] == b"%PDF"


def test_auth_required_and_roles(client):
    bare = TestClient(app)
    assert bare.get("/incidents").status_code == 401
    assert bare.get("/health").status_code == 200
    assert client.post("/auth/login", json={"username": "admin", "password": "wrong"}).status_code == 401
    field = login_as(client, "saha")
    assert client.get("/incidents", headers=field).status_code == 200
    assert client.get("/users", headers=field).status_code == 403
    assert client.put("/cameras/CAM-01/zones", json=[], headers=field).status_code == 403
    ohs = login_as(client, "isg")
    assert client.post("/cameras", json={"id": "X", "name": "x"}, headers=ohs).status_code == 403
    # token in the query string works for links opened outside the app (PDF, images)
    tok = field["Authorization"].split()[1]
    assert bare.get(f"/reports/summary.pdf?token={tok}").status_code == 200
    # source URLs (may contain passwords) are only shown to admins
    assert "source" not in client.get("/site", headers=field).json()["cameras"][0]
    assert "source" in client.get("/site").json()["cameras"][0]


def test_user_management(client):
    u = client.post("/users", json={"username": "gorkem", "name": "Gorkem", "role": "ohs",
                                    "password": "secret1"}).json()
    assert u["role"] == "ohs"
    assert client.post("/users", json={"username": "gorkem", "name": "x", "role": "ohs",
                                       "password": "secret1"}).status_code == 400
    assert client.post("/users", json={"username": "kisa", "role": "ohs", "password": "123"}).status_code == 400
    assert client.post("/auth/login", json={"username": "gorkem", "password": "secret1"}).status_code == 200
    assert client.post(f"/users/{u['id']}/password", json={"password": "newpass1"}).status_code == 200
    assert client.post("/auth/login", json={"username": "gorkem", "password": "newpass1"}).status_code == 200
    me = client.get("/auth/me").json()
    assert client.delete(f"/users/{me['id']}").status_code == 400  # cannot delete yourself
    assert client.delete(f"/users/{u['id']}").status_code == 200


def test_camera_zone_subcontractor_management(client):
    s = client.post("/subcontractors", json={"name": "Yeni Taseron Ltd", "trade": "Electrical", "workers": 7}).json()
    assert s["id"] == "yeni-taseron-ltd"
    r = client.post("/cameras", json={"id": "CAM-09", "name": "Gate", "subcontractor": s["id"]})
    assert r.status_code == 200, r.text
    assert any(c["id"] == "CAM-09" for c in r.json()["cameras"])
    assert client.post("/cameras", json={"id": "bad id!", "name": "x"}).status_code == 400
    zones = [{"name": "Loading Bay", "type": "restricted", "polygon": [[0, 0.5], [1, 0.5], [1, 1], [0, 1]]},
             {"name": "Roof Edge", "type": "height", "polygon": [[0, 0], [1, 0], [1, 0.3], [0, 0.3]]}]
    saved = client.put("/cameras/CAM-09/zones", json=zones).json()
    assert [z["id"] for z in saved] == ["loading-bay", "roof-edge"]
    assert client.put("/cameras/CAM-09/zones", json=[{"name": "x", "polygon": [[0, 0], [1, 1]]}]).status_code == 422
    # no image yet -> 404, then upload a reference photo
    assert client.get("/cameras/CAM-09/frame").status_code == 404
    with open(SAMPLES / "street.jpg", "rb") as f:
        assert client.post("/cameras/CAM-09/reference", files={"file": ("ref.jpg", f, "image/jpeg")}).status_code == 200
    fr = client.get("/cameras/CAM-09/frame")
    assert fr.status_code == 200 and fr.headers["content-type"] == "image/jpeg"
    # zones apply to scans assigned to the camera
    with open(SAMPLES / "street.jpg", "rb") as f:
        res = client.post("/analyze/image", files={"file": ("s.jpg", f, "image/jpeg")},
                          data={"camera_id": "CAM-09"}).json()
    assert any(p["zones"] for p in res["persons"])
    inc = client.get(f"/incidents/{res['incident_ids'][0]}").json()
    assert inc["subcontractor"] == "Yeni Taseron Ltd"
    assert client.get("/incidents", params={"camera_id": "CAM-09"}).json()
    assert client.delete("/subcontractors/" + s["id"]).status_code == 200
    assert client.delete("/cameras/CAM-09").status_code == 200
    assert client.get("/cameras/CAM-09/frame").status_code == 404


def test_filters_and_trend(client):
    zone = client.get("/incidents", params={"category": "zone", "limit": 100}).json()
    assert zone and all("zone" in i["categories"] for i in zone)
    page2 = client.get("/incidents", params={"limit": 2, "offset": 2}).json()
    page1 = client.get("/incidents", params={"limit": 2}).json()
    assert {i["id"] for i in page1}.isdisjoint({i["id"] for i in page2})
    a = client.get("/analytics", params={"range": "week"}).json()
    assert len(a["trend"]) == 7 and "by_camera" in a
    assert len(client.get("/analytics").json()["trend"]) == 24
