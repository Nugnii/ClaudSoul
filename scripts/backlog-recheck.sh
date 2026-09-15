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
UNPROVEN=0
CHECKED=0

# report СТАТУС ПУНКТ ТЕКСТ
report() {
    CHECKED=$((CHECKED + 1))
    case "$1" in
        ok)     [ -n "${BACKLOG_RECHECK_VERBOSE:-}" ] && printf '  ✓ %-5s %s\n' "$2" "$3" ;;
        broken) BROKEN=$((BROKEN + 1)); printf '  ✗ %-5s %s\n' "$2" "$3" ;;
        # «Нечем проверить» — ТРЕТЬЕ состояние, а не разновидность нарушения. До 10 сентября
        # 2026 оно шло каналом `broken`, и потребитель (knowledge-audit-digest.sh:460 считает
        # строки `^  ✗ `) объявлял владельцу «закрытие ОТКАТИЛОСЬ, верни пункту ☐». Повод: в
        # чистом окружении launchd нет PyYAML, разбор честно пометил все 341 родителя
        # «не прочитан», и сигнал старта сессии сказал неправду о мире — закрытие держалось.
        # Корень R6 из ROOTS.md: два состояния мира отвечали одним значением канала.
        # Молчать здесь тоже нельзя (род B): отказ прибора не есть чистота.
        unproven) UNPROVEN=$((UNPROVEN + 1)); printf '  ? %-5s %s\n' "$2" "$3" ;;
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
    _total=$(grep -c '' "$LOG" 2>/dev/null) || _total=0
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
    # Считает РАЗБОРОМ поля `source_cases`, а не вхождением имени в текст родителя
    # (D312). Прежний способ спрашивал `c.name not in par[tgt]`, а имя кейса лежит в
    # файле родителя и помимо `source_cases` — в `provenance_log.trigger_case`, в
    # `related`, в прозе. Замер 5 сентября 2026: подстрока давала 1 нарушение там, где
    # разбор даёт 18. Инвариант вынесен в `hooks/lib/link_symmetry.py`, чтобы у писателя
    # и у приборов был ОДИН ответ: две прежние копии совпадали дословно и ошибались
    # согласованно, то есть их независимость была мнимой.
    # Библиотека ищется там, где она бывает: в репозитории, рядом со скриптом и в
    # установке. Её ОТСУТСТВИЕ — не «чисто», а «не проверено»: неспособность прибора
    # ответить на свой вопрос выдавать за зелёный нельзя (D205, род B).
    _LS_LIB=""
    for _d in "$REPO/hooks/lib" "$(dirname "$0")/../hooks/lib" "$HOME/.claude/hooks/lib"; do
        if [ -f "$_d/link_symmetry.py" ]; then _LS_LIB="$_d"; break; fi
    done
    _asym=$(LIB_DIR="$_LS_LIB" python3 - "$LESSONS" <<'PY' 2>/dev/null || echo "?"
import os, sys
sys.path.insert(0, os.environ["LIB_DIR"])
import link_symmetry as ls
bad, unread = ls.asymmetric(sys.argv[1])
# «Не прочитано» называется отдельно и НЕ выдаётся за чистоту (род B).
print(f"{len(bad)} {len(unread)}")
PY
)
    _asym_bad=${_asym%% *}
    _asym_unread=${_asym##* }
    if [ -z "$_LS_LIB" ]; then
        report unproven "D12" "нет hooks/lib/link_symmetry.py — инвариант НЕ ПРОВЕРЕН"
    elif [ "$_asym" = "?" ]; then
        report skip "D12" "нет python3 или PyYAML — разобрать поле нечем"
    elif [ "$_asym_bad" != "0" ]; then
        report broken "D12" "снова $_asym_bad односторонних ссылок кейс → паттерн"
    elif [ "$_asym_unread" != "0" ]; then
        report unproven "D12" "$_asym_unread родителей не разобрать — чистота НЕ ПОДТВЕРЖДЕНА"
    else
        report ok "D12" "односторонних ссылок нет"
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

# --- D411: спайка по рёбрам ДАННЫХ не даёт спирали правок ----------------------
# Закрыт вердиктом: спайка из 17 узлов ЗАКОННА по устройству — общий журнал с несколькими
# писателями и читателями, а ребро «читает» идёт от журнала к механизму по потоку данных.
# Вердикт держится числом, а не словом: правка одного механизма спайки не должна тянуть
# ОТВЕТНУЮ правку соседа в ближайших трёх коммитах. Замер при закрытии: состав спайки 14
# файлов дерева, тронуты в 16 коммитах из 300, кандидат в спираль один, и осмотр показал
# разные предметы — настоящих спиралей ноль. Порог: больше одного кандидата.
# ПРОГРАММА ВЫНЕСЕНА ИЗ ПОДСТАНОВКИ. Heredoc внутри `$( … )` bash 5 разбирает иначе, чем
# bash 3.2: на раннере CI он потерял закрывающую скобку («command substitution: … ` || echo
# "?")'») и следом убил скрипт под `set -u` — «_SPIRAL: unbound variable», а с ним три
# соседних инварианта (прогон 34872897131, 14 сентября 2026). Локально дефект невоспроизводим:
# на этой машине bash 3.2. Форма ниже от версии оболочки не зависит.
_SPIRAL_PY=$(mktemp 2>/dev/null) || _SPIRAL_PY=""
if [ -n "$_SPIRAL_PY" ]; then
    cat > "$_SPIRAL_PY" <<'PYSPIRAL'
import json, os, subprocess, sys
# СОСТАВ СПАЙКИ ВЫВОДИТСЯ ИЗ КАРТЫ, а не перечисляется: перечень устарел бы в тот же день,
# когда спайка изменится, и инвариант молча судил бы вчерашний набор (род F). Берём самый
# большой кусок и оставляем в нём файлы дерева — журналы правками не двигают.
DATA = "mcp-server/visualization/project-graph-data.json"
try:
    g = json.load(open(DATA, encoding="utf-8"))
except (OSError, ValueError):
    print("?")
    sys.exit(0)
# Виды рёбер — ТЕ ЖЕ, что берёт режим --scc прибора карты: исполнение и данные. Первая
# редакция брала ВСЕ виды (пункт, описывает, знание) и выводила спайку из 70 файлов —
# предмет иной, и число вышло про другое (19 из 70 против 0 из 11).
KIND = ("зовёт", "использует", "пишет", "читает", "проверяет")
adj, radj = {}, {}
for e in g["edges"]:
    if not str(e.get("type", "")).startswith(KIND):
        continue
    adj.setdefault(e["source"], set()).add(e["target"])
    radj.setdefault(e["target"], set()).add(e["source"])
idx = {n["id"]: n for n in g["nodes"]}
seen, best = set(), set()
for start in idx:
    if start in seen:
        continue
    fwd, stack = {start}, [start]
    while stack:
        x = stack.pop()
        for y in adj.get(x, ()):
            if y not in fwd:
                fwd.add(y); stack.append(y)
    back, stack = {start}, [start]
    while stack:
        x = stack.pop()
        for y in radj.get(x, ()):
            if y not in back:
                back.add(y); stack.append(y)
    comp = fwd & back
    seen |= comp
    if len(comp) > len(best):
        best = comp
names = {idx[x]["key"] for x in best
         if idx[x].get("key") and os.path.exists(idx[x]["key"])}
if not names:
    print("?")
    sys.exit(0)
log = subprocess.run(["git", "log", "--format=%H", "-n", "300", "--name-only"],
                     capture_output=True, text=True).stdout
commits, cur = [], None
for line in log.splitlines():
    if len(line) == 40 and all(c in "0123456789abcdef" for c in line):
        cur = set(); commits.append(cur)
    elif line.strip() and cur is not None:
        cur.add(line.strip())
touched = sum(1 for c in commits if c & names)
spiral = 0
for i, c in enumerate(commits):
    a = c & names
    if len(a) != 1:
        continue
    for nxt in commits[max(0, i - 3):i]:
        b = nxt & names
        if b and b != a:
            spiral += 1
            break
print(f"{spiral} {touched}")
PYSPIRAL
    _SPIRAL=$( (cd "$REPO" 2>/dev/null && python3 "$_SPIRAL_PY" 2>/dev/null) || echo "?" )
    rm -f "$_SPIRAL_PY"
else
    _SPIRAL="?"
fi
if [ "$_SPIRAL" = "?" ]; then
    report unproven "D411" "нет python3 либо git — спираль правок НЕ ИЗМЕРЕНА"
else
    _sp_n=${_SPIRAL%% *}; _sp_t=${_SPIRAL##* }
    if [ "${_sp_t:-0}" -eq 0 ]; then
        report unproven "D411" "спайку не трогали ни разу за 300 коммитов — измерять нечего"
    elif [ "${_sp_n:-0}" -gt 1 ]; then
        report broken "D411" "ответных правок внутри спайки снова $_sp_n из $_sp_t — спираль появилась"
    else
        report ok "D411" "спайка данных законна: ответных правок $_sp_n из $_sp_t коммитов"
    fi
fi

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
# «Не проверено» называется ВСЕГДА и отдельной строкой — и при зелёном итоге тоже:
# невысказанная непроверенность читается как чистота (род B).
[ "${UNPROVEN:-0}" -gt 0 ] && \
    echo "Не проверено: $UNPROVEN — прибор не смог ответить на свой вопрос (это НЕ откат закрытия)."
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
