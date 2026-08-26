#!/usr/bin/env bash
# statusline-claudsoul.sh — строка статуса Claude Code с индикатором фазы ablation.
#
# Единственная АРХИТЕКТУРНО постоянная владелец-видимая поверхность: событийные
# systemMessage дважды прошли мимо владельца (amendment phase-1 и ui_exception
# phase-2, 2026-08-08/09) — фаза обязана стоять перед глазами, а не мелькать.
# Фазы нет — сегмент 🧪 исчезает, остаётся обычная строка (модель · каталог).
#
# Вход: stdin JSON от Claude Code (model.display_name, workspace.current_dir).

input=$(cat)
model=$(printf '%s' "$input" | jq -r '.model.display_name // empty' 2>/dev/null)
cwd=$(printf '%s' "$input" | jq -r '.workspace.current_dir // .cwd // empty' 2>/dev/null)

line="${model:-Claude}"
[ -n "$cwd" ] && line="${line} · ${cwd##*/}"

M="$HOME/.claude/ablation/active-phase.json"
if [ -f "$M" ] && command -v jq >/dev/null 2>&1; then
    phase=$(jq -r '.phase // empty' "$M" 2>/dev/null)
    if [ -n "$phase" ]; then
        J="$HOME/.claude/ablation/journal.jsonl"
        q=0
        [ -f "$J" ] && q=$(jq -s '[.[] | select(.e=="queue")] | length' "$J" 2>/dev/null)
        line="${line} · 🧪 ablation ${phase} · очередь ${q:-0}/20"
    fi
fi

printf '%s' "$line"
