#!/usr/bin/env bash
# СУДИТ: hooks/lib/reply-readers.tsv hooks/tests/fixtures/probe_D1145.sh
# test_reply_readers_registry.sh — D1145 (корень R3): у каждого читателя признака «реплика владельца» объявлено понятие
# (граница-узкая | граница-широкая | граница-без-сводки | речь | до-текущей | источник | не-реплика), и новый читатель без строки краснит свидетеля. Ноги — на
# дереве-фикстуре: читатель по имени и читатель со своей копией в любой форме без строки — красно; упоминание в
# комментарии и файл теста читателем не делают; понятие вне словаря, «источник» без определения, второе определение
# признака, строка без файла, строка для не-читателя и дубль — красно. НАЗВАННЫЙ ПРЕДЕЛ: верно ли понятие читателю,
# свидетель не судит. Условие снятия: D1149 закрыт — понятие строки сверяется поведенческой ногой читателя.
set -uo pipefail
DIR="$(cd "$(dirname "$0")" && pwd)"
REPO="$(cd "$DIR/../.." && pwd)"
PROBE="$DIR/fixtures/probe_D1145.sh"
PASS=0; FAIL=0
ok()  { PASS=$((PASS + 1)); }
bad() { FAIL=$((FAIL + 1)); echo "FAIL [$1]: $2"; }
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT

# T1 — настоящее дерево: у каждого читателя строка есть.
out=$(CLAUDSOUL_REPO="$REPO" bash "$PROBE" 2>&1); rc=$?
[ "$rc" -eq 0 ] && ok || bad T1 "живое дерево: rc=$rc — $out"

ROOT="$T/r"
base() {  # дерево с источником и пустым реестром
    rm -rf "$ROOT"; mkdir -p "$ROOT/hooks/lib" "$ROOT/hooks/tests" "$ROOT/scripts"
    printf 'def is_owner_reply(rec):\n    return True\n' > "$ROOT/hooks/lib/transcript_window.py"
    printf '# шапка\nhooks/lib/transcript_window.py\tисточник\n' > "$ROOT/hooks/lib/reply-readers.tsv"
}
row() { printf '%s\t%s\n' "$1" "$2" >> "$ROOT/hooks/lib/reply-readers.tsv"; }
expect() {  # expect <нога> <код> <подстрока вывода или пусто>
    out=$(CLAUDSOUL_REPO="$ROOT" bash "$PROBE" 2>&1); rc=$?
    [ "$rc" -eq "$2" ] || { bad "$1" "ожидался код $2, получен $rc — $out"; return; }
    [ -z "$3" ] || grep -Fq "$3" <<< "$out" || { bad "$1" "в выводе нет «$3»: $out"; return; }
    ok
}

base; expect T2 0 ""
# T3 — читатель по имени без строки; T4 — та же строка в реестре — зелено.
base; printf 'x=$(transcript_user_texts "$T" 1)\n' > "$ROOT/hooks/new-guard.sh"; expect T3 1 "нет понятия: hooks/new-guard.sh"
row hooks/new-guard.sh речь; expect T4 0 ""
# T5 — своя копия признака без строки, в каждой форме, которую держит дерево (скептик D1145, M2).
base; printf 'if t == "user":\n    pass\n' > "$ROOT/scripts/replay.py"; expect T5 1 "нет понятия: scripts/replay.py"
base; printf 'if rec.get("type") != "user":\n    pass\n' > "$ROOT/scripts/neq.py"; expect T5b 1 "нет понятия: scripts/neq.py"
base; printf '[ "$ROLE" = "user" ] && echo y\n' > "$ROOT/hooks/sh-eq.sh"; expect T5c 1 "нет понятия: hooks/sh-eq.sh"
base; printf 'jq "select(.type == \\"user\\")" f\n' > "$ROOT/hooks/jq-esc.sh"; expect T5d 1 "нет понятия: hooks/jq-esc.sh"
base; printf 'b=$(rc_last_block "$T")\n' > "$ROOT/hooks/rc-reader.sh"; expect T5e 1 "нет понятия: hooks/rc-reader.sh"
# T6 — упоминание только в комментарии читателем не делает; файл теста — тоже.
base; printf '# живёт в transcript_user_texts\n' > "$ROOT/hooks/paths.sh"
printf 'x=$(transcript_user_texts "$T" 1)\n' > "$ROOT/hooks/tests/test_x.sh"; expect T6 0 ""
# T6b — репозиторий под каталогом `tests/`: фильтр тестов судит путь внутри дерева, а не абсолютный (L1).
ROOT="$T/x/tests/repo"; base; printf 'x=$(transcript_user_texts "$T" 1)\n' > "$ROOT/hooks/g.sh"
expect T6b 1 "нет понятия: hooks/g.sh"; ROOT="$T/r"
# T7 — понятие вне словаря.
base; printf 'x=$(transcript_user_texts "$T" 1)\n' > "$ROOT/hooks/g.sh"; row hooks/g.sh реплика; expect T7 1 "нет понятия: hooks/g.sh"
# T7b — снятое слово «граница» (звало и узкое понятие, и широкое; D1149) — тоже вне словаря.
base; printf 'x=$(transcript_user_texts "$T" 1)\n' > "$ROOT/hooks/g.sh"; row hooks/g.sh граница; expect T7b 1 "нет понятия: hooks/g.sh"
# T8 — «источник» без определения признака в файле; T8b — второе определение признака, назвавшее себя источником (L3).
base; printf 'x=$(transcript_user_texts "$T" 1)\n' > "$ROOT/hooks/g.sh"; row hooks/g.sh источник
expect T8 1 "источник без определения признака: hooks/g.sh"
base; printf 'def is_owner_reply(rec):\n    return False\n' > "$ROOT/scripts/copy.py"; row scripts/copy.py источник
expect T8b 1 "признак определён в 2 файлах"
# T8c — двойник владельца в jq (`HIL_OWNER_REPLY_JQ`, D1150) — тоже признак: второе его определение красно; T8d — читатель,
# зовущий только `owner_reply`, без строки — красно.
base; printf 'HIL_OWNER_REPLY_JQ=x\n' > "$ROOT/hooks/lib1.sh"; printf 'HIL_OWNER_REPLY_JQ=y\n' > "$ROOT/hooks/lib2.sh"
row hooks/lib1.sh источник; row hooks/lib2.sh источник; expect T8c 1 "признак определён в 2 файлах: ^HIL_OWNER_REPLY_JQ="
base; printf 'jq "${HIL_OWNER_REPLY_JQ:-def owner_reply: false;}"\n' > "$ROOT/hooks/g.sh"; expect T8d 1 "нет понятия: hooks/g.sh"
# T9 — строка без файла; T9b — строка для не-читателя; T9c — дубль строки (L3).
base; row hooks/gone.sh граница-широкая; expect T9 1 "строка без файла: hooks/gone.sh"
base; printf 'echo hi\n' > "$ROOT/hooks/plain.sh"; row hooks/plain.sh граница-широкая; expect T9b 1 "строка для не-читателя: hooks/plain.sh"
base; printf 'x=$(transcript_user_texts "$T" 1)\n' > "$ROOT/hooks/g.sh"; row hooks/g.sh речь; row hooks/g.sh граница-широкая
expect T9c 1 "дубль строки: hooks/g.sh"
# T10 — реестра нет.
base; rm "$ROOT/hooks/lib/reply-readers.tsv"; expect T10 1 "реестра нет"

echo "reply-readers registry: PASS=$PASS FAIL=$FAIL"
exit $(( FAIL != 0 ))
