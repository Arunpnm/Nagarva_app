"""Static server for the Flutter web build with SPA fallback.

usePathUrlStrategy() means deep links like /orders must serve index.html,
which python's plain http.server does not do.

Usage: python .claude/spa_server.py <port> <root>
"""
import http.server
import os
import sys

port = int(sys.argv[1]) if len(sys.argv) > 1 else 5001
root = os.path.abspath(sys.argv[2] if len(sys.argv) > 2 else "build/web")


class SpaHandler(http.server.SimpleHTTPRequestHandler):
    def __init__(self, *args, **kwargs):
        super().__init__(*args, directory=root, **kwargs)

    def send_head(self):
        path = self.translate_path(self.path)
        if not os.path.exists(path):
            self.path = "/index.html"
        return super().send_head()


if __name__ == "__main__":
    print(f"Serving {root} on http://localhost:{port}", flush=True)
    http.server.ThreadingHTTPServer(("127.0.0.1", port), SpaHandler).serve_forever()
