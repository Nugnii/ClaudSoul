#!/usr/bin/env bash
# uninstall.sh — снять ClaudSoul с машины, не тронув накопленное.
#
# Зачем. `install.sh` правит четыре места в глобальной настройке Claude Code, и до этого
# скрипта пути назад не было ни одного: бэкапы с отметкой времени создавались, но откат
# оставался ручным. Внешний читатель README закрывал вкладку ровно на этом абзаце —
# «перечислили четыре записи в мой глобальный конфиг и не дали ни одного пути назад».
# Необратимость установки — довод против установки, а не мелочь оформления.
#
# ЧТО НЕ УДАЛЯЕТСЯ НИКОГДА: ~/.claude/global-lessons/ — накопленная база знаний.
# Это работа владельца машины, а не файлы программы: кейсы, паттерны и принципы, набранные
# за месяцы. Снятие инструмента не повод стирать то, ради чего он ставился. Каталог
# называется в отчёте явно, чтобы человек знал, что осталось и где.
#
# УМОЛЧАНИЕ — СУХОЙ ПРОГОН. Скрипт печатает список того, что снимет, и выходит. Удаление
# только по явному `--apply`. Обратный порядок (удалять по умолчанию, показывать по флагу)
# ставит цену ошибки на неверную сторону: забытый флаг у деструктивной операции стоит
# данных, забытый флаг у показа стоит одного повторного запуска.
#
# Принадлежность определяется СВЕРКОЙ С РЕПОЗИТОРИЕМ, а не маской имени: в ~/.claude/hooks
# и ~/.claude/commands живут и чужие хуки со скиллами. Снимается ровно то, чему нашёлся
# исходник в этом репозитории; всё прочее не трогается и в отчёт не попадает.
#
# Использование:
#   ./uninstall.sh            # показать, что будет снято
#   ./uninstall.sh --apply    # снять
#   ./uninstall.sh --apply --keep-state   # снять, но оставить журналы и реестр сессий

set -uo pipefail

CLAUDSOUL_DIR="${CLAUDSOUL_DIR:-$(cd "$(dirname "$0")" && pwd)}"
CLAUDE_HOME="$HOME/.claude"
APPLY=0
KEEP_STATE=0

for arg in "$@"; do
    case "$arg" in
        --apply) APPLY=1 ;;
        --keep-state) KEEP_STATE=1 ;;
        -h|--help) sed -n '2,30p' "$0"; exit 0 ;;
        *) echo "Неизвестный аргумент: $arg" >&2; exit 2 ;;
    esac
done

ts=$(date +%Y%m%d%H%M%S)
PLANNED=0
note()  { printf '  %s\n' "$1"; }
plan()  { PLANNED=$((PLANNED + 1)); printf '  %s\n' "$1"; }

[ -d "$CLAUDE_HOME" ] || { echo "Нет $CLAUDE_HOME — ClaudSoul не установлен."; exit 0; }

if [ "$APPLY" -eq 0 ]; then
    echo "СУХОЙ ПРОГОН. Ничего не удаляется. Для снятия: $0 --apply"
else
    echo "СНЯТИЕ ClaudSoul."
fi
echo ""

# --- 1. Хуки: только те, чей исходник есть в репозитории ---
echo "Хуки (~/.claude/hooks):"
HOOK_HITS=0
if [ -d "$CLAUDE_HOME/hooks" ]; then
    for src in "$CLAUDSOUL_DIR"/hooks/*.sh; do
        [ -f "$src" ] || continue
        name=$(basename "$src")
        tgt="$CLAUDE_HOME/hooks/$name"
        [ -f "$tgt" ] || continue
        HOOK_HITS=$((HOOK_HITS + 1))
        [ "$APPLY" -eq 1 ] && rm -f "$tgt"
    done
    for src in "$CLAUDSOUL_DIR"/hooks/lib/*; do
        [ -f "$src" ] || continue
        tgt="$CLAUDE_HOME/hooks/lib/$(basename "$src")"
        [ -f "$tgt" ] || continue
        HOOK_HITS=$((HOOK_HITS + 1))
        [ "$APPLY" -eq 1 ] && rm -f "$tgt"
    done
fi
[ "$HOOK_HITS" -gt 0 ] && plan "$HOOK_HITS файл(ов) — сверено с $CLAUDSOUL_DIR/hooks/" || note "нечего снимать"

# --- 2. Скиллы ---
echo "Скиллы (~/.claude/commands):"
SKILL_HITS=0
for src in "$CLAUDSOUL_DIR"/skills/*/; do
    [ -f "$src/SKILL.md" ] || continue
    name=$(basename "$src")
    tgt="$CLAUDE_HOME/commands/$name"
    [ -d "$tgt" ] || continue
    SKILL_HITS=$((SKILL_HITS + 1))
    [ "$APPLY" -eq 1 ] && rm -rf "$tgt"
