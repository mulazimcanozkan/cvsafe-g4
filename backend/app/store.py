"""SQLite persistence for incidents, their timeline and scan statistics."""
from __future__ import annotations

import json
import sqlite3
import threading
import time

from .rules import VIOLATIONS, incident_severity, incident_title

SCHEMA = """
CREATE TABLE IF NOT EXISTS incidents (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    created_at REAL NOT NULL,
    updated_at REAL NOT NULL,
    camera_id TEXT,
    camera_name TEXT,
    zone_name TEXT,
    subcontractor TEXT,
    types TEXT NOT NULL,
    title TEXT NOT NULL,
    severity TEXT NOT NULL,
    confidence REAL,
    person_ids TEXT,
    count INTEGER DEFAULT 1,
    status TEXT DEFAULT 'open',
    ack_at REAL,
    source TEXT,
    image TEXT,
    raw_image TEXT,
    meta TEXT
);
CREATE TABLE IF NOT EXISTS events (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    incident_id INTEGER NOT NULL,
    ts REAL NOT NULL,
    kind TEXT NOT NULL,
    text TEXT NOT NULL
);
CREATE TABLE IF NOT EXISTS scans (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    ts REAL NOT NULL,
    camera_id TEXT,
    subcontractor TEXT,
    persons INTEGER NOT NULL,
    compliant INTEGER NOT NULL,
    ppe_ok INTEGER NOT NULL,
    source TEXT
);
CREATE TABLE IF NOT EXISTS settings (
    key TEXT PRIMARY KEY,
    value TEXT NOT NULL
);
CREATE INDEX IF NOT EXISTS idx_inc_created ON incidents(created_at);
CREATE INDEX IF NOT EXISTS idx_scan_ts ON scans(ts);
"""


