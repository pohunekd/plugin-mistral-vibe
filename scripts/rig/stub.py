"""Loopback OpenAI-style chat-completions stub for the Vibe capture rig.

Run: python3 -I stub.py --port N --log FILE [--slow-chunks N --slow-interval S]

The scenario is chosen by a marker in the LAST user message:
  [[PLAIN]]  short answer
  [[SLOW]]   streamed answer, one chunk per --slow-interval seconds
  [[THINK]]  reasoning deltas for a while, then an answer
  [[BASH]]   bash tool call (argument: command `echo hello`)
  [[BASHSLOW]] bash tool call whose command sleeps (running-command label)
  [[ASK]]    ask_user_question tool call (2 options, title `Which color`)
  [[ASK3]]   ask_user_question with 3 options, title `Pick the fruit`
  [[ASK4]]   ask_user_question with 4 options, title `Pick the fruit`
  [[RETRY]]  HTTP 500 for the first two attempts, then success
  [[LONG]]   long answer, large reported usage (scroll and compaction)
A request whose last message has role "tool" gets a short closing answer.
Anything else gets the plain answer. Only the request line and a body
summary are logged, never a header.
"""
from __future__ import annotations

import argparse
import json
import threading
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

ARGS = None
LOCK = threading.Lock()
RETRY_SEEN = {}


def log(line: str) -> None:
    with LOCK:
        with open(ARGS.log, "a", encoding="utf-8") as fh:
            fh.write(f"{time.strftime('%H:%M:%S')} {line}\n")


def last_user_text(messages):
    for m in reversed(messages):
        if m.get("role") == "user":
            c = m.get("content")
            if isinstance(c, list):
                return " ".join(p.get("text", "") for p in c if isinstance(p, dict))
            return c or ""
    return ""


def chunk(delta, finish=None, usage=None):
    body = {
        "id": "chatcmpl-stub",
        "object": "chat.completion.chunk",
        "created": 1,
        "model": "stub-model",
        "choices": [{"index": 0, "delta": delta, "finish_reason": finish}],
    }
    if usage is not None:
        body["usage"] = usage
        body["choices"] = [] if finish is None else body["choices"]
    return body


def tool_chunks(name, arguments, call_id):
    return [
        chunk({"role": "assistant", "tool_calls": [{"index": 0, "id": call_id, "type": "function",
                                                     "function": {"name": name, "arguments": arguments}}]}),
        chunk({}, "tool_calls"),
    ]


def text_chunks(text):
    return [chunk({"role": "assistant", "content": text}), chunk({}, "stop")]