done
[ "$SKILL_HITS" -gt 0 ] && plan "$SKILL_HITS каталог(ов)" || note "нечего снимать"

# --- 3. Блок правил в глобальном CLAUDE.md ---
echo "Глобальные правила (~/.claude/CLAUDE.md):"
GLOBAL_MD="$CLAUDE_HOME/CLAUDE.md"
MARK_START="<!-- ClaudSoul: managed-start"
MARK_END="<!-- ClaudSoul: managed-end -->"
if [ -f "$GLOBAL_MD" ] && grep -qF "$MARK_START" "$GLOBAL_MD"; then
    plan "блок между маркерами будет вырезан (копия: CLAUDE.md.bak.$ts)"
    if [ "$APPLY" -eq 1 ]; then
        cp "$GLOBAL_MD" "$GLOBAL_MD.bak.$ts"
        awk -v s="$MARK_START" -v e="$MARK_END" '
            index($0, s) { skip = 1 }
            !skip { print }
            index($0, e) { skip = 0 }
        ' "$GLOBAL_MD" > "$GLOBAL_MD.tmp" && mv "$GLOBAL_MD.tmp" "$GLOBAL_MD"
    fi
else
    note "маркеров нет — файл не тронут"
fi

# --- 4. Регистрация хуков и статусной строки в settings.json ---
echo "Настройки (~/.claude/settings.json):"
SETTINGS="$CLAUDE_HOME/settings.json"
if [ -f "$SETTINGS" ] && command -v jq >/dev/null 2>&1; then
    # Снимаются ТОЛЬКО команды, указывающие на наши хуки. Чужие записи в тех же событиях
    # остаются: settings.json — общий файл, а не наш.
    if jq -e '.hooks' "$SETTINGS" >/dev/null 2>&1; then
        plan "команды хуков ClaudSoul будут удалены (копия: settings.json.bak.$ts)"
        if [ "$APPLY" -eq 1 ]; then
            cp "$SETTINGS" "$SETTINGS.bak.$ts"
            # Список НАШИХ имён строится из репозитория и передаётся в jq. Прежняя версия
            # отбирала по маске пути `.claude/hooks/*.sh` и сносила вместе с нашими чужие
            # хуки, лежащие в том же каталоге и том же событии, — принадлежность определяется
            # сверкой с исходником, ровно как для файлов выше, а не формой пути.
            OURS_JSON=$(for s in "$CLAUDSOUL_DIR"/hooks/*.sh; do
                [ -f "$s" ] && basename "$s"; done | jq -R . | jq -s .)
            jq --argjson ours "$OURS_JSON" '
              def is_ours: . as $c | ($ours | any(. as $n | $c | test("/" + $n + "$|/" + $n + "[^a-zA-Z0-9]")));
              (.hooks // {}) |= with_entries(
                .value |= (map(
                    .hooks |= map(select(((.command // "") | is_ours) | not))
                  ) | map(select((.hooks | length) > 0)))
              )
              | (if (.hooks | length) == 0 then del(.hooks) else . end)
              | (if (.statusLine.command // "") | test("statusline-claudsoul") then del(.statusLine) else . end)
            ' "$SETTINGS" > "$SETTINGS.tmp" && mv "$SETTINGS.tmp" "$SETTINGS"
        fi
    else
        note "секции hooks нет"
    fi
else
    note "файла нет либо нет jq — правьте вручную"
fi

# --- 5. Одиночные файлы ---
echo "Служебные файлы:"
for rel in bin/resolve-claudsoul-repo.sh claudsoul-repo statusline-claudsoul.sh; do
    tgt="$CLAUDE_HOME/$rel"
    [ -e "$tgt" ] || continue
    plan "$rel"
    [ "$APPLY" -eq 1 ] && rm -f "$tgt"
done
SKILL_TMPL=0
for src in "$CLAUDSOUL_DIR"/templates/*; do
    [ -f "$src" ] || continue
    tgt="$CLAUDE_HOME/templates/$(basename "$src")"
    [ -f "$tgt" ] || continue
    SKILL_TMPL=$((SKILL_TMPL + 1))
    [ "$APPLY" -eq 1 ] && rm -f "$tgt"
done
[ "$SKILL_TMPL" -gt 0 ] && plan "$SKILL_TMPL шаблон(ов)"
[ "$PLANNED" -eq 0 ] && note "нечего снимать"

# --- 6. Периодические агенты (macOS) ---
echo "Периодические агенты (launchd):"
LA_HITS=0
if [ "$(uname -s)" = "Darwin" ]; then
    for label in com.claudsoul.scanner com.claudsoul.knowledge-audit com.claudsoul.bridge-health; do
        plist="$HOME/Library/LaunchAgents/${label}.plist"
        [ -f "$plist" ] || continue
        LA_HITS=$((LA_HITS + 1))
        if [ "$APPLY" -eq 1 ]; then
            launchctl unload "$plist" 2>/dev/null
            rm -f "$plist"
        fi
    done
    [ "$LA_HITS" -gt 0 ] && plan "$LA_HITS агент(ов)" || note "не установлены"
else
    note "не macOS — агенты не ставились"
fi

# --- 7. Сервер MCP ---
echo "Сервер MCP:"
# `claude mcp list` НЕ вызывается в сухом прогоне: сам CLI при любом вызове пишет
# ~/.claude.json и кладёт его копию в ~/.claude/backups/. Сухой прогон не имеет права
# ни на один побочный эффект — в том числе чужой. Поймано собственным тестом: сравнение
# дерева до и после показало два новых файла там, где обещано «ничего не меняется».
if ! command -v claude >/dev/null 2>&1; then
    note "нет CLI claude — снимите вручную: claude mcp remove claudsoul -s user"
elif [ "$APPLY" -eq 0 ]; then
    plan "регистрация claudsoul будет снята, если она есть (проверка отложена: вызов CLI пишет свой конфиг)"
elif claude mcp list 2>/dev/null | grep -q claudsoul; then
    plan "регистрация claudsoul снята"
    claude mcp remove claudsoul -s user >/dev/null 2>&1
else
    note "не зарегистрирован"
fi

# --- 8. Состояние ---
echo "Состояние (журналы, реестр сессий):"
if [ "$KEEP_STATE" -eq 1 ]; then
    note "оставлено по --keep-state"
else
    ST_HITS=0
    for d in "$CLAUDE_HOME/hooks/state" "$CLAUDE_HOME/sessions"; do
        [ -d "$d" ] || continue
        ST_HITS=$((ST_HITS + 1))
        [ "$APPLY" -eq 1 ] && rm -rf "$d"
    done
    [ "$ST_HITS" -gt 0 ] && plan "$ST_HITS каталог(ов) — журналы инжектов, метрики, реестр" || note "нечего снимать"
fi

echo ""
echo "СОХРАНЯЕТСЯ: $CLAUDE_HOME/global-lessons — накопленная база знаний."
if [ -d "$CLAUDE_HOME/global-lessons" ]; then
    kn=$(find "$CLAUDE_HOME/global-lessons" -maxdepth 1 -name '*.md' | wc -l | tr -d ' ')
    echo "  в ней сейчас $kn записей. Это ваша работа, а не файлы программы — она остаётся."
fi
echo ""
if [ "$APPLY" -eq 0 ]; then
    echo "Это был сухой прогон. Чтобы снять: $0 --apply"
else
    echo "Снято. Перезапустите Claude Code, чтобы настройки перечитались."
fi
