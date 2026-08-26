"""Характеризующий тест безопасности viz-сервера (serve.py).

Мутирующие POST-эндпоинты (`/api/node/delete` и пр.) необратимо трогают
файлы знаний. Фиксируем две защиты, добавленные после аудита скрытых рисков:
  1. bind на 127.0.0.1 (не 0.0.0.0) — нет доступа из локальной сети;
  2. Origin-проверка на POST — cross-origin браузерный CSRF отклоняется (403).

Тесты не трогают БД и файлы: проверяют только гейт Origin и роутинг
(неизвестный путь → 404), реальная мутация узла не вызывается.
"""

from __future__ import annotations

import http.client
import sys
import threading
from http.server import ThreadingHTTPServer
from pathlib import Path

SERVE_DIR = Path(__file__).resolve().parents[1] / "visualization"
sys.path.insert(0, str(SERVE_DIR))

import serve  # noqa: E402


def _start_server():
    httpd = ThreadingHTTPServer(("127.0.0.1", 0), serve.Handler)
    port = httpd.server_address[1]
    threading.Thread(target=httpd.serve_forever, daemon=True).start()
    return httpd, port


def _post(port, path, headers=None, body=b"{}"):
    conn = http.client.HTTPConnection("127.0.0.1", port, timeout=5)
    conn.request("POST", path, body=body, headers=headers or {})
    resp = conn.getresponse()
    status = resp.status
    resp.read()
    conn.close()
    return status


def test_cross_origin_post_rejected():
    """Чужой Origin → 403 ДО роутинга, мутация не достигается (CSRF closed)."""
    httpd, port = _start_server()
    try:
        status = _post(
            port,
            "/api/node/delete",
            headers={"Origin": "http://evil.example", "Content-Type": "text/plain"},
            body=b'{"id": 1}',
        )
        assert status == 403
    finally:
        httpd.shutdown()


def test_same_origin_post_passes_gate():
    """Origin == Host → гейт пропускает; неизвестный путь → 404 (без мутации)."""
    httpd, port = _start_server()
    try:
        status = _post(
            port,
            "/api/node/bogus",
            headers={"Origin": f"http://127.0.0.1:{port}"},
        )
        assert status == 404
    finally:
        httpd.shutdown()


def test_no_origin_post_passes_gate():
    """Без Origin (не браузер) → гейт пропускает; неизвестный путь → 404."""
    httpd, port = _start_server()
    try:
        status = _post(port, "/api/node/bogus")
        assert status == 404
    finally:
        httpd.shutdown()


def test_server_binds_loopback_only():
    """Регрессия-страж: bind остаётся loopback, не 0.0.0.0."""
    src = (SERVE_DIR / "serve.py").read_text(encoding="utf-8")
    assert 'ThreadingHTTPServer(("127.0.0.1", port)' in src
    assert 'ThreadingHTTPServer(("", port)' not in src
