#!/usr/bin/env bash
# backlog-recheck.sh — закрытый пункт долга обязан оставаться закрытым.
# Результат: закрытые пункты долга остались закрытыми — воскресших нет
# Проверка результата: bash scripts/backlog-recheck.sh даёт 0
#
#
# Зачем. Закрытия бывают двух видов, и держатся они по-разному:
#
#   · закрытие, за которым стоит ТЕСТ, проверяет себя само — тест гоняется каждый прогон,
#     и регрессия становится красной строкой без чьего-либо участия;
#   · закрытие РАЗОВЫМ ДЕЙСТВИЕМ (лог вычищен, ссылки восстановлены, поле задокументировано)
#     не проверяет себя ничем. Оно может тихо откатиться, и в файле долга пункт останется
#     помеченным «сделано».
#
# Замер на 2026-07-29: из 28 закрытых пунктов 11 держались тестом, 17 — разовым действием.
# Этот скрипт закрывает вторую половину: у каждого проверяемого пункта — свой инвариант
# и своя команда, а не общее «посмотреть глазами».
#
# Что НЕ проверяется и почему. Пункты-решения (записан ADR, вопрос собеседнику отвечен,
# отказ зафиксирован) регрессировать не могут: у них нет состояния, которое портится.
# Их перечисление здесь было бы имитацией проверки.
#
# Запуск: вручную либо из недельного дайджеста. Код возврата 1, если хоть один инвариант
# перестал держаться.

set -uo pipefail

# Подстановка в ёлочках пишется ТОЛЬКО как «${var}». Ёлочки многобайтовые, и при `set -u`
# bash читает «$var» как имя переменной вместе с закрывающей кавычкой — «unbound variable».  # mb-ok: строка демонстрирует дефект, а не совершает его
# Тот же класс, что чинился в v1.14.6: многобайтовый символ вплотную к синтаксису оболочки.

REPO="${CLAUDSOUL_REPO:-$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")/.." 2>/dev/null && pwd -P)}"
LESSONS="${LESSONS_DIR:-$HOME/.claude/global-lessons}"
STATE="${STATE_DIR:-$HOME/.claude/hooks/state}"

if [ ! -f "$REPO/BACKLOG.md" ]; then
    echo "backlog-recheck: не найден $REPO/BACKLOG.md" >&2
    exit 2
fi

BROKEN=0
CHECKED=0

# report СТАТУС ПУНКТ ТЕКСТ
report() {
    CHECKED=$((CHECKED + 1))
    case "$1" in
        ok)     [ -n "${BACKLOG_RECHECK_VERBOSE:-}" ] && printf '  ✓ %-5s %s\n' "$2" "$3" ;;
        broken) BROKEN=$((BROKEN + 1)); printf '  ✗ %-5s %s\n' "$2" "$3" ;;
        skip)   printf '  … %-5s %s\n' "$2" "$3" ;;
    esac
    return 0
}

echo "Перепроверка закрытых пунктов долга"

# --- D7: лог инжектов без нечитаемых строк ------------------------------------
# Закрыт разовой чисткой (8508 → 8335). Писатель чинён отдельно, но регрессия санитизации
# вернула бы битые строки молча — счётчик в metrics.md увидит их только при следующем Stop.
LOG="$STATE/injection-log.jsonl"
if [ ! -f "$LOG" ]; then
    report skip "D7" "лога инжектов нет — проверять нечего"
elif ! command -v jq >/dev/null 2>&1; then
    report skip "D7" "нет jq"
else
    _total=$(grep -c '' "$LOG" 2>/dev/null || echo 0)
    _valid=$({ jq -rR 'fromjson? // empty | 1' "$LOG" 2>/dev/null || true; } | grep -c '' || true)
    _bad=$(( _total - _valid ))
    if [ "$_bad" -eq 0 ]; then
        report ok "D7" "лог инжектов: $_total строк, все разбираются"
    else
        report broken "D7" "в логе инжектов снова $_bad нечитаемых строк из $_total"
    fi
fi

# --- D12: двусторонние ссылки кейс ↔ паттерн ----------------------------------
# Закрыт восстановлением 22 ссылок. Держится тестом test_knowledge_link_symmetry.py,
# но тот гоняется только вместе с набором mcp — здесь дешёвая независимая проверка.
if [ ! -d "$LESSONS" ]; then
    report skip "D12" "базы знаний нет"
else
    _asym=$(python3 - "$LESSONS" <<'PY' 2>/dev/null || echo "?"
import re, sys, pathlib
d = pathlib.Path(sys.argv[1])
par = {p.name: p.read_text(errors="replace") for p in list(d.glob("pattern-*.md")) + list(d.glob("principle-*.md"))}
rx = re.compile(r"^\s*-\s*(confirms|specializes|extends|generalizes)\s*:\s*(\S+\.md)\s*$", re.M)
n = 0
for c in d.glob("case-*.md"):
    t = c.read_text(errors="replace")
    if "DEPRECATED" in t[:2000]:
        continue
    for _, tgt in rx.findall(t):
        tgt = tgt.split("/")[-1]
        if tgt in par and c.name not in par[tgt]:
            n += 1
print(n)
PY
)
    if [ "$_asym" = "0" ]; then
        report ok "D12" "односторонних ссылок нет"
    elif [ "$_asym" = "?" ]; then
        report skip "D12" "нет python3"
    else
        report broken "D12" "снова $_asym односторонних ссылок кейс → паттерн"
    fi
