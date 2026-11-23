#!/usr/bin/env bash
set -u
# СУДИТ: hooks/lib/backfill-replay-one.sh
# probe_D1154.sh — воркер реплея отдаёт те же события при заданном `STATE_DIR` в окружении, что и без него (D1154).
#   Воркер подменял только `HOME`, детектор писал состояние в унаследованный `STATE_DIR` (`hooks/paths-lib.sh` его
#   сохраняет), а воркер читал `$HOME/.claude/hooks/state/…` — файла нет, событий 0, молча.
#   Расшифровка — та же, что у ноги T2 `hooks/tests/test_backfill.sh` (предложение и согласие → событие `gentle`).
#   0 — событий поровну и больше нуля, чужой каталог пуст; 1 — с `STATE_DIR` или `ITR_STATE_DIR` в окружении событий
#   иначе либо реплей писал в унаследованный каталог; 2 — нет воркера/jq либо без них событий 0 (рамка не собралась:
#   равенство нулей ничего не судит).
cd "${CLAUDSOUL_REPO:-$(git rev-parse --show-toplevel 2>/dev/null)}" 2>/dev/null || exit 2
WK="$PWD/hooks/lib/backfill-replay-one.sh"
[ -f "$WK" ] && command -v jq >/dev/null 2>&1 || exit 2
W=$(mktemp -d) || exit 2
trap 'rm -rf "$W"' EXIT
mkdir -p "$W/foreign"
{
    jq -cn '{type:"user", timestamp:"2026-04-01T10:00:00Z", message:{role:"user", content:[{type:"text", text:"напиши функцию"}]}}'
    jq -cn '{type:"assistant", timestamp:"2026-04-01T10:00:05Z", message:{role:"assistant", content:[{type:"text", text:"Вот набросок функции. Всё готово, запускаем?"}]}}'
    jq -cn '{type:"user", timestamp:"2026-04-01T10:00:30Z", message:{role:"user", content:[{type:"text", text:"да"}]}}'
} > "$W/t.jsonl"
n_without=$(env -u STATE_DIR BACKFILL_TMP="$W" bash "$WK" "$W/t.jsonl" 2>/dev/null | grep -c '"source":"backfill"')
n_with=$(STATE_DIR="$W/foreign" BACKFILL_TMP="$W" bash "$WK" "$W/t.jsonl" 2>/dev/null | grep -c '"source":"backfill"')
# Вторая переменная той же дыры: `ITR_STATE_DIR` библиотека состояния ставит первой (`hooks/intrusiveness-state-lib.sh:72`).
n_itr=$(env -u STATE_DIR ITR_STATE_DIR="$W/foreign" BACKFILL_TMP="$W" bash "$WK" "$W/t.jsonl" 2>/dev/null | grep -c '"source":"backfill"')
[ "${n_without:-0}" -gt 0 ] || { echo "рамка: без STATE_DIR событий 0"; exit 2; }
# Изоляция: песочница не пишет в унаследованный каталог — иначе на живом состоянии реплей писал бы в живое, а остаток
# (`itr_event_last_fire_*`) гасил бы события следующего прогона дедупом (D1154, круг 2, M1: равенство чисел этого не видит).
left=$(find "$W/foreign" -type f 2>/dev/null | head -3)
[ -z "$left" ] || { echo "дефект: реплей писал в унаследованный каталог: $left"; exit 1; }
[ "$n_with" = "$n_without" ] && [ "$n_itr" = "$n_without" ] \
    || { echo "дефект: с STATE_DIR событий $n_with, с ITR_STATE_DIR $n_itr, без них $n_without"; exit 1; }
echo "событий поровну: $n_with"
