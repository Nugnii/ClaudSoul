#!/usr/bin/env bash
# ablation-phase-guard.sh — фаза замера видима и защищена механически (§6).
# en: while a measurement phase is active, injects a per-session signal and guards the installed policy surface from deploys; nobody has to remember.
#
# Родился из вопроса собеседника «мне постоянно нужно помнить, идёт фаза или
# нет?» — по principle-knowledge-in-the-world помнить не должен никто: маркер
# active-phase.json (пишет freeze-policy, снимает phase.sh close) — источник
# истины; этот хук его читает на двух событиях:
#   UserPromptSubmit — раз в сессию: «фаза X активна, правила §6»;
#   PreToolUse (Bash|Edit|Write|MultiEdit) — каждый раз: попытка деплоя в УСТАНОВЛЕННУЮ
#   policy (~/.claude/hooks, settings.json, CLAUDE.md, install.sh) во время
#   фазы получает стоп-сигнал. Разработка в репозитории свободна (§6:
#   разрабатывать можно постоянно, активировать — между фазами).
#
# Ограничение названо: Bash-детект ловит классы cp/mv/rm/ln/tee/install.sh —
# экзотический redirect в установленное может пройти мимо; страж — тормоз
# от бытовой инерции, не санкция.
set -uo pipefail

PATHS_LIB="${PATHS_LIB:-$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/paths-lib.sh}"
if [ -f "$PATHS_LIB" ]; then source "$PATHS_LIB"; else : "${STATE_DIR:=$HOME/.claude/hooks/state}"; fi
THROTTLE_LIB="${THROTTLE_LIB:-$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/throttle-lib.sh}"
[ -f "$THROTTLE_LIB" ] || THROTTLE_LIB="$HOME/.claude/hooks/throttle-lib.sh"
[ -f "$THROTTLE_LIB" ] && source "$THROTTLE_LIB"

command -v jq >/dev/null 2>&1 || exit 0

MARKER="${ABLATION_DIR:-$HOME/.claude/ablation}/active-phase.json"
[ -f "$MARKER" ] || exit 0
PHASE=$(jq -r '.phase // "?"' "$MARKER" 2>/dev/null)
SINCE=$(jq -r '.since // "?"' "$MARKER" 2>/dev/null)

INPUT=$(cat)
SESSION_ID=$(printf '%s' "$INPUT" | jq -r '.session_id // empty' 2>/dev/null)
TOOL=$(printf '%s' "$INPUT" | jq -r '.tool_name // empty' 2>/dev/null)

# Заморозка policy держится не с открытия фазы, а с ПЕРВОЙ ПРИНЯТОЙ задачи.
# Внутри тройки заморозка абсолютна по построению (§6: все три тени из одного
# снимка), значит общий запрет нужен только для сопоставимости МЕЖДУ тройками.
# Троек ноль — сравнивать не с чем, и запрет охраняет сравнение, которого нет,
# платя полной остановкой правок. Повод: владелец, 2026-08-27, при нулевой
# очереди и стоящих правках. Тот же якорь, что у часов enrollment (§13).
J="${ABLATION_DIR:-$HOME/.claude/ablation}/journal.jsonl"
QUEUED=0
if [ -f "$J" ]; then
    QUEUED=$(jq -s '[.[] | select(.e=="queue")] | length' "$J" 2>/dev/null || echo 0)
fi
case "${QUEUED:-0}" in ''|*[!0-9]*) QUEUED=0 ;; esac

inject() {
    # Оба поля: additionalContext — агенту в контекст, systemMessage — владельцу
    # на экран. Amendment phase-1 (2026-08-08): сигнал уходил только агенту,
    # владелец в новой сессии его не видел — «и ты видишь, и я вижу» было
    # правдой наполовину. Правило владельца обязано быть видимым владельцу.
    printf '%s' "$1" | jq -Rs --arg ev "$2" \
        '{systemMessage: ., hookSpecificOutput: {hookEventName: $ev, additionalContext: .}}'
    exit 0
}

if [ -z "$TOOL" ]; then
    # UserPromptSubmit: сигнал раз в сессию. Содержимое динамическое: обязанность
    # регистрации (протокол §3: запрос регистрируется ДО первого действия) и
    # авто-проверка условия остановки (§13: 20 в очереди либо 8 недель) — обе
    # обязанности сняты с памяти агента механизмом (та же норма, что для владельца).
    [ -n "$SESSION_ID" ] || exit 0

    # Сегмент шапки уходит КАЖДЫЙ ход, а полные правила — раз в сессию.
    # Правило шапки требует «очередь N/20», но источника N не было ни в одном
    # хуке: число жило только в `phase.sh status`, и каждая сессия сочиняла своё.
    # 2026-08-27 владелец увидел «11/20» при живом 0 — канарейка, заведённая
    # ЛОВИТЬ расхождение, сама его производила (pattern-unobservable-narrated-as-fact).
    # Теперь агент копирует число отсюда. Раз в сессию сегмент не годится:
    # очередь растёт по ходу, и к концу сессии эхо было бы устаревшим.
    SEGMENT="🧪 Сегмент шапки этого хода: «🧪 ${PHASE} · очередь ${QUEUED}/20» — число копируй отсюда, не сочиняй."

    FIRST="yes"
    if command -v throttle_file >/dev/null 2>&1; then
        TF=$(throttle_file "$STATE_DIR" ablation-phase "$SESSION_ID")
        if throttle_seen "$TF" session; then
            FIRST="no"
        else
            throttle_mark "$TF" session
        fi
    fi
    [ "$FIRST" = "no" ] && inject "$SEGMENT" "UserPromptSubmit"
    if [ "$QUEUED" -gt 0 ]; then
        MSG="🧪 Фаза ablation «${PHASE}» активна (с ${SINCE}), в очереди ${QUEUED}. Заморозка В СИЛЕ. Правила §6: подключать хуки/скиллы, менять activation/пороги/инъекции/MCP — ЗАПРЕЩЕНО; разработка в ветке свободна; база знаний живёт. Закрытие: scripts/ablation/phase.sh close ${PHASE}."
    else
        MSG="🧪 Фаза ablation «${PHASE}» активна (с ${SINCE}), очередь пуста. Заморозка ЕЩЁ НЕ В СИЛЕ: троек ноль, сравнивать не с чем — правки policy разрешены и просто войдут в то, что будет мериться. Заморозка включится с первой принятой задачей. Закрытие: scripts/ablation/phase.sh close ${PHASE}."
    fi

    if [ -f "$J" ]; then
        TODAY=$(date -u '+%Y-%m-%d')
        REG_TODAY=$(jq -s --arg d "$TODAY" \
            '[.[] | select(.e=="register" and (.ts | startswith($d)))] | length' "$J" 2>/dev/null || echo 0)
        [ "${REG_TODAY:-0}" -eq 0 ] && MSG="$MSG
