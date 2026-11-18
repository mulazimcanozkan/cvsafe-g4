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

# Columns added after the first prototype release (soft delete and last sign-in for the web panel).
MIGRATIONS = {
    "users": {
        "is_active": "INTEGER NOT NULL DEFAULT 1",  # 0 = deactivated, cannot sign in (FR-21)
        "last_login_at": "REAL",
    },
}


class AccountDisabled(Exception):
    """Raised on sign-in with the correct password for a deactivated account."""


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
    if row is None:
        return None
    keys = row.keys()
    return {"id": row["id"], "username": row["username"], "name": row["name"], "role": row["role"],
            "is_active": bool(row["is_active"]) if "is_active" in keys else True,
            "last_login_at": row["last_login_at"] if "last_login_at" in keys else None}


class Auth:
    def __init__(self, store):
        from .store import ensure_columns

        self.store = store
        with store.lock:
            store.db.executescript(SCHEMA)
            ensure_columns(store.db, MIGRATIONS)
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
        """Number of active administrators (BR-11: at least one must remain)."""
        with self.store.lock:
            return self.store.db.execute(
                "SELECT COUNT(*) FROM users WHERE role='admin' AND is_active=1").fetchone()[0]

    def update_user(self, uid, *, name=None, role=None, is_active=None):
        """Change display name, role and/or active flag. Deactivation revokes all sessions.

        Business rules that need the acting user (BR-11, no self-lockout) are checked by the API.
        """
        sets, args = [], []
        if name is not None:
            if not name.strip():
                raise ValueError("Name cannot be empty")
            sets.append("name=?")
            args.append(name.strip())
        if role is not None:
            if role not in ROLES:
                raise ValueError("Unknown role")
            sets.append("role=?")
            args.append(role)
        if is_active is not None:
            sets.append("is_active=?")
            args.append(1 if is_active else 0)
        with self.store.lock:
            if sets:
                self.store.db.execute(f"UPDATE users SET {', '.join(sets)} WHERE id=?", (*args, uid))
            if is_active is False:
                self.store.db.execute("DELETE FROM sessions WHERE user_id=?", (uid,))
            self.store.db.commit()
            return self.get_user(uid, locked=True)

    def set_password(self, uid, password):
        if len(password) < 6:
            raise ValueError("Password must be at least 6 characters")
        with self.store.lock:
            self.store.db.execute("UPDATE users SET pw_hash=? WHERE id=?", (hash_password(password), uid))
            self.store.db.execute("DELETE FROM sessions WHERE user_id=?", (uid,))
            self.store.db.commit()

    def login(self, username, password):
        """Returns {token, user} or None for wrong credentials; raises AccountDisabled if deactivated."""
        with self.store.lock:
            row = self.store.db.execute("SELECT * FROM users WHERE username=?",
                                        (username.strip().lower(),)).fetchone()
        if row is None or not check_password(password, row["pw_hash"]):
            return None
        if not row["is_active"]:
            raise AccountDisabled()
        token = secrets.token_urlsafe(32)
        now = time.time()
        with self.store.lock:
            self.store.db.execute("DELETE FROM sessions WHERE expires<?", (now,))
            self.store.db.execute("INSERT INTO sessions (token, user_id, expires) VALUES (?,?,?)",
                                  (token, row["id"], now + SESSION_DAYS * 86400))
            self.store.db.execute("UPDATE users SET last_login_at=? WHERE id=?", (now, row["id"]))
            self.store.db.commit()
            user = self.get_user(row["id"], locked=True)
        return {"token": token, "user": user}

    def user_for_token(self, token):
        if not token:
            return None
        with self.store.lock:
            row = self.store.db.execute(
                "SELECT u.* FROM sessions s JOIN users u ON u.id=s.user_id "
                "WHERE s.token=? AND s.expires>? AND u.is_active=1",
                (token, time.time())).fetchone()
        return _public(row)

    def logout(self, token):
        with self.store.lock:
            self.store.db.execute("DELETE FROM sessions WHERE token=?", (token,))
            self.store.db.commit()
