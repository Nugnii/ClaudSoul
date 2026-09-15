"""Характеризующий тест: кэш модели эмбеддингов не должен жить в /tmp.

Дефект (D66, отказ инструмента). `TextEmbedding(EMBED_MODEL)` без `cache_dir`
кладёт модель в `tempfile.gettempdir()/fastembed_cache` — на macOS это
`/var/folders/…/T/`, каталог временных файлов, который система вычищает.

22 августа чистка прошла наполовину: `snapshots/` с симлинками осталась,
`blobs/` с самими файлами опустела. Все симлинки стали битыми, и
`search_knowledge` начал падать с `ONNXRuntimeError NO_SUCHFILE`. Отказ молчит
до первого вызова, а вызов делается не каждую сессию — поломка прожила
незамеченной, и обязательный шаг «перед задачей — семантический поиск»
выполнялся grep-ом по именам файлов, то есть ровно тем keyword-поиском, вместо
которого семантический и заводили.

Инвариант: каталог кэша лежит вне каталога временных файлов — модель обязана
пережить их очистку. `FASTEMBED_CACHE_PATH` уважается: сервер запускают
харнессом, а не шеллом, и переменной там может не быть вовсе.
"""

from __future__ import annotations

import sys
import tempfile
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

import indexer  # noqa: E402


class _FakeEmbedding:
    """Подмена fastembed: тест о выборе каталога, не о загрузке модели."""

    def __init__(self, model_name, **kwargs):
        self.model_name = model_name
        self.kwargs = kwargs


def _cache_dir_used(monkeypatch) -> Path:
    monkeypatch.setattr(indexer, "TextEmbedding", _FakeEmbedding)
    monkeypatch.setattr(indexer, "_model", None)
    model = indexer.get_model()
    cache_dir = model.kwargs.get("cache_dir")
    assert cache_dir, "get_model() не передал cache_dir — модель уедет в /tmp по умолчанию"
    return Path(cache_dir)


def _is_relative_to(path: Path, other: Path) -> bool:
    try:
        path.resolve().relative_to(other.resolve())
        return True
    except ValueError:
        return False


def test_cache_dir_outside_tempdir(monkeypatch):
    """Кэш вне каталога временных файлов — иначе чистка ОС ломает поиск."""
    cache_dir = _cache_dir_used(monkeypatch)
    tmp_root = Path(tempfile.gettempdir())
    assert not _is_relative_to(cache_dir, tmp_root), (
        f"кэш модели в каталоге временных файлов ({cache_dir}) — "
        f"он переживёт не каждую перезагрузку, а отказ молчит до первого вызова"
    )


def test_env_override_respected(monkeypatch, tmp_path):
    """Явно заданный FASTEMBED_CACHE_PATH сильнее умолчания."""
    custom = tmp_path / "custom-cache"
    monkeypatch.setenv("FASTEMBED_CACHE_PATH", str(custom))
    assert _cache_dir_used(monkeypatch) == custom


def test_cache_dir_created(monkeypatch, tmp_path):
    """Каталог создаётся до загрузки: fastembed не делает mkdir -p сам."""
    custom = tmp_path / "nested" / "cache"
    monkeypatch.setenv("FASTEMBED_CACHE_PATH", str(custom))
    _cache_dir_used(monkeypatch)
    assert custom.is_dir(), "каталог кэша не создан — первая загрузка упадёт"
