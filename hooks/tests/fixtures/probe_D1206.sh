#!/usr/bin/env bash
# СУДИТ: hooks/tests/fixtures/probe_D1151.sh
# probe_D1206 — проба D1151 судит виды и формы записи, преобладающие в живых ходах с подсказкой: каждый мутант стража в
#   копии дерева её краснит. Голос мутанта — код 1: подсказка на записи при зачтённой цепочке с `notfollowed`/`repeat`/
#   `discovery`, у субагента с теми же видами, на позднем ходе сессии, на формах `>>`, `git commit`, `sed -i`, записи из
#   Python и записи в документ поведения `.md` (мутанты круга 5 D1151, скептик opus по fe78efe6, M1–M2, L3), при зачтённой
#   цепочке и у субагента на позднем ходе, у субагента на записи через Bash (скептик opus по 92518e87, M1–M2). Слепота — код
#   2: страж, не видящий события у субагента, `discovery`, `repeat` либо `notfollowed`, не кладёт вид в журнал, и проба
#   обязана сказать «повод не принят», а не «тихо». Новый вид в перечне `RC_KINDS_RE` без построителя в пробе — тоже 2.
#   Контроль — немутированная копия: проба D1151 на ней 0. Прогоны идут параллельно, каждый в своей копии.
# Код: 0 — контроль зелёный, каждый мутант даёт свой код; 1 — нет (названо); 2 — нет стража или пробы, мутант не встал
#   либо контроль не зелёный (судить мутантов не на чем).
set -u
R="${CLAUDSOUL_REPO:-$(git rev-parse --show-toplevel 2>/dev/null)}"
P="$R/hooks/tests/fixtures/probe_D1151.sh"
[ -f "$R/hooks/five-whys-gate.sh" ] && [ -f "$P" ] && command -v python3 >/dev/null 2>&1 || exit 2
W=$(mktemp -d "${TMPDIR:-/tmp}/probe-D1206.XXXXXX") || exit 2
trap 'rm -rf "$W"' EXIT
# Голос мутанта — любая строка в stdout стража на записи; содержание подсказки пробе D1151 безразлично.
V='[ "$IS_WRITE" -eq 1 ] &&'
CMD='"$(printf "%s" "$INPUT" | jq -r ".tool_input.command // empty")"'
NF='case "|$KINDS_RAW" in *"|notfollowed:"*|*"|repeat:"*|*"|discovery:"*) echo подсказка;; esac'
LATE='grep "^turn:" "$SEEN_FILE" 2>/dev/null | grep -qv "^turn:${TURN_KEY:-0}|"'   # журнал несёт строку прошлого хода
mk() {   # mk <имя> <файл в hooks/> [<было> <стало>] — копия хуков с пробой; <было>=tail — строка перед последним `exit 0`
    local d="$W/$1"
    mkdir -p "$d/hooks/tests/fixtures" || return 1
    cp "$R"/hooks/* "$d/hooks/" 2>/dev/null; cp -R "$R/hooks/lib" "$d/hooks/" && cp "$P" "$d/hooks/tests/fixtures/" || return 1
    [ $# -ge 3 ] || return 0
    python3 - "$d/hooks/$2" "$3" "${4:-}" <<'PY'
import sys
p, a, b = sys.argv[1:4]
s = open(p, encoding="utf-8").read()
if a == "tail":  # строка голоса — перед последним `exit 0` стража, где запись без права на отказ молчит
    if not s.rstrip().endswith("\nexit 0"):
        sys.exit(1)
    i = s.rstrip().rindex("\nexit 0")
    s = s[:i] + "\n" + b + s[i:]
else:
    if s.count(a) != 1:
        sys.exit(1)
    s = s.replace(a, b)
open(p, "w", encoding="utf-8").write(s)
PY
}
G=five-whys-gate.sh
mk cur "$G" || exit 2
mk m_append "$G" tail "$V case $CMD in *\">>\"*) echo подсказка;; esac" || exit 2
mk m_commit "$G" tail "$V case $CMD in *\"git commit\"*) echo подсказка;; esac" || exit 2
mk m_sed_i "$G" tail "$V case $CMD in *\"sed -i\"*) echo подсказка;; esac" || exit 2
mk m_py_write "$G" tail "$V case $CMD in *write_text*|*\"open(\"*) echo подсказка;; esac" || exit 2
mk m_target_md "$G" tail "$V case \"\${_FWG_TGT:-}\" in *.md) echo подсказка;; esac" || exit 2
mk m_carried_nf "$G" tail "$V [ \"\$_FWG_CARRIED\" -eq 1 ] && $NF" || exit 2
mk m_sub_nf "$G" tail "$V [ \"\$_FWG_IN_SUBAGENT\" -eq 1 ] && $NF" || exit 2
mk m_later_turn "$G" tail "$V $LATE && echo подсказка" || exit 2
mk m_carried_late "$G" tail "$V [ \"\$_FWG_CARRIED\" -eq 1 ] && $LATE && echo подсказка" || exit 2
mk m_sub_late "$G" tail "$V [ \"\$_FWG_IN_SUBAGENT\" -eq 1 ] && $LATE && echo подсказка" || exit 2
mk m_sub_bash "$G" tail "$V [ \"\$_FWG_IN_SUBAGENT\" -eq 1 ] && [ \"\$TOOL_NAME\" = Bash ] && echo подсказка" || exit 2
mk b_sub_event "$G" '    _ev=$(rc_open_events "$STATE" | head -3 | tr '"'\\n'"' '"';'"')' \
    '    _ev=$([ "$_FWG_IN_SUBAGENT" -eq 1 ] || rc_open_events "$STATE" | head -3 | tr '"'\\n'"' '"';'"')' || exit 2
mk b_discovery "$G" 'if [ -n "${LAST_BLOCK:-}" ] && grep -qiE "$DISCOVERY_RE" <<< "$_DISC_TEXT"; then' 'if false; then' || exit 2
mk b_repeat "$G" '    if [ "$_rep" -gt 0 ]; then' '    if false; then' || exit 2
mk b_notfollowed "$G" '    if [ "$_nf" -gt 0 ]; then' '    if false; then' || exit 2
mk n_new_kind root-cause-lib.sh 'RC_KINDS_RE="${RC_KINDS_RE:-rework:|' 'RC_KINDS_RE="${RC_KINDS_RE:-novel1206:|rework:|' || exit 2
WANT="cur=0 m_append=1 m_commit=1 m_sed_i=1 m_py_write=1 m_target_md=1 m_carried_nf=1 m_sub_nf=1 m_later_turn=1"
WANT="$WANT m_carried_late=1 m_sub_late=1 m_sub_bash=1"
WANT="$WANT b_sub_event=2 b_discovery=2 b_repeat=2 b_notfollowed=2 n_new_kind=2"
for p in $WANT; do
    m=${p%%=*}
    ( CLAUDSOUL_REPO="$W/$m" bash "$W/$m/hooks/tests/fixtures/probe_D1151.sh" >/dev/null 2>&1; echo $? > "$W/$m.rc" ) &
done
wait
[ "$(cat "$W/cur.rc" 2>/dev/null)" = 0 ] || { echo "контроль: проба D1151 на немутированной копии — код $(cat "$W/cur.rc" 2>/dev/null)"; exit 2; }
bad=0
for p in $WANT; do
    m=${p%%=*}; rc=$(cat "$W/$m.rc" 2>/dev/null)
    [ "$rc" = "${p#*=}" ] || { echo "мутант $m: проба D1151 — код ${rc:-нет}, а не ${p#*=}"; bad=1; }
done
[ "$bad" -eq 0 ] && echo "контроль зелёный; голос мутантов — 1, слепота и вид без построителя — 2"
exit "$bad"