class Store:
    def __init__(self, path):
        self.db = sqlite3.connect(path, check_same_thread=False)
        self.db.row_factory = sqlite3.Row
        self.lock = threading.Lock()
        with self.lock:
            self.db.executescript(SCHEMA)
            self.db.commit()

    # ---------------------------------------------------------------- writes
    def add_incident(self, *, types, camera=None, zone_name=None, subcontractor=None, confidence=None,
                     person_ids=None, count=1, source="camera", image=None, raw_image=None, meta=None,
                     ts=None, status="open"):
        ts = ts or time.time()
        types = sorted(set(types))
        cam_id = camera["id"] if camera else None
        cam_name = camera["name"] if camera else None
        with self.lock:
            cur = self.db.execute(
                """INSERT INTO incidents (created_at, updated_at, camera_id, camera_name, zone_name, subcontractor,
                   types, title, severity, confidence, person_ids, count, status, source, image, raw_image, meta)
                   VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)""",
                (ts, ts, cam_id, cam_name, zone_name, subcontractor, json.dumps(types), incident_title(types),
                 incident_severity(types), confidence, json.dumps(person_ids or []), count, status, source,
                 image, raw_image, json.dumps(meta or {})))
            iid = cur.lastrowid
            where = f"{cam_id} / {zone_name}" if zone_name else (cam_id or "upload")
            self._event(iid, ts, "ai", f"{incident_title(types)} flagged at {where}.")
            self._event(iid, ts + 0.5, "telemetry", "Push alert dispatched to field manager.")
            self.db.commit()
        return iid

    def bump_incident(self, iid, extra_types=None, image=None, raw_image=None):
        """Merge a repeated detection into an existing open incident."""
        with self.lock:
            row = self.db.execute("SELECT types, count FROM incidents WHERE id=?", (iid,)).fetchone()
            if not row:
                return
            types = sorted(set(json.loads(row["types"])) | set(extra_types or []))
            now = time.time()
            self.db.execute(
                """UPDATE incidents SET types=?, title=?, severity=?, count=?, updated_at=?,
                   image=COALESCE(?, image), raw_image=COALESCE(?, raw_image) WHERE id=?""",
                (json.dumps(types), incident_title(types), incident_severity(types), row["count"] + 1, now,
                 image, raw_image, iid))
            self._event(iid, now, "ai", "Repeat detection merged into this incident.")
            self.db.commit()

    def set_status(self, iid, status, note=None, actor=None):
        now = time.time()
        with self.lock:
            row = self.db.execute("SELECT status FROM incidents WHERE id=?", (iid,)).fetchone()
            if not row:
                return False
            self.db.execute("UPDATE incidents SET status=?, ack_at=COALESCE(ack_at, ?), updated_at=? WHERE id=?",
                            (status, now, now, iid))
            text = {"acknowledged": "Acknowledged & addressed by field manager.",
                    "false_alarm": "Marked as false alarm (sent to AI feedback loop)."}.get(status, status)
            if actor:
                text = text.replace("field manager", actor) if "field manager" in text else f"{text} ({actor})"
            if note:
                text += f" Note: {note}"
            self._event(iid, now, "user", text)
            self.db.commit()
        return True

    def log_action(self, iid, kind, note=None, actor=None):
        texts = {"siren": "Site siren triggered.", "dispatch": "Field warden dispatched over radio.",
                 "broadcast": "Warning broadcast to zone.", "log": "Verbal warning logged."}
        now = time.time()
        with self.lock:
            if not self.db.execute("SELECT 1 FROM incidents WHERE id=?", (iid,)).fetchone():
                return False
            text = texts.get(kind, kind) + (f" ({actor})" if actor else "") + (f" {note}" if note else "")
            self._event(iid, now, "action", text)
            self.db.execute("UPDATE incidents SET updated_at=? WHERE id=?", (now, iid))
            self.db.commit()
        return True

    def add_scan(self, *, persons, compliant, ppe_ok, camera_id=None, subcontractor=None, source="camera",
                 ts=None):
        with self.lock:
            self.db.execute("INSERT INTO scans (ts, camera_id, subcontractor, persons, compliant, ppe_ok, source)"
                            " VALUES (?,?,?,?,?,?,?)",
                            (ts or time.time(), camera_id, subcontractor, persons, compliant, ppe_ok, source))
            self.db.commit()

    def _event(self, iid, ts, kind, text):
        self.db.execute("INSERT INTO events (incident_id, ts, kind, text) VALUES (?,?,?,?)", (iid, ts, kind, text))

    # ----------------------------------------------------------------- reads
    def recent_open(self, camera_id, types, within_s=120):
        with self.lock:
            row = self.db.execute(
                "SELECT id FROM incidents WHERE camera_id=? AND types=? AND status='open' AND updated_at>? "
                "ORDER BY id DESC LIMIT 1",
                (camera_id, json.dumps(sorted(set(types))), time.time() - within_s)).fetchone()
        return row["id"] if row else None

    def list_incidents(self, status=None, category=None, limit=50, since=None, camera_id=None, offset=0):
        q, args = "SELECT * FROM incidents WHERE 1=1", []
        if camera_id:
            q += " AND camera_id=?"
            args.append(camera_id)
        if status == "active":
            q += " AND status='open'"
        elif status:
            q += " AND status=?"
            args.append(status)
        if since:
            q += " AND created_at>=?"
            args.append(since)
        if category:
            # categories derive from the violation types stored as JSON
            from .rules import VIOLATIONS
            types = [t for t, v in VIOLATIONS.items() if v["category"] == category]
            if not types:
                return []
            q += " AND (" + " OR ".join("types LIKE ?" for _ in types) + ")"
            args += [f'%"{t}"%' for t in types]
        q += " ORDER BY created_at DESC LIMIT ? OFFSET ?"
        args += [limit, offset]
        with self.lock:
            return [self._row(r) for r in self.db.execute(q, args).fetchall()]

    def get_incident(self, iid):
        with self.lock:
            row = self.db.execute("SELECT * FROM incidents WHERE id=?", (iid,)).fetchone()
            if not row:
                return None
            ev = self.db.execute("SELECT ts, kind, text FROM events WHERE incident_id=? ORDER BY ts", (iid,)).fetchall()
        out = self._row(row)
        out["timeline"] = [dict(e) for e in ev]
        return out

    def get_setting(self, key, default=None):
        with self.lock:
            row = self.db.execute("SELECT value FROM settings WHERE key=?", (key,)).fetchone()
        return json.loads(row["value"]) if row else default

    def set_setting(self, key, value):
        with self.lock:
            self.db.execute("INSERT INTO settings (key, value) VALUES (?, ?) "
                            "ON CONFLICT(key) DO UPDATE SET value=excluded.value", (key, json.dumps(value)))
            self.db.commit()

    def query(self, sql, args=()):
        with self.lock:
            return [dict(r) for r in self.db.execute(sql, args).fetchall()]

    @staticmethod
    def _row(r):
        d = dict(r)
        d["types"] = json.loads(d["types"])
        d["person_ids"] = json.loads(d["person_ids"] or "[]")
        d["meta"] = json.loads(d["meta"] or "{}")
        d["categories"] = sorted({VIOLATIONS[t]["category"] for t in d["types"] if t in VIOLATIONS})
        d["references"] = sorted({VIOLATIONS[t]["reference"] for t in d["types"] if t in VIOLATIONS})
        d["image_url"] = f"/media/{d['image']}" if d.get("image") else None
        d["raw_url"] = f"/media/{d['raw_image']}" if d.get("raw_image") else None
        return d
