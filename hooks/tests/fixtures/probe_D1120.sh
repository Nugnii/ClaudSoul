#!/usr/bin/env bash
# СУДИТ: hooks/root-cause-lib.sh scripts/outcome.sh hooks/tests/fixtures/probe_D1109.sh hooks/tests/fixtures/probe_D1110.sh
# probe_D1120 — пробы сверки исхода различают заявленное: каждая из пяти мутаций, выхолащивающих заявленное в D1109 и
# D1110, краснит хотя бы одну пробу серии кодом 1 («дефект»), а не 2 («рамка не собралась»). Красная (1), пока хоть
# одна мутация проходит незамеченной (скептик D1108, L5: m04 причина последняя, m05 упоминание подстрокой, m07 пути
# предмета из текста сняты, m12 дедуп печатает «записан», m10 бэклог цели не снимается — D1110 отвечает 2).
# Копия — `git archive HEAD`: судится закоммиченное. Рамка не собралась — 2.
R="${CLAUDSOUL_REPO:-$(cd "$(dirname "$0")/../../.." && pwd)}"
[ -f "$R/hooks/root-cause-lib.sh" ] && command -v perl >/dev/null 2>&1 && command -v git >/dev/null 2>&1 || exit 2
BASE=$(mktemp -d "${TMPDIR:-/tmp}/probe-D1120.XXXXXX") || exit 2
mkdir -p "$BASE/pristine" && ( cd "$R" && git archive HEAD ) | tar -x -C "$BASE/pristine" || exit 2
LIB=hooks/root-cause-lib.sh
PROBES="1106 1107 1108 1109 1110 1111 1115 1116"
missed=""
mut() {   # <имя> <файл> <perl-выражение> — 0, если хоть одна проба покраснела кодом 1
    d="$BASE/$1"; cp -R "$BASE/pristine" "$d" || return 2
    before=$(cksum < "$d/$2"); perl -0pi -e "$3" "$d/$2"; after=$(cksum < "$d/$2")
    [ "$before" != "$after" ] || { echo "$1: мутация не легла" >&2; return 2; }
    for p in $PROBES; do
        [ -f "$d/hooks/tests/fixtures/probe_D$p.sh" ] || continue
        ( cd "$d" && CLAUDSOUL_REPO="$d" bash "hooks/tests/fixtures/probe_D$p.sh" >/dev/null 2>&1 ); [ $? -eq 1 ] && return 0
    done
    return 1
}
# Положительный контроль рамки: «свежесть всегда» пробы ловят (D1106, D1108) — иначе «не заметили» значило бы сломанную
# рамку выхолащивания, а не слепые пробы.
# Мутации независимы (у каждой своя копия дерева) и идут ПАРАЛЛЕЛЬНО (D1222, 8 ноября 2026): подряд проба шла 253 с при
# нагрузке 10–15 — дольше срока прибора свидетелей-атак и срока «Проверки» архиватора; исход каждой — в файле `<имя>.rc`.
( mut m01_fresh_always "$LIB" 's/(_rc_block_fresh_snap\(\) \{[^\n]*\n)/$1    return 0\n/'; echo $? > "$BASE/m01_fresh_always.rc" ) &
names=""
for m in \
    "m04_fail_last|$LIB|s/_rv_fail\(\) \{ \[ -n \"\\\$\{_rv_bad:-\}\" \] \|\| _rv_bad=\"\\\$1\"; \}/_rv_fail() { _rv_bad=\"\\\$1\"; }/" \
    "m05_textname_substr|$LIB|s/grep -qxF -- \"\\\$\{2:-\}\" <<< \"\\\$_tn_w\"/grep -qF -- \"\\\${2:-}\" <<< \"\\\$_tn_w\"/" \
    "m07_no_text_subj|$LIB|s/printf '%s\\\\n' \"\\\$_on_x\" \| grep -oE/printf '' | grep -oE/" \
    "m10_no_target_snap|$LIB|s/_rc_snap_backlog \"\\\$1\" \"\\\$_ot_s\"/: \"\\\$1\" \"\\\$_ot_s\"/" \
    "m12_dedup_says_written|scripts/outcome.sh|s/if \[ \"\\\$\{_n1:-0\}\" -gt \"\\\$\{_n0:-0\}\" \] 2>\/dev\/null; then/if true; then/"; do
    name=${m%%|*}; rest=${m#*|}; file=${rest%%|*}; expr=${rest#*|}
    ( mut "$name" "$file" "$expr"; echo $? > "$BASE/$name.rc" ) &
    names="$names $name"
done
wait
[ "$(cat "$BASE/m01_fresh_always.rc" 2>/dev/null)" = 0 ] || exit 2
for name in $names; do
    rc=$(cat "$BASE/$name.rc" 2>/dev/null); rc=${rc:-2}
    [ "$rc" -eq 2 ] && exit 2
    [ "$rc" -eq 0 ] || missed="$missed $name"
done
[ -z "$missed" ] || { echo "мутации, которых пробы не заметили:$missed" >&2; exit 1; }
echo "каждая мутация заявленного краснит пробу кодом 1"
exit 0
