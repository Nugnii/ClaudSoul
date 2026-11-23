#!/usr/bin/env bash
# resolve-claudsoul-repo.sh — единый детектор корня репозитория ClaudSoul.
#
# Был скопирован вербатим в 4 скилла (ingest/entity/wiki, + enrich ссылался текстом)
# с уже разошедшимися формулировками ошибок. Вынесен сюда; install.sh деплоит в
# ~/.claude/bin/, скиллы делают `source "$HOME/.claude/bin/resolve-claudsoul-repo.sh"`.
#
# Bootstrap: лежит в ИЗВЕСТНОМ ~/.claude/bin/, а не в самом репозитории — иначе
# курица-яйцо (функция ищет репо, поэтому не может жить внутри того, что ищет).
#
# Provides:
#   resolve_claudsoul_repo  → печатает путь к корню репо (stdout) или ошибку (stderr, код 1)
# Порядок резолва: CLAUDSOUL_REPO env → ~/.claude/claudsoul-repo (пишет install.sh) → git-корень.

resolve_claudsoul_repo() {
    # 1. Переменная окружения (явный override)
    if [ -n "${CLAUDSOUL_REPO:-}" ] && [ -d "$CLAUDSOUL_REPO/mcp-server/ingest" ]; then
        echo "$CLAUDSOUL_REPO"; return
    fi
    # 2. Постоянный файл, записанный install.sh
    if [ -f "$HOME/.claude/claudsoul-repo" ]; then
        local path
        path=$(cat "$HOME/.claude/claudsoul-repo" 2>/dev/null)
        if [ -d "$path/mcp-server/ingest" ]; then echo "$path"; return; fi
    fi
    # 3. Git-корень (работает если cwd внутри ClaudSoul)
    local root
    root=$(git rev-parse --show-toplevel 2>/dev/null || true)
    if [ -n "$root" ] && [ -d "$root/mcp-server/ingest" ]; then
        echo "$root"; return
    fi
    echo "ERROR: не могу найти ClaudSoul. Запусти install.sh из корня репо, либо задай CLAUDSOUL_REPO=/путь/к/ClaudSoul" >&2
    return 1
}
