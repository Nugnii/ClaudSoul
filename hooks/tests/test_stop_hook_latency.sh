#!/usr/bin/env bash
# СУДИТ: scripts/stop-hook-latency.sh
# test_stop_hook_latency.sh — замер хуков Stop отделяет собственную цену хука от остановки машины: одиночный выход за
# предел — 1 и имя хука; граница, где медленна половина хуков и больше, — остановка, не находка (0); все быстрые — 0;
# границ в окне нет — 2. Рамка: каталог подложенных расшифровок (SHL_TRANSCRIPTS) с записями `stop_hook_summary`.
set -uo pipefail
REPO="$(cd "$(dirname "$0")/../.." && pwd)"
S="$REPO/scripts/stop-hook-latency.sh"
PASS=0; FAIL=0
ok()  { PASS=$((PASS + 1)); }
bad() { FAIL=$((FAIL + 1)); echo "FAIL [$1]: $2"; }
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
NOW=$(date -u +%Y-%m-%dT%H:%M:%SZ)
row() {  # <файл> <мс хука a> <мс хука b> <мс хука c> <мс хука d>
    # live-home-ok: `~/.claude/hooks/…` — строка данных фикстуры (команда хука в записи stop_hook_summary), не чтение
    printf '{"type":"system","subtype":"stop_hook_summary","timestamp":"%s","hookInfos":[{"command":"bash ~/.claude/hooks/a.sh","durationMs":%s},{"command":"bash ~/.claude/hooks/b.sh","durationMs":%s},{"command":"bash ~/.claude/hooks/c.sh","durationMs":%s},{"command":"bash ~/.claude/hooks/d.sh","durationMs":%s}]}\n' "$NOW" "$2" "$3" "$4" "$5" >> "$1"
}
run() { OUT=$(SHL_TRANSCRIPTS="$1" bash "$S" 2>&1); RC=$?; }
mkdir -p "$T/one" "$T/stall" "$T/fast" "$T/empty"
row "$T/one/s.jsonl" 900 30000 1200 800
run "$T/one"; [ "$RC" = 1 ] && grep -q 'b.sh  30.0 с' <<< "$OUT" && ok || bad T1 "одиночный выход за предел — ждали 1 и b.sh: код $RC, «${OUT}»"
row "$T/stall/s.jsonl" 12000 30000 900 15000
run "$T/stall"; [ "$RC" = 0 ] && grep -q 'остановок машины (медленна половина хуков и больше) 1' <<< "$OUT" && ok \
    || bad T2 "три из четырёх медленны — остановка, ждали 0 и счёт остановок: код $RC, «${OUT}»"
row "$T/fast/s.jsonl" 900 1100 1200 800
run "$T/fast"; [ "$RC" = 0 ] && ok || bad T3 "все быстрые — ждали 0: код $RC, «${OUT}»"
printf '{"type":"user","timestamp":"%s"}\n' "$NOW" > "$T/empty/s.jsonl"
run "$T/empty"; [ "$RC" = 2 ] && grep -q 'не измерено' <<< "$OUT" && ok || bad T4 "границ нет — ждали 2: код $RC, «${OUT}»"
run "$T/none"; [ "$RC" = 2 ] && ok || bad T4b "нет каталога — ждали 2: код $RC"
# T5 — граница старше окна не судится: та же одиночная запись трёхдневной давности при окне в сутки — 2.
OLD=$(date -u -v-3d +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || date -u -d '3 days ago' +%Y-%m-%dT%H:%M:%SZ)
mkdir -p "$T/old"; sed "s/$NOW/$OLD/" "$T/one/s.jsonl" > "$T/old/s.jsonl"
OUT=$(SHL_TRANSCRIPTS="$T/old" SHL_DAYS=1 bash "$S" 2>&1); RC=$?
[ "$RC" = 2 ] && ok || bad T5 "граница вне окна судилась: код $RC, «${OUT}»"
# T6 — каталог расшифровок берётся у указателя установки, а не у корня кода: корень привязан к снимку без расшифровок
# (так зовёт прибор свидетелей-атак), указатель называет настоящий репозиторий — замер судит его сессии (D1295).
mkdir -p "$T/h/.claude" "$T/real repo" "$T/snap"
printf '%s\n' "$T/real repo" > "$T/h/.claude/claudsoul-repo"
P="$T/h/.claude/projects/$(printf '%s' "$T/real repo" | sed 's|[/ ]|-|g')"; mkdir -p "$P"; cp "$T/one/s.jsonl" "$P/"
# `env -u SHL_TRANSCRIPTS`: каталог, заданный вызывающим, перекрыл бы указатель, и нога судила бы окружение, а не предмет
# (скептик opus по a97f2d2e, L1).
OUT=$(env -u SHL_TRANSCRIPTS HOME="$T/h" CLAUDSOUL_REPO="$T/snap" bash "$S" 2>&1); RC=$?
[ "$RC" = 1 ] && grep -q 'b.sh' <<< "$OUT" && ok || bad T6 "корень кода — снимок, указатель — настоящий: ждали 1 и b.sh, код $RC, «${OUT}»"
echo "stop-hook-latency: $PASS passed, $FAIL failed"
exit $(( FAIL != 0 ))
