#!/usr/bin/env python3
"""Stub quill-signal-bridge: serves the line-JSON protocol on a unix socket
with seeded demo conversations so the signal-chat UI can be developed and
rehearsed without a linked account. `receive` connections get a scripted
incoming message every RECV_EVERY seconds. Send is echoed into the store.
"""
import json, os, socket, threading, time, sys

SOCK = sys.argv[1] if len(sys.argv) > 1 else "/tmp/quill-signal.sock"
RECV_EVERY = float(os.environ.get("STUB_RECV_EVERY", "20"))

now = lambda: int(time.time() * 1000)
T0 = now() - 9_000_000

ALICE = "0aa11a11-1111-4111-a111-111111111111"
BOB = "0bb22b22-2222-4222-b222-222222222222"
DANA = "0dd44d44-4444-4444-d444-444444444444"
TEAM = "0cc33c33-3333-4333-c333-333333333333"

LOCK = threading.Lock()
STORE = {
    "conversations": [
        {"type": "contact", "uuid": ALICE, "name": "Alice Moreau"},
        {"type": "group", "uuid": TEAM, "name": "QuillOS Core"},
        {"type": "contact", "uuid": BOB, "name": "Bob Tanaka"},
        {"type": "contact", "uuid": DANA, "name": "Dana Reyes"},
    ],
    "messages": {
        ALICE: [
            {"body": "did you really get Signal running on the Quill board??", "timestamp": T0, "sender": ALICE, "from_self": False},
            {"body": "yep. native ARM64 Linux, real libsignal underneath", "timestamp": T0 + 60_000, "sender": "self", "from_self": True},
            {"body": "no Electron??", "timestamp": T0 + 95_000, "sender": ALICE, "from_self": False},
            {"body": "no Electron. it's a 12MB binary, boots in under a second", "timestamp": T0 + 140_000, "sender": "self", "from_self": True},
            {"body": "ok that's actually wild. send proof", "timestamp": T0 + 200_000, "sender": ALICE, "from_self": False},
        ],
        TEAM: [
            {"body": "standup in 10", "timestamp": T0 + 1_000_000, "sender": BOB, "from_self": False},
            {"body": "shipping the chat window today", "timestamp": T0 + 1_060_000, "sender": "self", "from_self": True},
            {"body": "screenshots or it didn't happen", "timestamp": T0 + 1_100_000, "sender": DANA, "from_self": False},
        ],
        BOB: [
            {"body": "battery numbers from the e-ink build look great", "timestamp": T0 + 2_000_000, "sender": BOB, "from_self": False},
            {"body": "9 days standby. messaging stack barely registers", "timestamp": T0 + 2_080_000, "sender": "self", "from_self": True},
        ],
        DANA: [
            {"body": "call me when the demo video is ready", "timestamp": T0 + 3_000_000, "sender": DANA, "from_self": False},
        ],
    },
}
NAMES = {ALICE: "Alice Moreau", BOB: "Bob Tanaka", DANA: "Dana Reyes"}

INCOMING = [
    (ALICE, ALICE, "just saw the window. this is the real deal 🔥"),
    (TEAM, DANA, "demo day is going to be fun"),
    (ALICE, ALICE, "Brian is going to love this"),
]

def ok(cmd, msg="ok", data=None):
    r = {"ok": True, "cmd": cmd, "msg": msg}
    if data is not None:
        r["data"] = data
    return r

def handle(req):
    cmd = req.get("cmd")
    if cmd == "ping":
        return ok("ping", "pong")
    if cmd == "status":
        return ok("status", "registered", {"registered": True})
    if cmd == "whoami":
        return ok("whoami", "ok", {"registered": True, "number": "+13059511381"})
    if cmd == "list-conversations":
        with LOCK:
            return ok(cmd, "ok", {"conversations": list(STORE["conversations"])})
    if cmd == "list-messages":
        t = req.get("thread", "")
        with LOCK:
            msgs = [dict(m, attachment_path=m.get("attachment_path"),
                         attachment_kind=m.get("attachment_kind"))
                    for m in STORE["messages"].get(t, [])]
        return ok(cmd, "ok", {"messages": msgs})
    if cmd == "send":
        t = req.get("thread", "")
        m = {"body": req.get("body", ""), "timestamp": req.get("timestamp", now()),
             "sender": "self", "from_self": True}
        with LOCK:
            STORE["messages"].setdefault(t, []).append(m)
        return ok("send", "sent", {"timestamp": m["timestamp"]})
    return {"ok": False, "cmd": cmd or "?", "msg": "unknown cmd"}

def serve_receive(conn):
    i = 0
    while True:
        time.sleep(RECV_EVERY)
        thread, sender, body = INCOMING[i % len(INCOMING)]
        i += 1
        m = {"body": body, "timestamp": now(), "sender": sender, "from_self": False}
        with LOCK:
            STORE["messages"].setdefault(thread, []).append(m)
        ev = {"event": "message", "thread": thread, "sender": sender,
              "sender_name": NAMES.get(sender), "body": body,
              "timestamp": m["timestamp"], "from_self": False,
              "attachment_kind": None}
        try:
            conn.sendall((json.dumps(ev) + "\n").encode())
        except OSError:
            return

def client_thread(conn):
    f = conn.makefile("r")
    try:
        for line in f:
            line = line.strip()
            if not line:
                continue
            req = json.loads(line)
            if req.get("cmd") == "receive":
                serve_receive(conn)
                return
            conn.sendall((json.dumps(handle(req)) + "\n").encode())
    except (OSError, json.JSONDecodeError):
        pass
    finally:
        conn.close()

def main():
    try:
        os.unlink(SOCK)
    except FileNotFoundError:
        pass
    s = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
    s.bind(SOCK)
    s.listen(8)
    print(f"stub bridge on {SOCK}", flush=True)
    while True:
        conn, _ = s.accept()
        threading.Thread(target=client_thread, args=(conn,), daemon=True).start()

main()
