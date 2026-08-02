#!/usr/bin/env python3
"""Sirve build/web sin cache (para desarrollo Flutter web).

Uso:
    python scripts/serve_web_nocache.py [puerto]

Por defecto usa el puerto 8080 y el directorio build/web del proyecto.
Agrega cabeceras Cache-Control: no-store para evitar estaleces al recargar.
"""
import http.server
import os
import sys

PORT = int(sys.argv[1]) if len(sys.argv) > 1 else 8080
BASE_DIR = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "build", "web")
BASE_DIR = os.path.normpath(BASE_DIR)


class NoCacheHandler(http.server.SimpleHTTPRequestHandler):
    def __init__(self, *args, **kwargs):
        super().__init__(*args, directory=BASE_DIR, **kwargs)

    def end_headers(self):
        self.send_header("Cache-Control", "no-store, no-cache, must-revalidate, max-age=0")
        self.send_header("Pragma", "no-cache")
        self.send_header("Expires", "0")
        super().end_headers()

    def log_message(self, fmt, *args):
        sys.stderr.write("%s - %s\n" % (self.address_string(), fmt % args))


if __name__ == "__main__":
    print(f"Sirviendo {BASE_DIR} en http://localhost:{PORT} (sin cache)")
    http.server.ThreadingHTTPServer(("0.0.0.0", PORT), NoCacheHandler).serve_forever()
