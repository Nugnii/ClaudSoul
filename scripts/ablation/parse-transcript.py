#!/usr/bin/env python3
"""parse-transcript.py — метрики плеча из артефактов песочницы (протокол §8.1).

Использование: parse-transcript.py <task_id> <arm>

Источники (всё внутри ABLATION_DIR/runs/<task_id>/<arm>/):
  result.json  — итог `claude -p --output-format json`: токены/длительность/ходы
                 (поля берутся оборонительно — формат CLI может меняться);
  home/.claude/projects/*/*.jsonl — транскрипты песочницы: all_commands =
                 количество tool_use, failed_commands = tool_result с is_error.

Стоимость считается по ВСЕМ запускам попытки (потолок 500k — §11): metrics
пишутся событием arm_metrics в журнал и печатаются; conditioning bias
(«считать только успешные») исключён тем, что парсер не смотрит на исход.
"""
import json
import os
import sys
from datetime import datetime, timezone
from pathlib import Path


def main() -> None:
    if len(sys.argv) != 3:
        sys.exit("usage: parse-transcript.py <task_id> <arm>")
    task_id, arm = sys.argv[1], sys.argv[2]
    base = Path(os.environ.get("ABLATION_DIR", Path.home() / ".claude" / "ablation"))
    run = base / "runs" / task_id / arm
    if not run.is_dir():
        sys.exit(f"parse: прогона {task_id}/{arm} нет")

    tokens_in = tokens_out = turns = 0
    duration_ms = 0
    result_file = run / "result.json"
    if result_file.is_file():
        try:
            res = json.loads(result_file.read_text())
            usage = res.get("usage", {})
            tokens_in = usage.get("input_tokens", 0) or 0
            tokens_out = usage.get("output_tokens", 0) or 0
            turns = res.get("num_turns", 0) or 0
            duration_ms = res.get("duration_ms", 0) or 0
        except (json.JSONDecodeError, OSError):
            pass  # метрики частичны — транскрипты ниже всё равно считаются

    all_commands = failed_commands = 0
    for jf in run.glob("home/.claude/projects/*/*.jsonl"):
        for line in jf.read_text().splitlines():
            try:
                item = json.loads(line)
            except json.JSONDecodeError:
                continue
            content = (item.get("message", {}) or {}).get("content")
            if not isinstance(content, list):
                continue
            for block in content:
                if not isinstance(block, dict):
                    continue
                if block.get("type") == "tool_use":
                    all_commands += 1
                if block.get("type") == "tool_result" and block.get("is_error"):
                    failed_commands += 1

    metrics = {
        "e": "arm_metrics", "id": task_id, "arm": arm,
        "ts": datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
        "tokens_in": tokens_in, "tokens_out": tokens_out,
        "turns": turns, "duration_ms": duration_ms,
        "all_commands": all_commands, "failed_commands": failed_commands,
    }
    with (base / "journal.jsonl").open("a") as f:
        f.write(json.dumps(metrics, ensure_ascii=False, separators=(",", ":")) + "\n")
    print(json.dumps(metrics, ensure_ascii=False))


if __name__ == "__main__":
    main()