⚠ Регистраций сегодня нет — рабочий запрос регистрируется ДО первого действия (§3): scripts/ablation/journal.sh register \"<текст запроса>\"."
        # Условие остановки: константы протокола (§13), не настройки.
        STOP=$(jq -s --arg since "$SINCE" '
            [.[] | select(.e=="queue")] as $q
            | ($q | length) as $n
            | (if $n > 0 then ($q[0].ts | fromdateiso8601) else null end) as $first
            | if $n >= 20 then "очередь \($n) >= 20 задач"
              elif ($first != null and (now - $first) > 4838400) then "8 недель с первой принятой"
              else empty end' "$J" 2>/dev/null | head -1)
        [ -n "$STOP" ] && [ "$STOP" != "null" ] && MSG="$MSG
⏰ Условие закрытия enrollment ДОСТИГНУТО (${STOP}): решение о закрытии — scripts/ablation/phase.sh close ${PHASE}."
    else
        MSG="$MSG
⚠ Журнал задач пуст — рабочий запрос регистрируется ДО первого действия (§3): scripts/ablation/journal.sh register \"<текст запроса>\"."
    fi
    inject "${SEGMENT}
${MSG}" "UserPromptSubmit"
fi

# PreToolUse: деплой в установленную policy во время фазы.
# До первой принятой задачи запрет не действует — см. пояснение к QUEUED выше.
[ "$QUEUED" -gt 0 ] || exit 0
# КОНТРПРИМЕР: правка ЧЕРЕЗ ОБОЛОЧКУ в обход этих путей — `cp x ~/.claude/hooks/y.sh`
# записана как путь назначения и попадёт, а `install.sh`, кладущий то же самое из
# репозитория, — нет: признак смотрит на строку пути, а не на факт установки.
DEPLOY_RE="\.claude/(hooks/|settings\.json|CLAUDE\.md)"
case "$TOOL" in
Edit|Write|MultiEdit)
    FILE=$(printf '%s' "$INPUT" | jq -r '.tool_input.file_path // ""' 2>/dev/null)
    grep -qE "^$HOME/$DEPLOY_RE" <<< "$FILE" || exit 0
    ;;
Bash)
    CMD=$(printf '%s' "$INPUT" | jq -r '.tool_input.command // ""' 2>/dev/null)
    # install.sh ловится только на ИСПОЛНЕНИЕ (bash|sh|source|./), не на
    # упоминание: маска «|install\.sh» дала 3 ложных СТОПа за 10 минут на
    # grep/чтение/git add — amendment phase-2 (2026-08-09). bash -n — проверка
    # синтаксиса, не запуск.
    # Имя команды — с границей, как у ветки install.sh ниже. Без неё
    # альтернатива ловила «rm» внутри любого слова ПЕРЕД путём: временный
    # каталог `/var/folders/rm5/...` и `git add hooks/reformulation-tracker.sh
    # ~/.claude/hooks/` давали ложный СТОП. Границу добавили ветке install.sh
    # 2026-08-09 (amendment phase-2), соседнюю не тронули — та же правка,
    # доехавшая в одно место из двух (2026-08-27).
    if grep -qE "(^|[;&|[:space:]])(cp|mv|rm|ln|tee)[[:space:]][^|;&]*$DEPLOY_RE" <<< "$CMD"; then
        :
    elif grep -qE "(^|[;&|[:space:]])((bash|sh|source)[[:space:]]+[^|;&]*install\.sh|\./install\.sh)" <<< "$CMD" \
        && ! grep -qE "(bash|sh)[[:space:]]+-n[[:space:]]" <<< "$CMD"; then
        :
    else
        exit 0
    fi
    ;;
*)  exit 0 ;;
esac

inject "🧪 СТОП: идёт фаза ablation «${PHASE}», в очереди ${QUEUED} задач(и) — деплой в установленную policy запрещён до конца фазы (§6): изменение попадёт в снимки будущих пар и разойдётся с уже принятыми. Правку — в ветку (активация после фазы). Критический дефект → amendment-процедура (§6: стоп enrollment → фиксация пар → исправление → новая фаза). Осознанное закрытие фазы: scripts/ablation/phase.sh close ${PHASE}." "PreToolUse"