fi

# --- D27 / D14: поля origin и preceded_artifact описаны в спецификации ---------
# Закрыты правкой META.md. Регрессия возможна: install.sh перезаписывает рабочую копию
# из репозитория, и правка не в том направлении молча пропадает.
META="$REPO/knowledge/META.md"
if [ ! -f "$META" ]; then
    report broken "D27" "нет $META"
else
    _miss=""
    grep -q '^origin:' "$META" || _miss="$_miss origin"
    grep -q '^preceded_artifact:' "$META" || _miss="$_miss preceded_artifact"
    if [ -z "$_miss" ]; then
        report ok "D27" "origin и preceded_artifact описаны в META"
    else
        report broken "D27" "в META снова не описано:$_miss"
    fi
    if [ -f "$LESSONS/META.md" ] && ! cmp -s "$META" "$LESSONS/META.md"; then
        report broken "D27" "META в репозитории и в рабочей базе разошлись — правка откатится при установке"
    else
        report ok "D27" "META синхронизирован с рабочей базой"
    fi
fi

# --- D8: у скиллов на месте фразы автовызова ----------------------------------
# Закрыт возвратом фраз. Регрессия вероятна: их снова вырежут при подгонке под длину.
for pair in "entity:что ты знаешь о" "ingest:добавь в базу знаний"; do
    _sk="${pair%%:*}"; _needle="${pair#*:}"
    _f="$REPO/skills/$_sk/SKILL.md"
    if [ ! -f "$_f" ]; then
        report skip "D8" "нет $_f"
    elif grep -qF "$_needle" "$_f"; then
        report ok "D8" "$_sk: фраза автовызова на месте"
    else
        report broken "D8" "$_sk: из описания снова пропала фраза «${_needle}»"
    fi
done

# --- D13: блокер-уровень с проверяемыми сигналами -----------------------------
# Закрыт поднятием pattern-shell-portability. Регрессия: сигналы сотрут или сломают JSON,
# и блокер станет украшением в frontmatter.
_sp="$LESSONS/pattern-shell-portability.md"
if [ ! -f "$_sp" ]; then
    report skip "D13" "знания нет в рабочей базе"
elif ! grep -q '^blocker: true' "$_sp"; then
    report broken "D13" "pattern-shell-portability больше не блокер-уровня"
else
    _sig=$(python3 - "$_sp" <<'PY' 2>/dev/null || echo "?"
import json, re, sys, pathlib
t = pathlib.Path(sys.argv[1]).read_text(errors="replace")
m = re.search(r"detection_signals: \|\n((?:  .*\n)+)", t)
if not m:
    print("0"); raise SystemExit
try:
    print(len(json.loads("".join(l[2:] for l in m.group(1).splitlines(True)))))
except Exception:
    print("bad")
PY
)
    case "$_sig" in
        0)   report broken "D13" "у блокера пустые detection_signals — срабатывать нечему" ;;
        bad) report broken "D13" "detection_signals не разбираются как JSON" ;;
        "?") report skip   "D13" "нет python3" ;;
        *)   report ok     "D13" "блокер жив, сигналов: $_sig" ;;
    esac
fi

# --- Итог ---------------------------------------------------------------------
echo ""
if [ "$BROKEN" -eq 0 ]; then
    echo "Инвариантов проверено: $CHECKED, все держатся."
else
    echo "Инвариантов проверено: $CHECKED, ПЕРЕСТАЛИ ДЕРЖАТЬСЯ: $BROKEN."
    echo "Пункт, чей инвариант сломан, снова открыт — верни ему ☐ в BACKLOG.md."
    # Воскресшее закрытие — повод разбора (D202). Повторение дефекта ПОСЛЕ контрмеры есть
    # провал самой контрмеры, то есть сильнейший из поводов; прежде он проходил строкой
    # отчёта, и разбора «почему закрытие не удержалось» не требовалось ни от кого.
    _RC_LIB="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")/../hooks" 2>/dev/null && pwd)/root-cause-lib.sh"
    [ -f "$_RC_LIB" ] || _RC_LIB="$HOME/.claude/hooks/root-cause-lib.sh"
    if [ -f "$_RC_LIB" ]; then
        # shellcheck source=/dev/null
        . "$_RC_LIB"
        rc_note_event "${STATE_DIR:-$HOME/.claude/hooks/state}" "resurrected" \
            "инвариантов перестало держаться: $BROKEN"
    fi
fi
[ "$BROKEN" -eq 0 ]
