"""Local API failure injection; no real API key or internet request required."""
import json
import subprocess
import sys
import threading
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path

counts = {}
class Handler(BaseHTTPRequestHandler):
    def log_message(self, *args):
        pass

    def do_POST(self):
        request = json.loads(self.rfile.read(int(self.headers.get("Content-Length", 0))))
        counts[self.path] = counts.get(self.path, 0) + 1
        if request.get("stream"):
            if self.path == "/stream-auth" or self.path == "/stream-retry" and counts[self.path] == 1:
                raw = json.dumps({"error": {"message": "invalid key" if self.path == "/stream-auth" else "temporary outage"}}).encode()
                self.send_response(401 if self.path == "/stream-auth" else 503)
                self.send_header("Content-Length", str(len(raw)))
                self.end_headers()
                self.wfile.write(raw)
                return
            self.send_response(200)
            self.send_header("Content-Type", "text/event-stream")
            self.send_header("Connection", "close")
            self.end_headers()
            self.close_connection = True
            commands = [
                {"op": "ellipse", "x": 50, "y": 50, "rx": 20, "ry": 14},
                {"op": "petal", "x": 50, "y": 50, "l": 22, "w": 7, "a": -90},
                {"op": "path", "p": [[25, 65], [35, 50], [65, 50], [75, 65]]},
            ]
            try:
                for index, command in enumerate(commands):
                    text = json.dumps(command, ensure_ascii=False) + "\n"
                    if index == 2:
                        text += json.dumps({"op": "comment", "text": "曲线轻轻画"}, ensure_ascii=False)
                    event = ("data: " + json.dumps({"choices": [{"delta": {"content": text}}]}, ensure_ascii=False) + "\n\n").encode()
                    for part in [event[:17], event[17:67], event[67:]]:
                        self.wfile.write(part)
                        self.wfile.flush()
                    if self.path == "/stream-cut":
                        return
                    if index == 0 and self.path != "/draw":
                        time.sleep(1.7)
                self.wfile.write(b"data: [DONE]\n\n")
                self.wfile.flush()
            except (BrokenPipeError, ConnectionResetError):
                pass
            return
        status = 200
        body = {"choices": [{"message": {"content": "ok"}}]}
        if self.path == "/slow":
            time.sleep(1.4)
        elif self.path == "/timeout":
            time.sleep(2.2)
        elif self.path == "/auth":
            status, body = 401, {"error": {"message": "invalid key"}}
        elif self.path == "/retry" and counts[self.path] == 1:
            status, body = 503, {"error": {"message": "temporary outage"}}
        elif self.path == "/malformed":
            body = {"choices": "invalid type"}
        elif self.path == "/empty":
            body["choices"][0]["message"]["content"] = " "
        elif self.path == "/draw":
            body["choices"][0]["message"]["content"] = json.dumps({"strokes": [[[10, 10], [90, 90]]], "comment": "测试笔触"})
        raw = json.dumps(body).encode()
        self.send_response(status)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(raw)))
        self.end_headers()
        try:
            self.wfile.write(raw)
        except (BrokenPipeError, ConnectionResetError):
            pass

if __name__ == "__main__":
    server = ThreadingHTTPServer(("127.0.0.1", 0), Handler)
    threading.Thread(target=server.serve_forever, daemon=True).start()
    game = Path(__file__).resolve().parents[1]
    scene = sys.argv[2] if len(sys.argv) > 2 else "PatternLlmTest.tscn"
    result = subprocess.run([sys.argv[1], "--headless", "--path", str(game), "res://tests/" + scene, "--", f"--mock-base-url=http://127.0.0.1:{server.server_port}"], timeout=90)
    server.shutdown()
    if scene == "PatternLlmTest.tscn":
        assert counts.get("/auth") == 1, counts
        assert counts.get("/retry") == 2, counts
    else:
        assert counts.get("/stream-auth") == 1, counts
        assert counts.get("/stream-retry") == 2, counts
    print("MOCK HTTP request counts:", counts, flush=True)
    sys.exit(result.returncode)
