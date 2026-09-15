"""Адверсариальный тест: FASTEMBED_CACHE_PATH со значением из JSON-конфига.

Атака. `cache_dir()` оборачивает значение переменной в `Path()` без
`expanduser()`. Шапка самого `indexer.py` говорит, что сервер запускает
харнесс, а не шелл — значит переменная приходит из JSON (`mcpServers.env`
в `~/.claude.json`, `env` в settings.json), где `~` НЕ раскрывается никем.
Строка `~/.claude/fastembed-cache` остаётся строкой.

Итог: `get_model()` делает `mkdir -p` каталога с именем `~` относительно
рабочего каталога процесса-сервера, кладёт туда 120 МБ модели и повторяет
загрузку при каждой смене cwd. Ровно тот дефект, который чинили (D66):
кэш уезжает в непредсказуемое место вместо постоянного.

Тест не трогает реальный HOME: cwd подменён на tmp_path, TextEmbedding —
заглушка, как в test_model_cache_persistent.py.
"""

from __future__ import annotations

import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

import indexer  # noqa: E402


class _FakeEmbedding:
    def __init__(self, model_name, **kwargs):
        self.model_name = model_name
        self.kwargs = kwargs


def test_tilde_in_env_is_expanded(monkeypatch):
    """`~/…` из JSON-конфига обязан стать домашним каталогом, а не именем папки."""
    monkeypatch.setenv("FASTEMBED_CACHE_PATH", "~/.claude/fastembed-cache")
    resolved = indexer.cache_dir()
    assert "~" not in resolved.parts, (
        f"cache_dir() вернул {resolved!r} — компонент '~' остался буквальным; "
        f"кэш ляжет в каталог с именем '~' рядом с cwd сервера"
    )
    assert resolved == Path.home() / ".claude" / "fastembed-cache"


def test_get_model_does_not_create_literal_tilde_dir(monkeypatch, tmp_path):
    """Проверка последствия: mkdir создаёт мусорный каталог './~' у сервера."""
    monkeypatch.setattr(indexer, "TextEmbedding", _FakeEmbedding)
    monkeypatch.setattr(indexer, "_model", None)
    monkeypatch.setenv("FASTEMBED_CACHE_PATH", "~/.claude/fastembed-cache")
    monkeypatch.chdir(tmp_path)

    indexer.get_model()

    junk = tmp_path / "~"
    assert not junk.exists(), (
        f"создан каталог {junk} — кэш модели уехал в мусорную папку "
        f"относительно cwd процесса, а не в домашний каталог"
    )
