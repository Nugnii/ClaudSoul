#!/usr/bin/env bash
# drift-check.sh — расхождение между тем, что лежит в репозитории, и тем, что реально работает.
#
# Зачем отдельным файлом. В v1.13.1 детектор был встроен в run_all.sh и покрывал одну пару
# из шести. Обобщение до шести пар — это уже логика, которую саму нужно проверять, а
# встроенную в раннер логику проверить нечем: тест не может подменить ей вход.
#
# Что случилось с прежней версией (найдено при обобщении, v1.14.2). Она вычисляла путь к
# источнику как `cd "$(dirname "$0")/.."` ПОСЛЕ того, как раннер уже сделал `cd` в каталог
# тестов. При вызове `bash hooks/tests/run_all.sh` из корня репозитория относительный путь
# складывался сам с собой, `cd` падал, путь выходил пустой, шаблон не находил ничего,
# цикл не выполнялся ни разу — и печаталось утвердительное «репозиторий и установленное
# совпадают». Проверка, построенная против закольцовки, сама прошла вхолостую тем же
# способом: ноль сравнений неотличим от нуля расхождений.
#
# Отсюда главное правило этого файла: **пара, в которой сравнили ноль файлов, — это не
# «совпадает», а сломанная проверка**. Такой исход называется BROKEN и виден отдельно от OK.
#
# Направление сравнения — репозиторий → установленное. Обратное (файлы, живущие только в
# установленном) сознательно не здесь: их считает `test_install_drift.sh` как LIVE_UNTRACKED,
# и часть из них легитимна — клиентские хуки конкретной машины.
#
# Формат вывода, по строке на пару:
#   СТАТУС|метка|сколько_сравнено|сколько_разошлось|подробности
#   OK      — сравнили хотя бы один файл, различий нет
#   DRIFT   — есть различия, подробности перечисляют имена
#   ABSENT  — установленной стороны нет вовсе (машина без install.sh) — вопрос не стоит
#   BROKEN  — проверка не смогла ничего сравнить; это отказ проверки, а не успех
#
# Код возврата: 0 — всё OK/ABSENT, 1 — есть DRIFT, 2 — есть BROKEN.

set -uo pipefail

# Корень репозитория. Считается от физического расположения ЭТОГО файла и не зависит от
# того, из какого каталога и каким путём его позвали — ровно та ошибка, что описана выше.
_self_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" 2>/dev/null && pwd -P)
REPO="${CLAUDSOUL_REPO:-$(cd -- "$_self_dir/../.." 2>/dev/null && pwd -P)}"
CLAUDE_HOME="${CLAUDE_HOME:-$HOME/.claude}"

# Корень обязан быть похож на ClaudSoul. Иначе все шесть пар выродятся в пустые шаблоны и
# напечатают шесть зелёных нулей — молчаливое «всё хорошо» от проверки, которая не нашла
# даже собственный репозиторий.
if [ -z "$REPO" ] || [ ! -f "$REPO/install.sh" ] || [ ! -d "$REPO/hooks" ]; then
    printf 'BROKEN|корень репозитория|0|0|не разрешился в дерево ClaudSoul: "%s"\n' "$REPO"
    exit 2
fi

_checked_total=0

