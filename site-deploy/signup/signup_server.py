#!/usr/bin/env python3
"""chirpchirps.com "tell me when it is out" list: self-hosted, SQLite, standard library only.

    signup_server.py                 serve on 127.0.0.1:$PORT (default 3330)
    signup_server.py --list          print the stored addresses (oldest first)

POST /api/signup   email=<address>  (form or JSON). Stores the address and the
                   time, nothing else: no IP address, no user agent, no cookie.
                   A browser form gets a redirect to /thanks.html; a fetch that
                   asks for JSON gets {"ok": true}. An address already stored
                   answers the same way (nobody learns who has signed up).
GET  /api/health   {"ok": true, "signups": N}

nginx sits in front (rate limit per address, 4 KB body limit). The server also
caps itself at HOURLY_CAP new rows an hour, so a flood cannot fill the disk.
The hidden "company" field is a bot trap: a filled one is answered as a success
and stored nowhere.

Copied from creasecracker.com's (/root/crease-cracker/site/deploy/signup/), which is modelled on borrowedcarts.com's.
The list is for one email on release day and is deleted after it (chirpchirps.com/privacy, "Release list", says so).

Database: $SIGNUP_DB (default /var/lib/chirpchirps/signups.db).
"""
from __future__ import annotations

import json
import os
import re
import sqlite3
import sys
import threading
from datetime import datetime, timedelta, timezone
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import parse_qs

DB = os.environ.get("SIGNUP_DB", "/var/lib/chirpchirps/signups.db")
PORT = int(os.environ.get("PORT", "3330"))
HOURLY_CAP = int(os.environ.get("SIGNUP_HOURLY_CAP", "300"))
MAX_BODY = 4096
EMAIL = re.compile(r"^[A-Za-z0-9.!#$%&'*+/=?^_`{|}~-]+@[A-Za-z0-9](?:[A-Za-z0-9-]{0,61}[A-Za-z0-9])?"
                   r"(?:\.[A-Za-z0-9](?:[A-Za-z0-9-]{0,61}[A-Za-z0-9])?)+$")
LOCK = threading.Lock()


def db() -> sqlite3.Connection:
    con = sqlite3.connect(DB, timeout=10)
    con.execute("CREATE TABLE IF NOT EXISTS signups (id INTEGER PRIMARY KEY, email TEXT NOT NULL UNIQUE, "
                "created_at TEXT NOT NULL, source TEXT NOT NULL DEFAULT 'site')")
    return con


def valid(email: str) -> bool:
    return 5 <= len(email) <= 254 and len(email.split("@")[0]) <= 64 and bool(EMAIL.match(email))


def store(email: str) -> str:
    """'ok', or 'busy' when the hourly cap is reached."""
    now = datetime.now(timezone.utc)
    with LOCK, db() as con:
        since = (now - timedelta(hours=1)).isoformat(timespec="seconds")
        if con.execute("SELECT COUNT(*) FROM signups WHERE created_at >= ?", (since,)).fetchone()[0] >= HOURLY_CAP:
            return "busy"
        con.execute("INSERT OR IGNORE INTO signups (email, created_at) VALUES (?, ?)",
                    (email, now.isoformat(timespec="seconds")))
    return "ok"


class Handler(BaseHTTPRequestHandler):
    server_version = "signup"
    sys_version = ""

    def log_message(self, fmt, *args):          # no request log: it would hold addresses' timing and nothing useful
        pass

    def _send(self, code: int, obj: dict, redirect: str | None = None) -> None:
        wants_json = "application/json" in (self.headers.get("Accept") or "")
        if redirect and not wants_json:
            self.send_response(303); self.send_header("Location", redirect)
            self.send_header("Content-Length", "0"); self.end_headers()
            return
        body = json.dumps(obj).encode()
        self.send_response(code)
        self.send_header("Content-Type", "application/json")
        self.send_header("Cache-Control", "no-store")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def do_GET(self):
        if self.path == "/api/health":
            with db() as con:
                n = con.execute("SELECT COUNT(*) FROM signups").fetchone()[0]
            return self._send(200, {"ok": True, "signups": n})
        self._send(404, {"ok": False, "error": "Not found."})

    def do_POST(self):
        if self.path != "/api/signup":
            return self._send(404, {"ok": False, "error": "Not found."})
        try:
            n = int(self.headers.get("Content-Length") or 0)
        except ValueError:
            n = -1
        if n <= 0 or n > MAX_BODY:
            return self._send(400, {"ok": False, "error": "Please enter an email address."})
        raw = self.rfile.read(n).decode("utf-8", "replace")
        if "json" in (self.headers.get("Content-Type") or ""):
            try:
                data = json.loads(raw)
                f = {k: str(v) for k, v in data.items()} if isinstance(data, dict) else {}
            except ValueError:
                f = {}
        else:
            f = {k: v[0] for k, v in parse_qs(raw, keep_blank_values=True).items()}
        if (f.get("company") or "").strip():                  # the bot trap
            return self._send(200, {"ok": True}, redirect="/thanks.html")
        email = (f.get("email") or "").strip().lower()
        if not valid(email):
            return self._send(400, {"ok": False, "error": "That does not look like an email address."}, redirect="/?signup=invalid#notify")
        if store(email) == "busy":
            return self._send(503, {"ok": False, "error": "We are a little busy. Please try again in an hour."}, redirect="/?signup=busy#notify")
        self._send(200, {"ok": True}, redirect="/thanks.html")


def main() -> None:
    if "--list" in sys.argv:
        with db() as con:
            for email, at in con.execute("SELECT email, created_at FROM signups ORDER BY id"):
                print(f"{at}\t{email}")
        return
    os.makedirs(os.path.dirname(DB), exist_ok=True)
    db().close()
    ThreadingHTTPServer(("127.0.0.1", PORT), Handler).serve_forever()


if __name__ == "__main__":
    main()
