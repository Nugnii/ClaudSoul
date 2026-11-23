#!/usr/bin/env bash
# СУДИТ: hooks/hook-input-lib.sh hooks/lib/transcript_window.py hooks/root-cause-lib.sh hooks/activity-flush-lib.sh hooks/shared-language-lib.sh
# test_adv_fold_helper_skew.sh — противник свёртки (D498): помощник прежнего выпуска на вызове `--fold` печатает смещение хода и выходит с 0, а `transcript_fold` принимает это число за накопленное — rc_*, activity_flush и shlang_candidates выдают мусор вместо запасного пути.
#
# Протокол окна защищён строкой «ok»: помощник, который её не сказал, считается отказавшим, и
# вызывающий берёт файл целиком. У свёртки такой защиты нет — судит только код возврата. Помощник
# прежнего выпуска (ec157dbd) ключа `--fold` не знает: незнакомые ключи проходят мимо, и без
# `--range` он печатает `off` — смещение начала хода — с кодом 0. Пара «новые библиотеки + прежний
# помощник» возникает в мире: `install.sh` переносит `hooks/*.sh` раньше `hooks/lib/*` (окно в
# секунды, когда параллельная сессия зовёт хуки), а перенос приёмника, правленного после прошлого
# переноса, доставщик отказывает (ADR-019) — и пара держится до ручного вмешательства.
# Ожидание: вывод тот же, что у согласованной пары (помощник не ответил свёрткой — запасной путь).
# Помощник прежнего выпуска воспроизведён его же поведением на незнакомых ключах: `turn_offset`
# нынешнего модуля (функция между выпусками та же) и `print(off)`.
set -uo pipefail
HOOKS="$(cd "$(dirname "$0")/.." && pwd)"
command -v python3 >/dev/null 2>&1 || { echo "SKIP: нет python3"; exit 0; }
command -v jq >/dev/null 2>&1 || { echo "SKIP: нет jq"; exit 0; }
unset INPUT_LIB HOOK_INPUT_LIB STATE_LOCK_LIB PATHS_LIB
PASS=0; FAIL=0
ok()  { PASS=$((PASS + 1)); }
bad() { FAIL=$((FAIL + 1)); echo "FAIL [$1]: $2"; }
T=$(mktemp -d)
export TMPDIR="$T/tmp"; mkdir -p "$TMPDIR"   # временные файлы помощника — тоже под каталогом теста

# Дерево с прежним помощником: библиотеки нынешние, помощник — прежнего выпуска.
mkdir -p "$T/skew/lib"
for f in hook-input-lib.sh root-cause-lib.sh activity-flush-lib.sh shared-language-lib.sh state-lock-lib.sh; do
    cp "$HOOKS/$f" "$T/skew/$f"
done
cp "$HOOKS/lib/state_lock.py" "$T/skew/lib/state_lock.py"
cat > "$T/skew/lib/transcript_window.py" <<PY
#!/usr/bin/env python3
# Помощник прежнего выпуска: режима --fold нет, без --range печатается смещение начала хода.
import importlib.util, sys
spec = importlib.util.spec_from_file_location("tw_real", "$HOOKS/lib/transcript_window.py")
tw = importlib.util.module_from_spec(spec); spec.loader.exec_module(tw)
st = sys.argv[sys.argv.index("--state") + 1] if "--state" in sys.argv[:-1] else None
print(tw.turn_offset(sys.argv[1], st)[0])
PY

# Расшифровка: 30 ходов — реплика с латинскими терминами, ответ агента, правка файла.
python3 - "$T/t.jsonl" <<'PY'
import json, sys
def u(x): return json.dumps({"type": "user", "origin": {"kind": "human"}, "message": {"role": "user", "content": [{"type": "text", "text": x}]}}, ensure_ascii=False)
def a(x): return json.dumps({"type": "assistant", "message": {"role": "assistant", "content": [{"type": "text", "text": x}]}}, ensure_ascii=False)
def e(fp): return json.dumps({"type": "assistant", "message": {"role": "assistant", "content": [{"type": "tool_use", "name": "Edit", "input": {"file_path": fp}}]}})
ls = []
for i in range(30):
    ls += [u(f"проверь workflow-x и deploy-check {i}"), a(f"ответ {i}"), e(f"/r/f{i % 3}.sh")]
open(sys.argv[1], "w", encoding="utf-8").write("\n".join(ls) + "\n")
PY

GRAB='printf "key=%s\n" "$(rc_turn_key "$2")"; printf "last=%s\n" "$(rc_last_block "$2")"
      d=$(mktemp -d "$3/af.XXXX"); activity_flush sid-skew-01 "$2" "$d" >/dev/null 2>&1
      sed "/^## /d" "$d/.claude-docs/session-activity.md" 2>/dev/null
      printf "shlang=%s\n" "$(shlang_candidates "$2" /dev/null 3 | tr "\n" ,)"'
grab() {  # grab <каталог хуков> <каталог состояния>
    mkdir -p "$2"
    STATE_DIR="$2" bash -c ". \"\$1/root-cause-lib.sh\"; . \"\$1/activity-flush-lib.sh\"; . \"\$1/shared-language-lib.sh\"; $GRAB" \
        _ "$1" "$T/t.jsonl" "$T"
}
REF=$(grab "$HOOKS" "$T/st-ref")
GOT=$(grab "$T/skew" "$T/st-skew")

# Положительный контроль: у согласованной пары вывод не тривиален.
case "$REF" in *"last=ответ 29"*"Tool calls: 30 (Edit:30)"*"workflow-x ×30"*) ok ;;
    *) bad K0 "согласованная пара дала тривиальный вывод: ${REF:0:300}" ;; esac
# Контроль воспроизведения: помощник прежнего выпуска на вызове свёртки отвечает числом с кодом 0.
K1=$(python3 "$T/skew/lib/transcript_window.py" "$T/t.jsonl" --fold x --state "$T/st-k1" -- cat 2>&1); K1RC=$?
case "$K1RC:$K1" in 0:[0-9]*) ok ;; *) bad K1 "помощник прежнего выпуска не воспроизведён: код $K1RC, вывод «${K1:0:200}»" ;; esac

field() { grep -m1 -E "^$2" <<< "$1"; }
[ "$(field "$GOT" key=)" = "$(field "$REF" key=)" ] && ok \
    || bad S1 "rc_turn_key: $(field "$GOT" key=) вместо $(field "$REF" key=) — метка хода из смещения, а не из реплики"
[ "$(field "$GOT" last=)" = "$(field "$REF" last=)" ] && ok \
    || bad S2 "rc_last_block: «$(field "$GOT" last=)» вместо «$(field "$REF" last=)»"
if grep -q "НЕ ПРОЧИТАНА" <<< "$GOT"; then
    bad S3 "activity_flush пишет «активность НЕ ПРОЧИТАНА» при читаемой расшифровке: $(grep -E 'НЕ ПРОЧИТАНА|Tool calls' <<< "$GOT" | tr '\n' ' ')"
else ok; fi
[ "$(field "$GOT" shlang=)" = "$(field "$REF" shlang=)" ] && ok \
    || bad S4 "shlang_candidates: «$(field "$GOT" shlang=)» вместо «$(field "$REF" shlang=)» — смещение хода принято за счёт токенов"

echo "test_adv_fold_helper_skew: прошло $PASS, упало $FAIL"
exit $(( FAIL != 0 ))