# Установка на машине есть, если ХОТЬ ОДИН приёмник наполнен из репозитория. Считается
# один раз, до первой пары: иначе улика зависит от порядка пар, и первая пара судит по
# пустому счётчику. Каталог знаний в перечень не входит намеренно — `uninstall.sh`
# оставляет его всегда («база знаний не удаляется никогда»), и его наличие об установке
# не говорит.
_install_present=0
for _probe in "$CLAUDE_HOME"/hooks/*.sh "$CLAUDE_HOME"/commands/*/SKILL.md \
              "$CLAUDE_HOME"/bin/*.sh "$CLAUDE_HOME"/templates/*.tmpl \
              "$CLAUDE_HOME/statusline-claudsoul.sh" "$CLAUDE_HOME/CLAUDE.md"; do
    if [ -f "$_probe" ]; then _install_present=1; break; fi
done
_drift_total=0
_broken_total=0

# _emit СТАТУС метка сравнено разошлось подробности
_emit() {
    printf '%s|%s|%s|%s|%s\n' "$1" "$2" "$3" "$4" "$5"
    _checked_total=$((_checked_total + $3))
    [ "$1" = "DRIFT" ] && _drift_total=$((_drift_total + 1))
    [ "$1" = "BROKEN" ] && _broken_total=$((_broken_total + 1))
    return 0
}

# _classify метка сравнено разошлось имена цель
# Единственное место, где число сравнений превращается в статус. Отдельной функцией, потому
# что правило «каталог есть, но ни одного файла в нём нет — это не расхождение, а отсутствие
# установки» пришлось вносить дважды: логика была продублирована в общем помощнике и в ветке
# скиллов, и во второй копии я её забыл. Дубликат классификации гарантирует, что следующее
# правило тоже будет применено не везде.
# _absent_or_drift метка подробности
# «Приёмника нет» значит разное в зависимости от того, есть ли на машине установка вообще.
# Улика глобальная (`_checked_total`), поэтому и решение одно на всех — шесть рукописных
# `_emit ABSENT` были шестью копиями решения, и правка дошла бы опять не до каждой.
_absent_or_drift() {
    if [ "$_install_present" -eq 1 ]; then
        _emit DRIFT "$1" 0 1 "$2 (установка на машине есть)"
    else
        _emit ABSENT "$1" 0 0 "$2"
    fi
}

_classify() {
    _c_lbl="$1"; _c_n="$2"; _c_d="$3"; _c_names="$4"; _c_dst="$5"; _c_miss="${6:-}"
    if [ -z "$_c_miss" ]; then
        _emit BROKEN "$_c_lbl" 0 0 "классификация позвана без счёта отсутствующих — сама проверка неполна"
        return 0
    fi
    if [ "$_c_n" -eq 0 ]; then
        _emit BROKEN "$_c_lbl" 0 0 "сравнили ноль файлов — сравнивать было нечего"
    elif [ "$_c_miss" -eq "$_c_n" ] && [ "$_c_n" -gt 1 ] && [ "$_install_present" -eq 0 ]; then
        # ABSENT утверждает «установки на машине нет». Утверждение глобальное, поэтому и
        # улика глобальная: НИ ОДНА прежняя пара ничего не сверила. Раньше вердикт выносился
        # покадрово, и пара без единого файла объявляла машину неустановленной, пока соседняя
        # строка того же вывода показывала сверенные файлы.
        _emit ABSENT "$_c_lbl" 0 0 "каталог $_c_dst есть, но ни одного из $_c_n файлов в нём нет — установка не выполнялась"
    elif [ "$_c_d" -gt 0 ]; then
        _emit DRIFT "$_c_lbl" "$_c_n" "$_c_d" "$_c_names"
    else
        _emit OK "$_c_lbl" "$_c_n" 0 ""
    fi
}

# _cmp_tree метка src_каталог dst_каталог шаблон [префикс_имени]
# Сравнивает содержимое пофайлово. Права и время намеренно не сравниваются: install.sh
# делает chmod +x, а cp обновляет mtime — по ним пара расходится всегда и сигнал обесценится.
_cmp_tree() {
    _lbl="$1"; _src="$2"; _dst="$3"; _pat="$4"; _pfx="${5:-}"
    # `_miss` отделён от `_d`: «файла нет» и «файл есть, но другой» — разные факты, и
    # ABSENT выводится ТОЛЬКО из первого. Пока они складывались в одно число, пара, где
    # все файлы отличаются по содержимому, печаталась как «установка не выполнялась» —
    # утверждение, опровергаемое `ls` того же каталога, и с кодом возврата 0.
    _n=0; _d=0; _miss=0; _names=""
    if [ ! -d "$_src" ]; then
        _emit BROKEN "$_lbl" 0 0 "нет каталога-источника: $_src"
        return 0
    fi
    if [ ! -d "$_dst" ]; then
        _absent_or_drift "$_lbl" "не установлено: $_dst"
        return 0
    fi
    for _f in "$_src"/$_pat; do
        [ -f "$_f" ] || continue
        _b=$(basename "$_f")
        _n=$((_n + 1))
        if [ ! -f "$_dst/$_b" ]; then
            _miss=$((_miss + 1)); _d=$((_d + 1)); _names="$_names $_pfx$_b"
        elif ! cmp -s "$_f" "$_dst/$_b"; then
            _d=$((_d + 1)); _names="$_names $_pfx$_b"
        fi
    done
    _classify "$_lbl" "$_n" "$_d" "$_names" "$_dst" "$_miss"
}

# --- 1. Хуки верхнего уровня (эталон v1.13.1) ---
_cmp_tree "хуки" "$REPO/hooks" "$CLAUDE_HOME/hooks" "*.sh"

# --- 2. Под-библиотеки хуков. Устанавливаются (install.sh), но детектором не покрывались.
# Шаблон * а не *.sh: в lib/ есть и .py, один из них зовётся на каждый Stop.
_cmp_tree "библиотеки хуков" "$REPO/hooks/lib" "$CLAUDE_HOME/hooks/lib" "*" "lib/"

# --- 3. Скиллы: skills/<имя>/ → ~/.claude/commands/<имя>/ ---
# Обход со стороны источника: в commands/ живут и чужие скиллы, не из ClaudSoul.
_skill_n=0; _skill_d=0; _skill_miss=0; _skill_names=""
if [ ! -d "$REPO/skills" ]; then
    _emit BROKEN "скиллы" 0 0 "нет каталога-источника: $REPO/skills"
elif [ ! -d "$CLAUDE_HOME/commands" ]; then
    _absent_or_drift "скиллы" "не установлено: $CLAUDE_HOME/commands"
else
    for _d_src in "$REPO"/skills/*/; do
        [ -d "$_d_src" ] || continue
        _name=$(basename "$_d_src")
        for _f in "$_d_src"SKILL.md "$_d_src"references/*.md; do
            [ -f "$_f" ] || continue
            _rel="${_f#"$_d_src"}"
            _skill_n=$((_skill_n + 1))
            _tgt="$CLAUDE_HOME/commands/$_name/$_rel"
            if [ ! -f "$_tgt" ]; then
                _skill_miss=$((_skill_miss + 1)); _skill_d=$((_skill_d + 1))
                _skill_names="$_skill_names $_name/$_rel"
            elif ! cmp -s "$_f" "$_tgt"; then
                _skill_d=$((_skill_d + 1)); _skill_names="$_skill_names $_name/$_rel"
            fi
        done
    done
    _classify "скиллы" "$_skill_n" "$_skill_d" "$_skill_names" "$CLAUDE_HOME/commands" "$_skill_miss"
fi

# --- 4. bin: ожидаемый набор выводится ИЗ install.sh, а не из ls каталога ---
# Единица установки здесь — именованный файл, а не каталог. bin/claudsoul.js в установку не
# входит намеренно: это точка входа npm-пакета claudsoul, у него другой канал доставки
# (см. docs/decisions.md). Сравнение по ls дало бы вечное ложное расхождение на нём.
_bin_n=0; _bin_d=0; _bin_miss=0; _bin_names=""
_bin_expected=$(grep -oE 'bin/[A-Za-z0-9._-]+\.sh' "$REPO/install.sh" 2>/dev/null | sed 's|^bin/||' | sort -u)
if [ -z "$_bin_expected" ]; then
    _emit BROKEN "bin" 0 0 "install.sh не называет ни одного файла bin/ — набор для сравнения пуст"
elif [ ! -d "$CLAUDE_HOME/bin" ]; then
    _absent_or_drift "bin" "не установлено: $CLAUDE_HOME/bin"
else
    for _b in $_bin_expected; do
        [ -f "$REPO/bin/$_b" ] || continue
        _bin_n=$((_bin_n + 1))
        if [ ! -f "$CLAUDE_HOME/bin/$_b" ]; then
            _bin_miss=$((_bin_miss + 1)); _bin_d=$((_bin_d + 1)); _bin_names="$_bin_names bin/$_b"
        elif ! cmp -s "$REPO/bin/$_b" "$CLAUDE_HOME/bin/$_b"; then
            _bin_d=$((_bin_d + 1)); _bin_names="$_bin_names bin/$_b"
        fi
    done
    _classify "bin" "$_bin_n" "$_bin_d" "$_bin_names" "$CLAUDE_HOME/bin" "$_bin_miss"
fi

# --- 5. Глобальные правила: только область между маркерами ---
# Снаружи маркеров живёт содержимое собеседника, его расхождением считать нельзя.
# Границы и способ записи блока берутся из той же библиотеки, что его и пишет.
_rules_src="$REPO/rules/CLAUDE.md"
_rules_dst="$CLAUDE_HOME/CLAUDE.md"
_merge_lib="$REPO/lib/claude-md-merge.sh"
if [ ! -f "$_rules_src" ] || [ ! -f "$_merge_lib" ]; then
    _emit BROKEN "правила" 0 0 "нет источника или библиотеки слияния: $_rules_src / $_merge_lib"
elif [ ! -f "$_rules_dst" ]; then
    _absent_or_drift "правила" "не установлено: $_rules_dst"
else
    # shellcheck source=/dev/null
    . "$_merge_lib"
    _mstart=$(grep -n -F "$CLAUDE_MD_MARKER_START" "$_rules_dst" 2>/dev/null | head -1 | cut -d: -f1)
    _mend=$(grep -n -F "$CLAUDE_MD_MARKER_END" "$_rules_dst" 2>/dev/null | head -1 | cut -d: -f1)
    if [ -z "$_mstart" ] || [ -z "$_mend" ]; then
        _emit BROKEN "правила" 0 0 "в установленном CLAUDE.md нет маркеров — сравнивать нечего"
    elif diff -q <(_cm_write_managed_block "$_rules_src") \
                 <(sed -n "${_mstart},${_mend}p" "$_rules_dst") >/dev/null 2>&1; then
        _emit OK "правила" 1 0 ""
    else
        _emit DRIFT "правила" 1 1 " rules/CLAUDE.md (область между маркерами)"
    fi
fi

# --- 6. Seed знаний: внешний скрипт + два файла, которые он не покрывает ---
# regen-seed.py --check сравнивает 23 генерируемых файла. META.md и source-tiers.md ведутся
# руками и стражу невидимы, поэтому сверяются здесь отдельно.
_seed_n=0; _seed_d=0; _seed_names=""
if ! command -v python3 >/dev/null 2>&1 || [ ! -f "$REPO/scripts/regen-seed.py" ]; then
    _emit BROKEN "seed знаний" 0 0 "нет python3 или scripts/regen-seed.py"
elif [ ! -d "$CLAUDE_HOME/global-lessons" ]; then
    _absent_or_drift "seed знаний" "не установлено: $CLAUDE_HOME/global-lessons"
elif [ -z "$(ls "$CLAUDE_HOME/global-lessons"/pattern-*.md "$CLAUDE_HOME/global-lessons"/principle-*.md 2>/dev/null)" ]; then
    # Каталог знаний есть, а seed в нём НЕТ. Это «не установлено», а не «отличается»:
    # `uninstall.sh` оставляет каталог всегда («база знаний не удаляется никогда»), и его
    # наличие об установке seed не говорит. То же разведение «нет» и «другое», что в
    # `_cmp_tree`, — и сюда оно, как обычно, не дошло само.
    _absent_or_drift "seed знаний" "не установлено: seed в $CLAUDE_HOME/global-lessons"
else
    _seed_n=$((_seed_n + 1))
    # Предмет пары — `$CLAUDE_HOME`, значит и внешнему сравнению он передаётся явно.
    # Без этого `regen-seed` смотрел в каталог запускающего, и пара отчитывалась о другом
    # объекте, чем заявляла.
    if ! CLAUDE_HOME="$CLAUDE_HOME" LESSONS_DIR="$CLAUDE_HOME/global-lessons" \
         python3 "$REPO/scripts/regen-seed.py" --check >/dev/null 2>&1; then
        _seed_d=$((_seed_d + 1)); _seed_names="$_seed_names knowledge/(генерируемые)"
    fi
    for _m in META.md source-tiers.md; do
        [ -f "$REPO/knowledge/$_m" ] || continue
        [ -f "$CLAUDE_HOME/global-lessons/$_m" ] || continue
        _seed_n=$((_seed_n + 1))
        cmp -s "$REPO/knowledge/$_m" "$CLAUDE_HOME/global-lessons/$_m" || {
            _seed_d=$((_seed_d + 1)); _seed_names="$_seed_names knowledge/$_m"
        }
    done
    if [ "$_seed_d" -gt 0 ]; then
        _emit DRIFT "seed знаний" "$_seed_n" "$_seed_d" "$_seed_names"
    else
        _emit OK "seed знаний" "$_seed_n" 0 ""
    fi
fi


# --- 7-я пара: РЕГИСТРАЦИЯ хуков (D55) -------------------------------------------
#
# Шесть пар выше сверяют ФАЙЛЫ. Но хук может лежать побайтово верным и при этом висеть
# на не том событии — или сразу на двух. `install.sh` сливает конфигурацию аддитивно
# (намеренно: чтобы не затирать хуки собеседника), поэтому запись УМЕЕТ добавляться и
# НЕ УМЕЕТ удаляться. Перенос `error-tracker` с PostToolUse на PreToolUse оставил старую
# регистрацию, и хук оказался зарегистрирован на обоих событиях сразу.
#
# Только называем, не чиним: в `settings.json` живут и чужие хуки, а сегодняшняя потеря
# 122 файлов выборки показала цену автоматического удаления по предположению.
_reg_n=0; _reg_d=0; _reg_names=""
_settings="$CLAUDE_HOME/settings.json"
if ! command -v python3 >/dev/null 2>&1 || ! command -v jq >/dev/null 2>&1; then
    _emit ABSENT "регистрация хуков" 0 0 "нужны python3 и jq"
elif [ ! -f "$_settings" ]; then
    _absent_or_drift "регистрация хуков" "не установлено: $_settings"
else
    _reg_out=$(python3 - "$REPO/install.sh" "$_settings" <<'REGPY'
import json, re, sys, pathlib

decl_src, live_src = pathlib.Path(sys.argv[1]), pathlib.Path(sys.argv[2])
m = re.search(r"HOOKS_CONFIG='(\{.*?\n\})'", decl_src.read_text(), re.S)
if not m:
    print("BROKEN|не разобран HOOKS_CONFIG"); raise SystemExit
declared, live = {}, {}
for store, doc in ((declared, json.loads(m.group(1))), (live, json.loads(live_src.read_text()))):
    for ev, matchers in (doc.get("hooks") or {}).items():
        for mm in matchers:
            for h in mm.get("hooks", []):
                cmd = h.get("command", "")
                g = re.search(r"hooks/([A-Za-z0-9_-]+\.sh)", cmd)
                if g:
                    store.setdefault(g.group(1), set()).add(ev)

ghosts, missing, ours = [], [], 0
for name, evs in live.items():
    if name not in declared:
        continue                      # чужой хук — не наше дело
    ours += 1
    extra = evs - declared[name]
    if extra:
        ghosts.append(f"{name}:{'+'.join(sorted(extra))}")

# Обратная сторона: хук объявлен в install.sh, файл установлен, а регистрации нет ни на
# одном событии — он не срабатывает никогда. Направление сверки объявлено «репозиторий →
# установленное», но цикл шёл по `live`, и объявленное-но-незарегистрированное в сравнение
# не попадало вовсе.
for name, evs in declared.items():
    if name not in live:
        missing.append(f"{name}:нет регистрации")
        continue
    # Сверка по паре «имя+событие», а не по одному имени. Прямая сторона (призраки) так и
    # шла, обратная смотрела только на имя: пока жива хоть одна регистрация хука, потеря
    # остальных была невидима. Многособытийных хуков в конфиге четыре, и у каждого из них
    # можно было потерять три события из четырёх при зелёной паре.
    lost = evs - live[name]
    if lost:
        missing.append(f"{name}:потеряны {'+'.join(sorted(lost))}")

# Число сравнений — НАШИ регистрации, а не все найденные. Прежде считался `len(live)`,
# включая отброшенные как чужие: любой чужой хук в settings.json гасил правило «ноль
# сравнений — BROKEN» и надувал `_checked_total`, отчего на машине БЕЗ установки соседние
# пары начинали кричать DRIFT «установка на машине есть».
_bad = ghosts + missing
print(f"{ours}|{'BAD' if _bad else 'OK'}|{' '.join(sorted(_bad))}")
REGPY
)
    case "$_reg_out" in
        BROKEN*) _emit BROKEN "регистрация хуков" 0 0 "${_reg_out#BROKEN|}" ;;
        *)
            _reg_n="${_reg_out%%|*}"
            _rest="${_reg_out#*|}"
            _reg_names="${_rest#*|}"
            # Порядок ветвей: «ноль сравнений» решается ПЕРВЫМ. Ноль наших регистраций —
            # это отказ проверки, а не находка в ней: сравнивать было нечего, и назвать
            # такое расхождением значит подменить BROKEN на DRIFT.
            if [ "${_reg_n:-0}" -eq 0 ]; then
                # Ноль сравнённых записей — это НЕ «совпадает». Ветка обходила `_classify`
                # и печатала OK при `settings.json` вида `{"hooks":{}}`: ни один хук не
                # висит ни на одном событии, а пара утверждает, что всё сошлось. Шапка
                # этого файла предупреждала ровно об этом — «дубликат классификации
                # гарантирует, что следующее правило будет применено не везде»; правило
                # BROKEN и оказалось применено не везде.
                # Ноль наших регистраций значит разное: на машине БЕЗ установки это
                # «не установлено», на установленной — отказ проверки. Улика та же
                # глобальная, что и у остальных приёмников.
                if [ "$_install_present" -eq 1 ]; then
                    _emit BROKEN "регистрация хуков" 0 0 "в settings.json нет ни одной НАШЕЙ регистрации, хотя установка на машине есть — сравнивать было нечего"
                else
                    _emit ABSENT "регистрация хуков" 0 0 "не установлено: ни одной нашей регистрации в $_settings"
                fi
            elif [ "${_rest%%|*}" = "BAD" ]; then
                _emit DRIFT "регистрация хуков" "${_reg_n:-0}" 1 "$_reg_names"
            else
                _emit OK "регистрация хуков" "${_reg_n:-0}" 0 ""
            fi
            ;;
    esac
fi

# --- 8. Шаблоны: templates/*.tmpl → ~/.claude/templates/ (D105) ---------------------
# Приёмник существовал с самого начала и пары не имел: install.sh его наполнял, а детектор
# не сравнивал никогда. Найден не глазами, а правилом — test_drift_pairs_cover_install.sh
# извлекает приёмники из install.sh и требует пару каждому.
_cmp_tree "шаблоны" "$REPO/templates" "$CLAUDE_HOME/templates" "*.tmpl"

# --- 9. Статусная строка: одиночный файл в корне ~/.claude (D105) --------------------
# Владелец-видимая поверхность (индикатор фазы ablation). Расхождение здесь означает, что
# показывается не то состояние, в котором система на самом деле.
_sl_src="$REPO/scripts/statusline-claudsoul.sh"
_sl_dst="$CLAUDE_HOME/statusline-claudsoul.sh"
if [ ! -f "$_sl_src" ]; then
    _emit BROKEN "статусная строка" 0 0 "нет источника: $_sl_src"
elif [ ! -f "$_sl_dst" ]; then
    _absent_or_drift "статусная строка" "не установлено: $_sl_dst"
elif cmp -s "$_sl_src" "$_sl_dst"; then
    _emit OK "статусная строка" 1 0 ""
else
    _emit DRIFT "статусная строка" 1 1 " scripts/statusline-claudsoul.sh"
fi

# BROKEN — повод разбора (D203), DRIFT — нет. Разница по последствию, а не по тяжести:
# DRIFT значит «разошлось, чинится одной командой», а BROKEN значит «сравнить НЕ УДАЛОСЬ»,
# то есть проверка потеряла способность отвечать на свой вопрос. Сбой самого наблюдения
# в зрелых практиках ценится выше сбоя наблюдаемого: инцидент, найденный вручную при
# молчащем мониторинге, вскрывает дыру в наблюдаемости, а не только в сервисе.
if [ "$_broken_total" -gt 0 ]; then
    _RC_LIB="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")/.." 2>/dev/null && pwd)/root-cause-lib.sh"
    [ -f "$_RC_LIB" ] || _RC_LIB="$HOME/.claude/hooks/root-cause-lib.sh"
    if [ -f "$_RC_LIB" ]; then
        # shellcheck source=/dev/null
        . "$_RC_LIB"
        rc_note_event "${STATE_DIR:-$HOME/.claude/hooks/state}" "drift-broken" \
            "пар, где сравнить не удалось: $_broken_total"
    fi
fi

[ "$_broken_total" -gt 0 ] && exit 2
[ "$_drift_total" -gt 0 ] && exit 1
exit 0
