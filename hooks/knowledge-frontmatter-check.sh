#!/usr/bin/env bash
# knowledge-frontmatter-check.sh — PostToolUse[Bash|Write|Edit|MultiEdit]: битый YAML frontmatter и НЕПОЛНАЯ шапка записанного знания называются СРАЗУ, а не когда-нибудь при прогоне тестов; набор обязательных полей выводится из шаблона контура.
# en: PostToolUse on knowledge writes, shell edits included: reports broken YAML frontmatter and missing required fields right after a knowledge file is written; the required set is derived from the contour's template.
#
# Инцидент (2026-08-11). Строка `description: … это не ловит: он проверяет …` — валидный
# русский и невалидный YAML: двоеточие с пробелом внутри незакавыченного скаляра читается
# как вложенное отображение. Замер живой базы: 21 файл из 317, включая
# principle-affect-as-engineering и pattern-shell-portability.
#
# Почему это НЕ ловилось само:
#   · tests/test_frontmatter.py проверяет парсер на выдуманных строках и живую базу
#     не открывает — предмет теста «умеет ли парсер», предмет вопроса «парсится ли база»
#     (pattern-subject-of-measurement-mismatch);
#   · после v1.x парсер получил salvage битого YAML — файл больше не теряется целиком,
#     но списки (edges, source_cases, related, domain, tags) он не восстанавливает.
#     То есть СВЯЗИ ГРАФА исчезают тихо, а запись выглядит здоровой. Пластырь без
#     детектора сделал класс менее заметным, чем он был.
# Поймано было случайно — проверкой, которую можно было и не писать. Этот хук убирает
# случайность: уровень 3 embedded-ness (principle-knowledge-in-the-world).
#
# Покрытие — честно о потолке:
#   · есть python с PyYAML (venv ClaudSoul либо системный) → ПОЛНАЯ проверка парсером;
#   · нет → regex на доминирующий класс «незакавыченное двоеточие»: замер на живой базе
#     17 из 21 (81%). Остальные 4 — «while parsing a block mapping» / «while scanning for
#     the next token» — regex-режим пропустит, их ловит тест mcp-server на живой базе.
#
# ПРЕДМЕТ — ИЗМЕНЁННЫЙ ФАЙЛ, А НЕ ИМЯ ИНСТРУМЕНТА (D311). Платформа умеет отбирать хук
# только по имени инструмента, события «файл изменён» в её интерфейсе нет — и доступный
# отбор был принят за предмет. Оболочка правит те же файлы (heredoc, `sed`, короткий
# скрипт) и `file_path` не несёт, поэтому при matcher `Write|Edit|MultiEdit` молчание
# неотличимо от «проверять было нечего»: замер 5 сентября 2026 — два кейса записаны
# `cat > … <<EOF`, проверка не срабатывала ни разу, а битый YAML доживал до прогона
# тестов mcp (которые в CI ещё и пропускаются, D313). Знание о роде лежало в базе с
# 27 августа: `case-2026-08-27-tool-name-detection-blind-to-work-mode`.
# Дробь на 5 сентября 2026: из 7 хуков, объявляющих предметом изменение файла, 3 стояли
# без `Bash` в matcher.
# Адреса у оболочки нет, поэтому предметом становится база, а целями — файлы НОВЕЕ
# отметки прохода; сторож `find` стоит доли миллисекунды и отсекает вызовы, при которых
# ничего не менялось (тот же приём у соседа `knowledge-link-symmetry.sh`).
#
# Input  (stdin): {session_id, tool_name, tool_input} (PostToolUse JSON)
# Output (stdout): {hookSpecificOutput:{hookEventName, additionalContext}} либо пусто
# Exit:  always 0 (degrade gracefully).

set -uo pipefail

PATHS_LIB="${PATHS_LIB:-$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/paths-lib.sh}"
if [ -f "$PATHS_LIB" ]; then
    # shellcheck source=/dev/null
    source "$PATHS_LIB"
else
    : "${LESSONS_DIR:=$HOME/.claude/global-lessons}"
    : "${CLAUDSOUL_ROOT:=$HOME/My Project/ClaudSoul}"
fi

command -v jq >/dev/null 2>&1 || exit 0


command -v jq >/dev/null 2>&1 || exit 0

INPUT=$(cat)
[ -z "$INPUT" ] && exit 0

