#!/usr/bin/env python3
# PROTOTYPE - NOT FOR PRODUCTION
# Servidor local para probar el build web ANTES de subirlo.
#
# `python -m http.server` NO manda las cabeceras de cross-origin isolation, asi
# que Godot se queda sin SharedArrayBuffer y arranca en pantalla negra. El bug
# se ve identico a "el build esta roto" y no lo esta: es el servidor.
#
# Uso:  python serve_web.py            (sirve build/web en el puerto 8000)
#       python serve_web.py 8080
import http.server
import os
import socketserver
import sys

PUERTO = int(sys.argv[1]) if len(sys.argv) > 1 else 8000
RAIZ = os.path.join(os.path.dirname(os.path.abspath(__file__)), "build", "web")


class Handler(http.server.SimpleHTTPRequestHandler):
    def __init__(self, *args, **kwargs):
        super().__init__(*args, directory=RAIZ, **kwargs)

    def end_headers(self):
        # Las dos que Godot necesita. Son las MISMAS que pone vercel.json.
        self.send_header("Cross-Origin-Opener-Policy", "same-origin")
        self.send_header("Cross-Origin-Embedder-Policy", "require-corp")
        super().end_headers()


if not os.path.isdir(RAIZ):
    print("No existe %s — corre build_web.sh primero." % RAIZ)
    raise SystemExit(1)

socketserver.TCPServer.allow_reuse_address = True
with socketserver.TCPServer(("", PUERTO), Handler) as httpd:
    print("Sirviendo %s en http://localhost:%d" % (RAIZ, PUERTO))
    print("En la consola del navegador, crossOriginIsolated debe dar true.")
    httpd.serve_forever()
