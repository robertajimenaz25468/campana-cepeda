"""
Campana Cepeda — Servidor básico de desarrollo
- Headers de seguridad básicos
- Sin encriptación, sin tokens, sin bloqueos
"""

import http.server
import os
from urllib.parse import urlparse

PORT = 8765
DIRECTORY = os.path.dirname(os.path.abspath(__file__))


class SimpleHandler(http.server.SimpleHTTPRequestHandler):
    def __init__(self, *args, **kwargs):
        super().__init__(*args, directory=DIRECTORY, **kwargs)

    def end_headers(self):
        self.send_header("Server", "nginx")
        self.send_header("X-Content-Type-Options", "nosniff")
        self.send_header("X-Frame-Options", "DENY")
        self.send_header("Cache-Control", "public, max-age=3600")
        super().end_headers()

    def log_message(self, format, *args):
        pass  # silencioso


if __name__ == "__main__":
    server = http.server.HTTPServer(("127.0.0.1", PORT), SimpleHandler)
    print(f"Servidor en http://127.0.0.1:{PORT}")
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        print("\nDetenido.")
        server.server_close()
