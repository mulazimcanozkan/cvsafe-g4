"""API tests for the endpoints used by the web panel: false-alarm reasons, incident
status flow (BR-02) and user editing / deactivation (FR-21, BR-11).

These tests need no sample images.  Run:  pytest -q tests/test_panel_api.py
"""
import os
import shutil
import tempfile
from pathlib import Path

import pytest

# Only used when this module is imported first; test_api.py sets the same variables.
_OWN_DATA = Path(tempfile.mkdtemp(prefix="cvsafe_panel_test_"))
os.environ.setdefault("CVSAFE_DATA", str(_OWN_DATA))
os.environ.setdefault("CVSAFE_DEMO", "1")
os.environ.setdefault("CVSAFE_STREAMS", "0")

from fastapi.testclient import TestClient  # noqa: E402

from app.main import app  # noqa: E402

PASSWORD = "cvsafe123"


@pytest.fixture(scope="module")
def client():
    with TestClient(app) as c:
        tok = c.post("/auth/login", json={"username": "admin", "password": PASSWORD}).json()["token"]
        c.headers["Authorization"] = f"Bearer {tok}"
        yield c
    shutil.rmtree(_OWN_DATA, ignore_errors=True)


def _open_incident_id(client):
    rows = client.get("/incidents", params={"status": "open"}).json()
    assert rows, "demo seed should provide open incidents"
    return rows[0]["id"]


def _new_user(client, username, role="field"):
    r = client.post("/users", json={"username": username, "name": username.title(), "role": role,
                                    "password": "secret12"})
    assert r.status_code == 200, r.text
    return r.json()


# ------------------------------------------------------------ false alarms
def test_false_alarm_reasons_lookup(client):
    reasons = client.get("/false_alarm_reasons").json()
    codes = [r["code"] for r in reasons]
    assert codes == ["wrong_detection", "authorised_person", "reflection_shadow", "other"]
    assert all(r["label"] for r in reasons)


def test_false_alarm_stores_reason_and_timeline(client):
    iid = _open_incident_id(client)
    r = client.post(f"/incidents/{iid}/false_alarm", json={"reason": "reflection_shadow", "note": "sun glare"})
    assert r.status_code == 200, r.text
    inc = r.json()
    assert inc["status"] == "false_alarm"
    assert inc["false_alarm_reason"] == "reflection_shadow"
    last = inc["timeline"][-1]["text"]
    assert "Reflection or shadow" in last and "sun glare" in last


def test_false_alarm_without_reason_defaults_to_other(client):
    """Older clients (current mobile app) send no reason; BR-02 still requires one."""
    iid = _open_incident_id(client)
    inc = client.post(f"/incidents/{iid}/false_alarm", json={}).json()
    assert inc["false_alarm_reason"] == "other"


def test_false_alarm_rejects_unknown_reason(client):
    iid = _open_incident_id(client)
    assert client.post(f"/incidents/{iid}/false_alarm", json={"reason": "bored"}).status_code == 400
    assert client.get(f"/incidents/{iid}").json()["status"] == "open"


# --------------------------------------------------------- status flow BR-02
def test_status_flow_has_no_way_back(client):
    iid = _open_incident_id(client)
    assert client.post(f"/incidents/{iid}/ack", json={}).json()["status"] == "acknowledged"
    # acknowledged -> acknowledged is not a change
    assert client.post(f"/incidents/{iid}/ack", json={}).status_code == 409
    # acknowledged -> false_alarm is allowed
    inc = client.post(f"/incidents/{iid}/false_alarm", json={"reason": "wrong_detection"}).json()
    assert inc["status"] == "false_alarm" and inc["ack_at"]
    # false_alarm is final
    assert client.post(f"/incidents/{iid}/ack", json={}).status_code == 409
    assert client.post(f"/incidents/{iid}/false_alarm", json={"reason": "other"}).status_code == 409


# ------------------------------------------------------------ user editing
def test_list_users_exposes_activity_fields(client):
    users = client.get("/users").json()
    admin = next(u for u in users if u["username"] == "admin")
    assert admin["is_active"] is True and admin["last_login_at"]


def test_update_name_and_role(client):
    u = _new_user(client, "mulazim")
    r = client.patch(f"/users/{u['id']}", json={"name": "Mulazim Ozkan", "role": "ohs"})
    assert r.status_code == 200, r.text
    assert r.json()["name"] == "Mulazim Ozkan" and r.json()["role"] == "ohs"
    assert client.patch(f"/users/{u['id']}", json={"role": "boss"}).status_code == 400
    assert client.patch(f"/users/{u['id']}", json={"name": "  "}).status_code == 400
    assert client.patch(f"/users/{u['id']}", json={"password": "x"}).status_code == 422  # unknown field
    assert client.patch("/users/999999", json={"name": "x"}).status_code == 404


def test_deactivate_revokes_sessions_and_blocks_login(client):
    u = _new_user(client, "batuhan")
    tok = client.post("/auth/login", json={"username": "batuhan", "password": "secret12"}).json()["token"]
    hdr = {"Authorization": f"Bearer {tok}"}
    assert client.get("/auth/me", headers=hdr).status_code == 200

    assert client.patch(f"/users/{u['id']}", json={"is_active": False}).json()["is_active"] is False
    assert client.get("/auth/me", headers=hdr).status_code == 401
    r = client.post("/auth/login", json={"username": "batuhan", "password": "secret12"})
    assert r.status_code == 403 and "deactivated" in r.json()["detail"]
    # wrong password on a deactivated account must not reveal its state
    assert client.post("/auth/login", json={"username": "batuhan", "password": "nope1234"}).status_code == 401

    assert client.patch(f"/users/{u['id']}", json={"is_active": True}).json()["is_active"] is True
    assert client.post("/auth/login", json={"username": "batuhan", "password": "secret12"}).status_code == 200


def test_admin_cannot_lock_themselves_out(client):
    me = client.get("/auth/me").json()
    assert client.patch(f"/users/{me['id']}", json={"role": "ohs"}).status_code == 400
    assert client.patch(f"/users/{me['id']}", json={"is_active": False}).status_code == 400
    assert client.patch(f"/users/{me['id']}", json={"name": "Site Admin"}).status_code == 200


def test_last_active_admin_rule(client):
    """BR-11: the last active administrator cannot be demoted or deactivated."""
    second = _new_user(client, "umut", role="admin")
    hdr = {"Authorization": "Bearer " + client.post(
        "/auth/login", json={"username": "umut", "password": "secret12"}).json()["token"]}
    me = client.get("/auth/me").json()
    # with two active admins, umut may deactivate the original admin ...
    assert client.patch(f"/users/{me['id']}", json={"is_active": False}, headers=hdr).status_code == 200
    # ... but now umut is the last active admin and cannot be demoted by anyone
    assert client.patch(f"/users/{second['id']}", json={"role": "field"}, headers=hdr).status_code == 400
    # restore the original admin (deactivation revoked its session, so sign in again)
    assert client.patch(f"/users/{me['id']}", json={"is_active": True}, headers=hdr).status_code == 200
    tok = client.post("/auth/login", json={"username": "admin", "password": PASSWORD}).json()["token"]
    client.headers["Authorization"] = f"Bearer {tok}"


def test_only_admin_can_edit_users(client):
    ohs = client.post("/auth/login", json={"username": "isg", "password": PASSWORD}).json()["token"]
    target = client.get("/users").json()[0]
    r = client.patch(f"/users/{target['id']}", json={"name": "x"}, headers={"Authorization": f"Bearer {ohs}"})
    assert r.status_code == 403
