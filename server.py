"""Local SQLite API for the tournament demo. Start with: python server.py"""
from http.server import SimpleHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
import json
import sqlite3
from datetime import datetime, timezone

ROOT = Path(__file__).resolve().parent
DB_PATH = ROOT / "giai-dau.sqlite3"


def connect_db():
    db = sqlite3.connect(DB_PATH)
    db.row_factory = sqlite3.Row
    db.execute("PRAGMA foreign_keys = ON")
    db.execute("""CREATE TABLE IF NOT EXISTS app_state (
        id INTEGER PRIMARY KEY CHECK (id = 1),
        payload TEXT NOT NULL,
        updated_at TEXT NOT NULL
    )""")
    db.execute("""CREATE TABLE IF NOT EXISTS accounts (
        id TEXT PRIMARY KEY,
        username TEXT NOT NULL UNIQUE,
        password TEXT NOT NULL,
        display_name TEXT NOT NULL,
        role TEXT NOT NULL,
        athlete_id TEXT,
        updated_at TEXT NOT NULL
    )""")
    for table, extra in {
        "tournaments": "sport TEXT NOT NULL DEFAULT ''",
        "teams": "tournament_id TEXT NOT NULL DEFAULT ''",
        "athletes": "team_id TEXT NOT NULL DEFAULT ''",
        "matches": "tournament_id TEXT NOT NULL DEFAULT ''",
        "events": "tournament_id TEXT NOT NULL DEFAULT '', match_id TEXT NOT NULL DEFAULT ''",
        "venues": "sport TEXT NOT NULL DEFAULT ''",
        "refs": "sport TEXT NOT NULL DEFAULT ''",
    }.items():
        db.execute(f"CREATE TABLE IF NOT EXISTS {table} (id TEXT PRIMARY KEY, {extra}, payload TEXT NOT NULL)")
    return db


class Handler(SimpleHTTPRequestHandler):
    def __init__(self, *args, **kwargs):
        super().__init__(*args, directory=str(ROOT), **kwargs)

    def end_headers(self):
        self.send_header("Cache-Control", "no-store")
        super().end_headers()

    def send_json(self, status, value):
        data = json.dumps(value, ensure_ascii=False).encode("utf-8")
        self.send_response(status)
        self.send_header("Content-Type", "application/json; charset=utf-8")
        self.send_header("Content-Length", str(len(data)))
        self.end_headers()
        self.wfile.write(data)

    def do_GET(self):
        if self.path.rstrip("/") == "/api/state":
            with connect_db() as db:
                row = db.execute("SELECT payload, updated_at FROM app_state WHERE id=1").fetchone()
            self.send_json(200, {"state": json.loads(row["payload"]), "updatedAt": row["updated_at"]} if row else {"state": None})
            return
        return super().do_GET()

    def do_PUT(self):
        if self.path.rstrip("/") != "/api/state":
            self.send_error(404)
            return
        try:
            size = int(self.headers.get("Content-Length", "0"))
            if size <= 0 or size > 30_000_000:
                self.send_json(413, {"error": "Payload rỗng hoặc vượt quá 30 MB"})
                return
            state = json.loads(self.rfile.read(size))
            required = ("tournaments", "teams", "athletes", "matches", "events", "users")
            if not isinstance(state, dict) or any(not isinstance(state.get(k), list) for k in required):
                self.send_json(400, {"error": "Dữ liệu giải đấu không hợp lệ"})
                return
            payload = json.dumps(state, ensure_ascii=False, separators=(",", ":"))
            now = datetime.now(timezone.utc).isoformat()
            with connect_db() as db:
                db.execute("INSERT INTO app_state(id,payload,updated_at) VALUES(1,?,?) "
                           "ON CONFLICT(id) DO UPDATE SET payload=excluded.payload,updated_at=excluded.updated_at", (payload, now))
                db.execute("DELETE FROM accounts")
                db.executemany("INSERT INTO accounts(id,username,password,display_name,role,athlete_id,updated_at) VALUES(?,?,?,?,?,?,?)",
                    [(str(u.get("id", "")), str(u.get("username", "")), str(u.get("password", "")), str(u.get("name", "")),
                      str(u.get("role", "view")), u.get("athlete"), now)
                     for u in state["users"] if u.get("id") and u.get("username")])
                for table in ("tournaments", "teams", "athletes", "matches", "events", "venues", "refs"):
                    db.execute(f"DELETE FROM {table}")
                    records = state.get(table, [])
                    rows = []
                    for item in records:
                        columns = [str(item.get("id", ""))]
                        if table in ("teams", "matches", "events"):
                            columns.append(str(item.get("tid", "")))
                        elif table == "athletes":
                            columns.append(str(item.get("team", "")))
                        elif table in ("tournaments", "venues", "refs"):
                            columns.append(str(item.get("sport", "")))
                        if table == "events":
                            columns.append(str(item.get("m", "")))
                        columns.append(json.dumps(item, ensure_ascii=False, separators=(",", ":")))
                        rows.append(tuple(columns))
                    db.executemany(f"INSERT INTO {table} VALUES({','.join('?' for _ in range(len(rows[0])) if rows)})", rows) if rows else None
            self.send_json(200, {"ok": True, "updatedAt": now})
        except (ValueError, TypeError, sqlite3.Error) as exc:
            self.send_json(400, {"error": str(exc)})


if __name__ == "__main__":
    with connect_db():
        pass
    print(f"Tournament app: http://127.0.0.1:8000/giai-dau.html\nSQLite: {DB_PATH}")
    ThreadingHTTPServer(("127.0.0.1", 8000), Handler).serve_forever()