TOOL_NAME=$(printf '%s' "$INPUT" | jq -r '.tool_name // ""' 2>/dev/null)
case "$TOOL_NAME" in
    Write|Edit|MultiEdit|Bash) ;;
    *) exit 0 ;;
esac

# ── Цели: названный адрес либо файлы, изменившиеся с прошлого прохода ─────────
STAMP="${CLAUDSOUL_STATE_DIR:-${STATE_DIR:-$HOME/.claude/hooks/state}}/frontmatter-scan.stamp"
TARGETS=()
if [ "$TOOL_NAME" = "Bash" ]; then
    [ -d "$LESSONS_DIR" ] || exit 0
    # ПЕРВЫЙ вызов заводит отметку и молчит: всё, что старше её, изменено не этим ходом,
    # и проходить базу целиком здесь нечестно вдвойне — это и не наше событие, и цена
    # прохода по 300+ файлам на КАЖДОЙ команде оболочки. НАЗВАННЫЙ ПРЕДЕЛ: битое, попавшее
    # в базу до появления отметки, ловит тест живой базы в mcp-server. Условие снятия:
    # предел уйдёт, если у хука появится вход со списком реально изменённых файлов.
    if [ ! -f "$STAMP" ]; then
        mkdir -p "$(dirname "$STAMP")" 2>/dev/null && : > "$STAMP" 2>/dev/null
        exit 0
    fi
    while IFS= read -r _f; do
        [ -n "$_f" ] && TARGETS+=("$_f")
    done < <(find "$LESSONS_DIR" -maxdepth 1 -name '*.md' -newer "$STAMP" -print 2>/dev/null)
    # Отметка сдвигается и когда проверять было нечего: «прошёл и не нашёл» — тоже
    # результат прохода. Сдвиг ДО проверки, а не после: цели уже собраны, и повторный
    # проход по ним дал бы вторую тревогу о том же файле, а не новую находку.
    : > "$STAMP" 2>/dev/null || true
    [ ${#TARGETS[@]} -gt 0 ] || exit 0
else
    FILE_PATH=$(printf '%s' "$INPUT" | jq -r '.tool_input.file_path // ""' 2>/dev/null)
    [ -z "$FILE_PATH" ] && exit 0
    TARGETS=("$FILE_PATH")
fi

# Только знания: *.md внутри базы. Черновики (_drafts) и META.md — не трогаем.
KEPT=()
for _t in "${TARGETS[@]}"; do
    [ -f "$_t" ] || continue
    case "$_t" in
        "$LESSONS_DIR"/*.md) ;;
        *) continue ;;
    esac
    case "$(basename "$_t")" in
        _*|META.md) continue ;;
    esac
    KEPT+=("$_t")
done
[ ${#KEPT[@]} -gt 0 ] || exit 0

# Дельта знаний — в реестр сессий (D258). Поля `knowledge_delta.created`/`updated`
# объявлены схемой реестра, а вызов `sr_update_knowledge` до 2 сентября 2026 стоял ТОЛЬКО
# в текстовых шаблонах скиллов (`skills/learn/references/case-template.md`,
# `skills/retro/references/promotion-rules.md`) — уровень 1 embedded-ness, инструкция
# агенту. Замер: непустой `created` в 58 записях из 3622 (1,6%). Событие «файл знания
# записан» наблюдаемо здесь, и писателем становится тот, кто его видит.
# Стоит ДО проверки frontmatter намеренно: знание записано независимо от того, валиден ли
# его YAML, и пропуск битого занизил бы счёт ровно на самых интересных случаях.
# НАЗВАННЫЙ ПРЕДЕЛ: created/updated различаются ПО ИНСТРУМЕНТУ (Write → created,
# Edit/MultiEdit/Bash → updated). `Write` поверх существующего знания зачтётся как created,
# а НОВОЕ знание, записанное оболочкой, — как updated: событие «файл существовал до вызова»
# на PostToolUse не наблюдаемо ни в одном из режимов. Из двух неточностей выбрана слабая:
# ошибочный `created` завышает счёт новых знаний, ошибочный `updated` — нет.
# Условие снятия: появится вход, несущий состояние файла ДО вызова (PreToolUse-парная
# запись) — различать по нему.
case "$TOOL_NAME" in
    Write) _KD_ACTION=created ;;
    *)     _KD_ACTION=updated ;;
esac
(
    SR_LIB="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" 2>/dev/null && pwd)/session-registry-lib.sh"
    [ -f "$SR_LIB" ] || SR_LIB="$HOME/.claude/hooks/session-registry-lib.sh"
    if [ -f "$SR_LIB" ]; then
        SR_OVERRIDE_SESSION_ID=$(printf '%s' "$INPUT" | jq -r '.session_id // ""' 2>/dev/null)
        export SR_OVERRIDE_SESSION_ID
        # shellcheck source=/dev/null
        if . "$SR_LIB"; then
            for _k in "${KEPT[@]}"; do
                sr_update_knowledge "$_KD_ACTION" "$(basename "$_k")"
            done
        fi
    fi
) 2>/dev/null || true

# Нет frontmatter вовсе — не наш случай (бывают справочные файлы без него).
CHECK=()
for _k in "${KEPT[@]}"; do
    [ "$(head -n 1 "$_k")" = "---" ] && CHECK+=("$_k")
done
[ ${#CHECK[@]} -gt 0 ] || exit 0

# ── Режим 1: полная проверка парсером, если есть python с PyYAML ──────────────
PY=""
# Явно названный интерпретатор ОТМЕНЯЕТ поиск, а не встаёт в его середину. Иначе
# переменная не управляет режимом: до 2026-08-11 проверка запасного пути (T2) думала,
# что отключает python подстановкой несуществующего пути, а хук всё равно доходил до
# системного `python3` — и четыре дня утверждала про regex-режим, исполняя парсерный.
# Красным это стало не от правки кода, а от среды: системный python3 обзавёлся PyYAML.
if [ -n "${CLAUDSOUL_PYTHON:-}" ]; then
    _py_candidates=("$CLAUDSOUL_PYTHON")
else
    _py_candidates=("$CLAUDSOUL_ROOT/mcp-server/.venv/bin/python" python3)
fi
for candidate in "${_py_candidates[@]}"; do
    [ -n "$candidate" ] || continue
    command -v "$candidate" >/dev/null 2>&1 || [ -x "$candidate" ] || continue
    if "$candidate" -c 'import yaml' >/dev/null 2>&1; then
        PY="$candidate"
        break
    fi
done

MSG=""
add() { MSG="${MSG}${MSG:+
}$1"; }

if [ -n "$PY" ]; then
    # Один процесс на ВЕСЬ список: цели считаются пачкой, и цена не растёт по числу
    # запусков интерпретатора.
    # ПОЛНОТА ШАПКИ (D347, 12 сентября 2026). Обязательные поля выводятся из шаблона своего
    # контура (плейсхолдеры `[…]`, `a|b`, `YYYY`, `1-5`), у операционного контура — плюс блок
    # «# Обязательные» knowledge/META.md. Перечня имён в коде нет намеренно: перечень был бы
    # родом L (у двух контуров наборы разные). Замер до починки: 224 записи из 415 без
    # какого-либо обязательного поля (source_session 213 — его не было в общем шаблоне,
    # intensity 56, source_cases 27, name/description 4); неполная запись жила до случайной
    # находки — 5 из 363 нашлись 7 сентября глазом.
    REPORT=$(CLAUDSOUL_ROOT="${CLAUDSOUL_ROOT:-}" "$PY" - "${CHECK[@]}" <<'PY_CHECK' 2>/dev/null
import sys, os, re, yaml
ROOT = os.environ.get("CLAUDSOUL_ROOT", "")
def _placeholders(tmpl):
    req = []
    try:
        body = open(tmpl, encoding="utf-8").read().split("---")[1]
    except (OSError, IndexError):
        return None
    for line in body.splitlines():
        m = re.match(r"^([a-z_]+):\s*(.*)$", line)
        if not m:
            continue
        v = m.group(2).split("#")[0].strip()
        if (v.startswith("[") and v.endswith("]") and v != "[]") or "|" in v or "YYYY" in v or re.fullmatch(r"\d+-\d+", v):
            req.append(m.group(1))
    return req
def required_from_template(name):
    # обязательные поля выводятся из шаблона контура, а не из перечня в коде
    if not ROOT:
        return None, None
    if re.match(r"(case|pattern|principle)-", name):
        req = _placeholders(os.path.join(ROOT, "templates", "knowledge.md.tmpl"))
        if req is None:
            return None, None
        try:
            meta = open(os.path.join(ROOT, "knowledge", "META.md"), encoding="utf-8").read()
            blk = re.search(r"^# Обязательные\n(.*?)^# ", meta, re.S | re.M)
            if blk:
                req += re.findall(r"^([a-z_]+):", blk.group(1), re.M)
        except OSError:
            pass
        return sorted(set(req)), "templates/knowledge.md.tmpl + knowledge/META.md «Обязательные»"
    for c in ("entity", "fact", "relation"):
        if name.startswith(c + "-"):
            req = _placeholders(os.path.join(ROOT, "templates", c + ".md.tmpl"))
            return (sorted(set(req)) if req is not None else None), "templates/%s.md.tmpl" % c
    return None, None
for path in sys.argv[1:]:
    name = os.path.basename(path)
    try:
        raw = open(path, encoding="utf-8", errors="replace").read()
    except OSError:
        # Отказ чтения называется, а не подставляет «здоров» (род B реестра дефектов).
        print("UNREAD|" + name + "||")
        continue
    parts = raw.split("---", 2)
    if len(parts) < 3:
        continue
    try:
        meta = yaml.safe_load(parts[1])
    except yaml.YAMLError as e:
        mark = getattr(e, "problem_mark", None)
        where = ("строка %d, колонка %d" % (mark.line + 1, mark.column + 1)) if mark else "место не определено"
        print("BROKEN|" + name + "|" + str(e).splitlines()[0].strip() + "|" + where)
        continue
    # YAML валиден — отдельно предупреждаем о пустом frontmatter (тоже потеря метаданных).
    if not isinstance(meta, dict) or not meta:
        print("EMPTY|" + name + "||")
        continue
    req, src = required_from_template(name)
    if req:
        missing = [k for k in req if k not in meta]
        if missing:
            print("INCOMPLETE|" + name + "|" + ", ".join(missing) + "|" + src)
    # ФОРМА РЕБРА (D1032, 23 октября 2026): элемент `edges` — ПАРА «вид: цель», один ключ, цель
    # строкой. Словарь {type, target}, пара из двух ключей, список целей и отображение вместо
    # списка валидны как YAML и потому проходили парсер, а разборщик связей
    # (hooks/lib/link_symmetry.py) таких рёбер не читает — ребро молча выпадало из графа:
    # 22 ребра в 17 файлах на 23 октября, два из них без встречной ссылки у родителя.
    edges = meta.get("edges")
    if edges not in (None, []):
        wrong = []
        if not isinstance(edges, list):
            wrong.append("edges — не список, а %s" % type(edges).__name__)
        else:
            for i, it in enumerate(edges, 1):
                if not isinstance(it, dict):
                    wrong.append("элемент %d — %s, а не пара" % (i, type(it).__name__))
                elif len(it) != 1:
                    wrong.append("элемент %d — %d ключа (%s), а не пара «вид: цель»" % (i, len(it), ", ".join(map(str, it))))
                elif not isinstance(list(it.values())[0], str) or not list(it.values())[0].strip():
                    wrong.append("элемент %d — цель не строкой (%s)" % (i, type(list(it.values())[0]).__name__))
        if wrong:
            print("EDGEFORM|" + name + "|" + "; ".join(wrong[:3]) + ("; …" if len(wrong) > 3 else "") + "|")
PY_CHECK
)
    while IFS='|' read -r KIND NAME WHY WHERE; do
        case "$KIND" in
            BROKEN)
                add "⚠️ Битый YAML frontmatter: ${NAME}
   ${WHY} (${WHERE}).
   Знание НЕ потеряно (парсер достаёт скаляры построчно), но СПИСКИ — edges,
   source_cases, related, domain, tags — не читаются вовсе: связи графа исчезают тихо.
   Частая причина: двоеточие с пробелом внутри незакавыченного значения
   (\`description: … не ловит: он проверяет …\`). Лечится кавычками вокруг значения.
   Почини сейчас и перечитай файл — иначе запись выглядит здоровой, а связей у неё нет."
                ;;
            EMPTY)
                add "⚠️ Пустой frontmatter: ${NAME} — метаданных нет, знание не попадёт ни в один фильтр."
                ;;
            INCOMPLETE)
                add "⚠️ Неполная шапка: ${NAME} — нет полей: ${WHY}.
   Обязательные поля выводятся из шаблона контура (${WHERE}); допиши их сейчас:
   неполная запись живёт незамеченной до случайной находки (D347). Значение неизвестно —
   оставь пустым (\"\" или []), не выдумывай."
                ;;
            UNREAD)
                add "⚠️ ${NAME} — файл не прочитан, frontmatter НЕ ПРОВЕРЕН."
                ;;
            EDGEFORM)
                add "⚠️ Ребро не парой «вид: цель»: ${NAME} — ${WHY}.
   Форма (knowledge/META.md § Связи): \`- confirms: pattern-x.md\`, пояснение — комментарием.
   Словарь {type: …, target: …}, пару из двух ключей и список целей разборщик связей
   (hooks/lib/link_symmetry.py) не читает: для обхода графа такого ребра нет, встречная
   ссылка у родителя не пишется (D1032). Почини сейчас — YAML при этом валиден, и позже
   этого не заметит никто."
                ;;
        esac
    done <<< "$REPORT"
else
    # ── Режим 2 (без PyYAML): regex на доминирующий класс ─────────────────────
    # Ловит верхнеуровневый скаляр без кавычек/блока, в значении которого есть ": ".
    # Потолок известен и назван в шапке: 17 из 21 на замере живой базы.
    # `nextfile` здесь НЕ используется намеренно (pattern-shell-portability): его нет в
    # части реализаций awk, а роль его берёт флаг `found`, сбрасываемый на FNR == 1.
    SUSPECT=$(awk '
        FNR == 1 { n = 0; found = 0 }            # счётчики пофайлово: целей бывает больше одной
        /^---$/ { n++; next }
        n != 1 { next }
        found >= 3 { next }
        # Разделитель ключа отрезаем и ищем ": " ТОЛЬКО в значении — иначе условие
        # срабатывает на самом разделителе, то есть на каждой строке подряд.
        match($0, /^[A-Za-z_][A-Za-z0-9_-]*:[ \t]+/) {
            val = substr($0, RSTART + RLENGTH)
            if (val ~ /^["'"'"'|>[{]/) next          # закавычено или блок/список — YAML разберёт
            # Комментарий YAML отбрасывает, а двоеточия в нём безвредны: без этой срезки
            # строки вида `instrument_verdict: inexpressible   # …по конструкции: …` давали
            # ложную тревогу (замер: 6 здоровых файлов из 317).
            sub(/[ \t]+#.*/, "", val)
            if (val ~ /: /) {
                # Печатаем ключ, а не кусок значения: обрезка по байтам рубит UTF-8 посередине.
                key = $0; sub(/:.*/, "", key)
                base = FILENAME; sub(/.*\//, "", base)
                print "   " base ": строка " FNR ", ключ «" key "»"
                found++
            }
        }
    ' "${CHECK[@]}" 2>/dev/null)

    # Форма ребра в запасном режиме — по строке: элемент списка, начинающийся с `{type` или `type:` (D1032).
    EDGESUSPECT=$(awk '
        FNR == 1 { n = 0; inedges = 0 }
        /^---$/ { n++; next }
        n != 1 { next }
        /^edges:/ { inedges = 1; if ($0 ~ /\{[ \t]*type[ \t]*:/) { base = FILENAME; sub(/.*\//, "", base); print "   " base ": строка " FNR } ; next }
        inedges && /^[A-Za-z_]/ { inedges = 0 }
        inedges && /^[ \t]+-[ \t]*(\{[ \t]*type[ \t]*:|type[ \t]*:)/ { base = FILENAME; sub(/.*\//, "", base); print "   " base ": строка " FNR }
    ' "${CHECK[@]}" 2>/dev/null)
    if [ -n "$EDGESUSPECT" ]; then
        add "⚠️ Ребро не парой «вид: цель» (форма {type, target} или пара из двух ключей):
${EDGESUSPECT}
   Форма: \`- confirms: pattern-x.md\` (knowledge/META.md § Связи). Разборщик связей такое ребро не
   читает — для обхода графа его нет (D1032)."
    fi
    if [ -n "$SUSPECT" ]; then
        add "⚠️ Возможен битый YAML frontmatter:
   Незакавыченное значение с двоеточием — YAML прочитает его как вложенное отображение
   и потеряет СПИСКИ (edges, source_cases, related, domain, tags), оставив вид здоровой записи:
${SUSPECT}
   Лечится кавычками вокруг значения. (Проверка неполная: PyYAML недоступен — доступен был
   бы, проверка шла бы парсером. Полный контроль — тест live-базы в mcp-server.)"
    fi
fi

[ -n "$MSG" ] || exit 0
jq -n --arg ctx "$MSG" \
    '{hookSpecificOutput:{hookEventName:"PostToolUse", additionalContext:$ctx}}' 2>/dev/null
exit 0
