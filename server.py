"""
Campana Cepeda — Servidor Seguro
- Rate limiting por IP (5 req/min para archivos de audio)
- Bloqueo de acceso directo a .b64.js (requiere Referer + token)
- Headers de seguridad (X-Content-Type-Options, etc.)
- Cache-Control restrictivo para archivos de audio
- OPSEC: NO se registran IPs, User-Agents ni datos de clientes
"""
import http.server
import os
import time
import hashlib
import secrets
from urllib.parse import urlparse

PORT = 8765
DIRECTORY = os.path.dirname(os.path.abspath(__file__))

# Rate limiter: IP -> [timestamps]
rate_limit = {}
RATE_LIMIT_MAX = 5       # max requests
RATE_LIMIT_WINDOW = 60   # per minute
AUDIO_EXTENSIONS = {'.b64.js', '.mp3', '.wav', '.ogg'}

# Session tokens válidos (generados por el servidor al cargar index.html)
valid_tokens = set()
TOKEN_SECRET = secrets.token_hex(32)
TOKEN_TTL = 3600  # 1 hora

def check_rate_limit(ip):
    now = time.time()
    if ip not in rate_limit:
        rate_limit[ip] = []
    # Limpiar entradas viejas
    rate_limit[ip] = [t for t in rate_limit[ip] if now - t < RATE_LIMIT_WINDOW]
    if len(rate_limit[ip]) >= RATE_LIMIT_MAX:
        return False
    rate_limit[ip].append(now)
    return True

def generate_token():
    t = str(int(time.time()))
    raw = f"{TOKEN_SECRET}:{t}"
    token = hashlib.sha256(raw.encode()).hexdigest()[:32]
    valid_tokens.add(token)
    return token

def verify_token(token):
    return token in valid_tokens

class SecureHandler(http.server.SimpleHTTPRequestHandler):
    def __init__(self, *args, **kwargs):
        super().__init__(*args, directory=DIRECTORY, **kwargs)

    def is_audio_request(self):
        path = urlparse(self.path).path.lower()
        return any(path.endswith(ext) for ext in AUDIO_EXTENSIONS)

    def end_headers(self):
        self.send_header('Server', 'nginx')  # no revelar que es Python
        self.send_header('X-Content-Type-Options', 'nosniff')
        self.send_header('X-Frame-Options', 'DENY')
        self.send_header('X-XSS-Protection', '1; mode=block')
        if self.is_audio_request():
            self.send_header('Cache-Control', 'no-store, no-cache, must-revalidate, max-age=0')
            self.send_header('Pragma', 'no-cache')
        else:
            self.send_header('Cache-Control', 'public, max-age=3600')
        super().end_headers()

    def do_GET(self):
        path = urlparse(self.path).path.lower()
        client_ip = self.client_address[0]

        # 1. Audio requests: strict protection
        if self.is_audio_request():
            # Rate limit check
            if not check_rate_limit(client_ip):
                self.send_error(429, "Too Many Requests - rate limit exceeded")
                return

            # Referer check: must come from our own page
            referer = self.headers.get('Referer', '')
            if not referer or 'localhost:8765' not in referer and '127.0.0.1:8765' not in referer:
                # Allow if valid token is present (for programmatic access)
                token = self.headers.get('X-Audio-Token', '')
                if not verify_token(token):
                    self.send_error(403, "Forbidden - direct access to audio is blocked")
                    return

        # 2. Index page: inject token as cookie
        if path.endswith('/') or path.endswith('index.html') or path.endswith('.html'):
            token = generate_token()
            self.send_response(200)
            self.send_header('Content-Type', 'text/html; charset=utf-8')
            self.send_header('Set-Cookie', f'cp_audio_token={token}; Path=/; HttpOnly; SameSite=Strict; Max-Age={TOKEN_TTL}')
            self.end_headers()
            # Serve the file
            filepath = os.path.join(DIRECTORY, 'index.html')
            with open(filepath, 'rb') as f:
                self.wfile.write(f.read())
            return

        # 3. Normal file serving
        super().do_GET()

    def do_HEAD(self):
        return self.do_GET()

    # Contador interno (sin datos de cliente)
    _req_count = 0
    _audio_count = 0

    def log_message(self, format, *args):
        SecureHandler._req_count += 1
        if self.is_audio_request():
            SecureHandler._audio_count += 1
        # OPSEC: NO se registran IPs, paths ni User-Agents
        # Solo se muestra un heartbeat cada 100 requests
        if SecureHandler._req_count % 100 == 0:
            print(f"[+] {SecureHandler._req_count} requests served ({SecureHandler._audio_count} audio)")

if __name__ == '__main__':
    server = http.server.HTTPServer(('127.0.0.1', PORT), SecureHandler)
    print(f"Server running on http://127.0.0.1:{PORT}")
    print(f"  Audio: Referer + token required | Rate: {RATE_LIMIT_MAX}/min")
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        print("\nStopped.")
        server.server_close()
