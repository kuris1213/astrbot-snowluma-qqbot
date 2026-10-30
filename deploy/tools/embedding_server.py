"""本地 OpenAI 兼容 embedding 服务（供 AstrBot 知识库使用）。

模型：BAAI/bge-small-zh-v1.5（512 维，CLS pooling + L2 归一化）
接口：
  POST /v1/embeddings   {"input": "文本" | ["文本1", ...], "model": "..."}
  GET  /v1/models
  GET  /health

启动（一般由 deploy\\start-embedding.ps1 调用）：
  .venv-embedding\\Scripts\\python.exe embedding_server.py --port 8010 --preload

模型目录通过环境变量 EMBEDDING_MODEL_DIR 指定；未指定时回退到仓库的
models\\bge-small-zh-v1.5（相对本文件向上两级）。
"""

from __future__ import annotations

import argparse
import json
import logging
import os
import sys
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

_HERE = os.path.dirname(os.path.abspath(__file__))
_DEFAULT_MODEL_DIR = os.path.normpath(
    os.path.join(_HERE, "..", "..", "models", "bge-small-zh-v1.5")
)

MODEL_DIR = os.environ.get("EMBEDDING_MODEL_DIR", _DEFAULT_MODEL_DIR)
MODEL_NAME = os.environ.get("EMBEDDING_MODEL_NAME", "bge-small-zh-v1.5")
MAX_LENGTH = 512
BATCH = 32

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s %(levelname)s %(message)s",
    stream=sys.stdout,
)
log = logging.getLogger("embedding")

_tokenizer = None
_model = None
_torch = None


def load_model() -> None:
    global _tokenizer, _model, _torch
    if _model is not None:
        return
    import torch
    from transformers import AutoModel, AutoTokenizer

    t0 = time.time()
    _torch = torch
    _tokenizer = AutoTokenizer.from_pretrained(MODEL_DIR)
    _model = AutoModel.from_pretrained(MODEL_DIR).eval()
    torch.set_num_threads(max(1, min(8, os.cpu_count() or 4)))
    log.info("model loaded in %.1fs from %s", time.time() - t0, MODEL_DIR)


def embed(texts: list[str]) -> list[list[float]]:
    load_model()
    vectors: list[list[float]] = []
    with _torch.no_grad():
        for start in range(0, len(texts), BATCH):
            chunk = texts[start : start + BATCH]
            batch = _tokenizer(
                chunk,
                padding=True,
                truncation=True,
                max_length=MAX_LENGTH,
                return_tensors="pt",
            )
            out = _model(**batch)
            cls = out.last_hidden_state[:, 0]
            normed = _torch.nn.functional.normalize(cls, p=2, dim=1)
            vectors.extend(normed.tolist())
    return vectors


class Handler(BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"
    server_version = "LocalEmbedding/1.0"

    def log_message(self, fmt: str, *args) -> None:  # 静音逐请求日志
        return

    def _send(self, code: int, payload: dict) -> None:
        body = json.dumps(payload, ensure_ascii=False).encode("utf-8")
        self.send_response(code)
        self.send_header("Content-Type", "application/json; charset=utf-8")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def do_GET(self) -> None:  # noqa: N802
        if self.path.startswith("/health"):
            self._send(200, {"status": "ok", "model": MODEL_NAME, "ready": _model is not None})
        elif self.path.startswith("/v1/models"):
            self._send(
                200,
                {
                    "object": "list",
                    "data": [{"id": MODEL_NAME, "object": "model", "owned_by": "local"}],
                },
            )
        else:
            self._send(404, {"error": {"message": "not found"}})

    def do_POST(self) -> None:  # noqa: N802
        if not (self.path.startswith("/v1/embeddings") or self.path.startswith("/embeddings")):
            self._send(404, {"error": {"message": "not found"}})
            return
        try:
            length = int(self.headers.get("Content-Length") or 0)
            raw = self.rfile.read(length) if length else b"{}"
            payload = json.loads(raw.decode("utf-8"))
        except Exception as exc:  # noqa: BLE001
            self._send(400, {"error": {"message": f"bad json: {exc}"}})
            return

        value = payload.get("input")
        if isinstance(value, str):
            texts = [value]
        elif isinstance(value, list):
            texts = [str(item) for item in value]
        else:
            self._send(400, {"error": {"message": "input must be string or string[]"}})
            return
        texts = [text if text.strip() else " " for text in texts]

        try:
            t0 = time.time()
            vectors = embed(texts)
            elapsed = time.time() - t0
        except Exception as exc:  # noqa: BLE001
            log.exception("embedding failed")
            self._send(500, {"error": {"message": str(exc)}})
            return

        total_tokens = sum(max(1, len(t)) for t in texts)
        self._send(
            200,
            {
                "object": "list",
                "data": [
                    {"object": "embedding", "index": i, "embedding": vec}
                    for i, vec in enumerate(vectors)
                ],
                "model": payload.get("model") or MODEL_NAME,
                "usage": {"prompt_tokens": total_tokens, "total_tokens": total_tokens},
            },
        )
        log.info("embedded %d text(s) in %.2fs", len(texts), elapsed)


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--host", default="127.0.0.1")
    parser.add_argument("--port", type=int, default=8010)
    parser.add_argument("--preload", action="store_true", help="启动时预加载模型")
    args = parser.parse_args()

    if args.preload:
        load_model()

    server = ThreadingHTTPServer((args.host, args.port), Handler)
    log.info("listening on http://%s:%d (model=%s)", args.host, args.port, MODEL_NAME)
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        log.info("bye")
    finally:
        server.server_close()


if __name__ == "__main__":
    main()
