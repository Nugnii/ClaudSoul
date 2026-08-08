#!/usr/bin/env bash
# timestamp-inject.sh — UserPromptSubmit: инжект текущего времени собеседника.
# en: injects the user's current local time each prompt; the reply must start
# with it — a cheap context-drift canary.
#
# Зачем. Правило «каждый ответ начинается с таймштампа» (rules/CLAUDE.md,
# решение собеседника 2026-08-08) требует источник времени: у модели нет часов,
# время из головы — выдумка (в день введения правила записи подписывались
# «поздняя ночь» при реальных 16:45). Инжект делает таймштамп механическим:
# агент эхоит, не сочиняет. Канарейка: инжект есть, а ответ начат без
# таймштампа → инструкции размылись, сессию пора перезапускать.
#
# Универсален: без проектных файлов, без состояния, работает в любом проекте.

set -uo pipefail

command -v jq >/dev/null 2>&1 || exit 0
cat >/dev/null 2>&1 || true   # stdin хука не нужен, но пайп читаем до конца

NOW=$(date '+%Y-%m-%d %H:%M %Z' 2>/dev/null) || exit 0
[ -n "$NOW" ] || exit 0

jq -cn --arg m "🕐 ${NOW} — начни ответ этим таймштампом (канарейка контекста)" \
  '{hookSpecificOutput: {hookEventName: "UserPromptSubmit", additionalContext: $m}}'
