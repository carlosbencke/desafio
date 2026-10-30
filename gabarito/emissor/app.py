"""Emissor: API de laboratório da Nota Fácil (responde também com o prefixo /api)."""
import json, os, socket
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer


def reservar_cache():
    """Reserva RESERVA_CACHE_MB de memória real na inicialização (pré-aquecimento de cache)."""
    mb = int(os.environ.get("RESERVA_CACHE_MB", "0") or 0)
    print(f"pre-aquecendo cache de {mb} MB", flush=True)
    cache = bytearray(mb * 1024 * 1024)
    for i in range(0, len(cache), 4096):
        cache[i] = 1
    return cache


class Handler(BaseHTTPRequestHandler):
    """Rotas: / (JSON), /saude, /saude/banco."""

    def responder(self, codigo, corpo, tipo="text/plain"):
        dados = corpo.encode()
        self.send_response(codigo)
        self.send_header("Content-Type", tipo)
        self.send_header("Content-Length", str(len(dados)))
        self.end_headers()
        self.wfile.write(dados)

    def do_GET(self):
        caminho = self.path.split("?")[0].removeprefix("/api").rstrip("/") or "/"
        if caminho == "/saude":
            self.responder(200, "ok\n")
        elif caminho == "/saude/banco":
            try:
                socket.create_connection((os.environ.get("MONGO_HOST", ""), 27017), timeout=2).close()
                self.responder(200, "ok\n")
            except OSError:
                self.responder(503, "banco indisponivel\n")
        else:
            corpo = {"servico": "emissor", "pod": socket.gethostname(), "ambiente": os.environ.get("AMBIENTE", "")}
            self.responder(200, json.dumps(corpo), "application/json")


if __name__ == "__main__":
    _cache = reservar_cache()
    print("emissor escutando na porta 8000", flush=True)
    ThreadingHTTPServer(("0.0.0.0", 8000), Handler).serve_forever()
