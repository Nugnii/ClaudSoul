"""Общая рамка mcp-тестов: журнал кросс-контурных открытий — во временном каталоге (D1006).

Писатель журнала (`ingest/discovery.py`) переписывает его снимком на каждом прогоне, пустым тоже.
Тест, зовущий discover() без подмены пути (`test_discovery.py`, интеграция в `test_cli.py`), переписал
бы живой журнал своей фикстурой. Подменяются и окружение (подпроцессы CLI, перезагрузка модуля), и
путь, уже вычисленный при импорте.
"""
import pytest


@pytest.fixture(autouse=True)
def _isolated_cross_contour_log(tmp_path, monkeypatch):
    log = tmp_path / "cross-contour-discoveries.jsonl"
    monkeypatch.setenv("CLAUDSOUL_CROSS_CONTOUR_LOG", str(log))
    try:
        import ingest.discovery as discovery
    except ImportError:
        return
    monkeypatch.setattr(discovery, "CROSS_CONTOUR_LOG_PATH", log)