class Handler(BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"

    def log_message(self, fmt, *a):  # silence default stderr logging
        return

    def _send_json(self, code, obj):
        raw = json.dumps(obj).encode()
        self.send_response(code)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(raw)))
        self.end_headers()
        self.wfile.write(raw)

    def do_GET(self):
        log(f"GET {self.path}")
        if self.path.rstrip("/").endswith("/models"):
            self._send_json(200, {"object": "list", "data": [{"id": "stub-model", "object": "model"}]})
        else:
            self._send_json(404, {"error": {"message": "not found"}})

    def do_POST(self):
        n = int(self.headers.get("Content-Length") or 0)
        raw = self.rfile.read(n) if n else b""
        try:
            req = json.loads(raw or b"{}")
        except ValueError:
            req = {}
        messages = req.get("messages", [])
        stream = bool(req.get("stream"))
        text = last_user_text(messages)
        last_role = messages[-1].get("role") if messages else None
        marker = next((m for m in ("RETRY", "SLOWBASH", "BASHSLOW", "BASH", "ASK", "ASK3", "ASK4", "THINK", "SLOW", "LONG", "PLAIN")
                       if f"[[{m}]]" in text), None)
        log(f"POST {self.path} stream={stream} msgs={len(messages)} last_role={last_role} marker={marker} bytes={n} text={text[:60]!r}")
        if not self.path.rstrip("/").endswith("/chat/completions"):
            self._send_json(404, {"error": {"message": "not found"}})
            return
        if last_role == "tool":
            chunks, delay, usage = text_chunks("Done."), 0.0, None
        elif marker == "RETRY":
            with LOCK:
                seen = RETRY_SEEN.get(text, 0)
                RETRY_SEEN[text] = seen + 1
            if seen < 5:
                log(f"RETRY attempt {seen + 1} -> 500")
                self._send_json(500, {"error": {"message": "stub server error"}})
                return
            chunks, delay, usage = text_chunks("Recovered after retry."), 0.0, None
        elif marker == "BASH":
            chunks, delay, usage = tool_chunks("bash", json.dumps({"command": "touch approved.txt"}), "call_bash"), 0.0, None
        elif marker in ("BASHSLOW", "SLOWBASH"):
            chunks, delay, usage = tool_chunks("bash", json.dumps({"command": "sleep 25"}), "call_bashslow"), 0.0, None
        elif marker == "ASK":
            q = {"questions": [{"question": "Which color should the stub use?", "header": "Color",
                                "options": [{"label": "Red", "description": "warm"},
                                            {"label": "Blue", "description": "cool"}]}]}
            chunks, delay, usage = tool_chunks("ask_user_question", json.dumps(q), "call_ask"), 0.0, None
        elif marker in ("ASK3", "ASK4"):
            labels = ["Apple", "Pear", "Plum", "Fig"][: 3 if marker == "ASK3" else 4]
            q = {"questions": [{"question": "Pick the fruit the stub should name?", "header": "Fruit",
                                "options": [{"label": lb, "description": "fruit option"} for lb in labels]}]}
            chunks, delay, usage = tool_chunks("ask_user_question", json.dumps(q), "call_ask"), 0.0, None
        elif marker == "SLOW":
            chunks = [chunk({"role": "assistant", "content": ""})]
            chunks += [chunk({"content": f"slow word {i} "}) for i in range(ARGS.slow_chunks)]
            chunks.append(chunk({}, "stop"))
            delay, usage = ARGS.slow_interval, None
        elif marker == "THINK":
            chunks = [chunk({"role": "assistant", "reasoning_content": f"thinking step {i} "}) for i in range(ARGS.slow_chunks)]
            chunks += [chunk({"content": "Thought it through."}), chunk({}, "stop")]
            delay, usage = ARGS.slow_interval, None
        elif marker == "LONG":
            body = "\n".join(f"Line {i}: the quick brown fox jumps over the lazy dog, entry {i}." for i in range(1, 161))
            chunks, delay = text_chunks(body), 0.0
            usage = {"prompt_tokens": ARGS.long_prompt_tokens, "completion_tokens": 100, "total_tokens": ARGS.long_prompt_tokens + 100}
        elif marker is None:
            # No scenario marker: a compaction summary request. Streams slowly so the in-progress screen is observable.
            chunks = [chunk({"role": "assistant", "content": ""})]
            chunks += [chunk({"content": f"summary part {i} "}) for i in range(ARGS.slow_chunks)]
            chunks.append(chunk({}, "stop"))
            delay, usage = ARGS.slow_interval, None
        else:
            chunks, delay, usage = text_chunks("Plain stub answer."), 0.0, None
        if not stream:
            content = "".join(c["choices"][0]["delta"].get("content", "") for c in chunks if c["choices"])
            calls = [tc for c in chunks if c["choices"] for tc in c["choices"][0]["delta"].get("tool_calls", [])]
            msg = {"role": "assistant", "content": content or None}
            if calls:
                msg["tool_calls"] = [{k: v for k, v in tc.items() if k != "index"} for tc in calls]
            fin = next((c["choices"][0]["finish_reason"] for c in chunks if c["choices"] and c["choices"][0]["finish_reason"]), "stop")
            self._send_json(200, {"id": "chatcmpl-stub", "object": "chat.completion", "created": 1, "model": "stub-model",
                                  "choices": [{"index": 0, "message": msg, "finish_reason": fin}],
                                  "usage": usage or {"prompt_tokens": 10, "completion_tokens": 5, "total_tokens": 15}})
            return
        self.send_response(200)
        self.send_header("Content-Type", "text/event-stream")
        self.send_header("Cache-Control", "no-cache")
        self.send_header("Connection", "close")
        self.end_headers()
        try:
            for c in chunks:
                self.wfile.write(b"data: " + json.dumps(c).encode() + b"\n\n")
                self.wfile.flush()
                if delay:
                    time.sleep(delay)
            u = usage or {"prompt_tokens": 10, "completion_tokens": 5, "total_tokens": 15}
            self.wfile.write(b"data: " + json.dumps({"id": "chatcmpl-stub", "object": "chat.completion.chunk", "created": 1,
                                                     "model": "stub-model", "choices": [], "usage": u}).encode() + b"\n\n")
            self.wfile.write(b"data: [DONE]\n\n")
            self.wfile.flush()
        except (BrokenPipeError, ConnectionResetError):
            log("client closed stream")
        self.close_connection = True


def main():
    global ARGS
    ap = argparse.ArgumentParser()
    ap.add_argument("--port", type=int, required=True)
    ap.add_argument("--log", required=True)
    ap.add_argument("--slow-chunks", type=int, default=40)
    ap.add_argument("--slow-interval", type=float, default=1.5)
    ap.add_argument("--long-prompt-tokens", type=int, default=30100)
    ARGS = ap.parse_args()
    srv = ThreadingHTTPServer(("127.0.0.1", ARGS.port), Handler)
    srv.daemon_threads = True
    log(f"stub listening 127.0.0.1:{ARGS.port}")
    srv.serve_forever()


if __name__ == "__main__":
    main()
