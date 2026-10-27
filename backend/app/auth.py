"""Users, password hashing and login sessions (bearer tokens).

Roles
  admin  - everything, including users and cameras
  ohs    - OHS specialist: incidents, zones, subcontractors, reports
  field  - site manager: sees alerts, responds to them, runs AI scans
"""
from __future__ import annotations

import hashlib
import hmac
import secrets
import time

ROLES = ("admin", "ohs", "field")
SESSION_DAYS = 7
_ITER = 200_000

SCHEMA = """
CREATE TABLE IF NOT EXISTS users (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    username TEXT UNIQUE NOT NULL,
    name TEXT NOT NULL,
    role TEXT NOT NULL,
    pw_hash TEXT NOT NULL,
    created_at REAL NOT NULL
);
CREATE TABLE IF NOT EXISTS sessions (
    token TEXT PRIMARY KEY,
    user_id INTEGER NOT NULL,
    expires REAL NOT NULL
);
"""


def hash_password(pw: str) -> str:
    salt = secrets.token_hex(16)
    digest = hashlib.pbkdf2_hmac("sha256", pw.encode(), bytes.fromhex(salt), _ITER).hex()
    return f"{salt}${digest}"


def check_password(pw: str, stored: str) -> bool:
    try:
        salt, digest = stored.split("$", 1)
    except ValueError:
        return False
    test = hashlib.pbkdf2_hmac("sha256", pw.encode(), bytes.fromhex(salt), _ITER).hex()
    return hmac.compare_digest(test, digest)


def _public(row):
    return None if row is None else {"id": row["id"], "username": row["username"], "name": row["name"],
                                     "role": row["role"]}


class Auth:
    def __init__(self, store):
        self.store = store
        with store.lock:
            store.db.executescript(SCHEMA)
            store.db.commit()

    def ensure_default_admin(self, password: str):
        """First run: create admin so someone can log in. Returns True if created."""
        with self.store.lock:
            n = self.store.db.execute("SELECT COUNT(*) FROM users").fetchone()[0]
        if n:
            return False
        self.create_user("admin", "Site Administrator", "admin", password)
        return True

    def create_user(self, username, name, role, password):
        username = username.strip().lower()
        if role not in ROLES:
            raise ValueError("Unknown role")
        if not username or not username.replace(".", "").replace("_", "").isalnum():
            raise ValueError("Username may contain letters, digits, '.' and '_' only")
        if len(password) < 6:
            raise ValueError("Password must be at least 6 characters")
        with self.store.lock:
            if self.store.db.execute("SELECT 1 FROM users WHERE username=?", (username,)).fetchone():
                raise ValueError("Username already exists")
            cur = self.store.db.execute(
                "INSERT INTO users (username, name, role, pw_hash, created_at) VALUES (?,?,?,?,?)",
                (username, name.strip() or username, role, hash_password(password), time.time()))
            self.store.db.commit()
            return self.get_user(cur.lastrowid, locked=True)

    def get_user(self, uid, locked=False):
        if locked:
            row = self.store.db.execute("SELECT * FROM users WHERE id=?", (uid,)).fetchone()
        else:
            with self.store.lock:
                row = self.store.db.execute("SELECT * FROM users WHERE id=?", (uid,)).fetchone()
        return _public(row)

    def list_users(self):
        with self.store.lock:
            rows = self.store.db.execute("SELECT * FROM users ORDER BY role, username").fetchall()
        return [_public(r) for r in rows]

    def delete_user(self, uid):
        with self.store.lock:
            self.store.db.execute("DELETE FROM sessions WHERE user_id=?", (uid,))
            cur = self.store.db.execute("DELETE FROM users WHERE id=?", (uid,))
            self.store.db.commit()
            return cur.rowcount > 0

    def count_admins(self):
        with self.store.lock:
            return self.store.db.execute("SELECT COUNT(*) FROM users WHERE role='admin'").fetchone()[0]

    def set_password(self, uid, password):
        if len(password) < 6:
            raise ValueError("Password must be at least 6 characters")
        with self.store.lock:
            self.store.db.execute("UPDATE users SET pw_hash=? WHERE id=?", (hash_password(password), uid))
            self.store.db.execute("DELETE FROM sessions WHERE user_id=?", (uid,))
            self.store.db.commit()

    def login(self, username, password):
        with self.store.lock:
            row = self.store.db.execute("SELECT * FROM users WHERE username=?",
                                        (username.strip().lower(),)).fetchone()
        if row is None or not check_password(password, row["pw_hash"]):
            return None
        token = secrets.token_urlsafe(32)
        with self.store.lock:
            self.store.db.execute("DELETE FROM sessions WHERE expires<?", (time.time(),))
            self.store.db.execute("INSERT INTO sessions (token, user_id, expires) VALUES (?,?,?)",
                                  (token, row["id"], time.time() + SESSION_DAYS * 86400))
            self.store.db.commit()
        return {"token": token, "user": _public(row)}

    def user_for_token(self, token):
        if not token:
            return None
        with self.store.lock:
            row = self.store.db.execute(
                "SELECT u.* FROM sessions s JOIN users u ON u.id=s.user_id WHERE s.token=? AND s.expires>?",
                (token, time.time())).fetchone()
        return _public(row)

    def logout(self, token):
        with self.store.lock:
            self.store.db.execute("DELETE FROM sessions WHERE token=?", (token,))
            self.store.db.commit()
