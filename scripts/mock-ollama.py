#!/usr/bin/env python3
from __future__ import annotations

import argparse
import json
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path


class MockOllamaHandler(BaseHTTPRequestHandler):
    server: "MockOllamaServer"

    def log_message(self, format: str, *args: object) -> None:
        return

    def do_GET(self) -> None:
        self.server.append_log({
            "method": "GET",
            "path": self.path,
        })
        if self.path == "/api/version":
            self.write_json({"version": "0.6.0"})
        elif self.path == "/api/tags":
            self.write_json({
                "models": [{
                    "name": self.server.model,
                    "details": {"families": ["clip"]},
                }],
            })
        else:
            self.send_error(404)

    def do_POST(self) -> None:
        if self.path != "/api/chat":
            self.send_error(404)
            return

        body = self.rfile.read(int(self.headers.get("Content-Length", "0") or "0"))
        request = json.loads(body.decode("utf-8") or "{}")
        self.server.append_log({
            "method": "POST",
            "path": self.path,
            "request": request,
        })
        self.write_ndjson([
            {"message": {"role": "assistant", "content": self.server.reply_prefix}, "done": False},
            {"message": {"role": "assistant", "content": self.server.reply_suffix}, "done": False},
            {"done": True},
        ])

    def write_json(self, payload: object) -> None:
        data = json.dumps(payload).encode("utf-8")
        self.send_response(200)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(data)))
        self.end_headers()
        self.wfile.write(data)

    def write_ndjson(self, payloads: list[object]) -> None:
        data = "".join(json.dumps(payload) + "\n" for payload in payloads).encode("utf-8")
        self.send_response(200)
        self.send_header("Content-Type", "application/x-ndjson")
        self.send_header("Content-Length", str(len(data)))
        self.end_headers()
        self.wfile.write(data)


class MockOllamaServer(ThreadingHTTPServer):
    def __init__(
        self,
        address: tuple[str, int],
        log_path: Path,
        model: str,
        reply: str,
    ) -> None:
        super().__init__(address, MockOllamaHandler)
        self.log_path = log_path
        self.model = model
        midpoint = max(1, len(reply) // 2)
        self.reply_prefix = reply[:midpoint]
        self.reply_suffix = reply[midpoint:]
        self.log_path.parent.mkdir(parents=True, exist_ok=True)
        self.log_path.write_text("", encoding="utf-8")

    def append_log(self, payload: object) -> None:
        with self.log_path.open("a", encoding="utf-8") as stream:
            stream.write(json.dumps(payload, sort_keys=True))
            stream.write("\n")


def main() -> int:
    parser = argparse.ArgumentParser(description="Run a deterministic Ollama-compatible test server.")
    parser.add_argument("--host", default="127.0.0.1")
    parser.add_argument("--port", type=int, default=11434)
    parser.add_argument("--log", type=Path, required=True)
    parser.add_argument("--model", default="llava:latest")
    parser.add_argument("--reply", default="Linux composer reply")
    args = parser.parse_args()

    server = MockOllamaServer((args.host, args.port), args.log, args.model, args.reply)
    server.serve_forever()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
