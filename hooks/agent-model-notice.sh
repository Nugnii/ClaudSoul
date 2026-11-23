#!/usr/bin/env bash
# agent-model-notice.sh — PreToolUse[Agent|Task|Workflow]: тяжёлый тип агента там, где хватит lean, и названный opus называются подсказкой.
# en: PreToolUse on agent/workflow launches — hints when a heavy agent type is used where `lean` would do, or when opus is named.
#
# Результат: запуская агента типа general-purpose (или волну, где у agent( нет agentType) либо
#            называя opus, автор видит цену старта и распределение по ролям, пока запуск ещё
#            дёшево остановить.
# Проверка результата: bash hooks/tests/test_agent_model_notice.sh даёт 0
#
# Правило живёт в rules/CLAUDE.md, § «Модели агентов»; здесь его механическая половина.
# Модель по умолчанию задаёт не хук, а `CLAUDE_CODE_SUBAGENT_MODEL=haiku` в settings.json:
# агент без названной модели идёт на haiku, поэтому «модель не названа» больше не повод.
#
# Повод — замер 8 октября 2026 по расшифровкам 24.09–08.10: субагенты дали 74% расхода в
# пересчёте по ценам API, из него 99% — контекст, а не ответы: агент стартует с ~104 тыс. токенов
# (медиана) и перечитывает их ~65 шагов. Из 120 тыс. токенов старта general-purpose в ProjectA_NEW
# 90 тыс. — CLAUDE.md с подключёнными файлами; агент `lean` (~/.claude/agents/lean.md: без
# CLAUDE.md, файловые инструменты и Bash) стартует с 6,7 тыс. Opus у проверяющих волн дал 40%.
#
# ПОЧЕМУ ПОДСКАЗКА, А НЕ ОТКАЗ. general-purpose законен, когда агенту нужны веб, MCP или
# скиллы; opus законен у финального скептика и на правке защитного слоя. У обоих признаков
# последствий два — уровень 4 не ставится.
#
# МОЛЧИТ о прочих типах: lean лёгок сам, Explore и Plan CLAUDE.md не грузят, claude-code-guide
# несёт модель в определении, fork наследует контекст родителя по устройству; определения своих
# типов хук не читает.
# ПРЕДЕЛ ВОЛНЫ: судится ТЕКСТ скрипта — мест вызова `agent(` против ключей `agentType` и
# значений opus у ключа model (строки-комментарии `//` сняты, у слов требуется граница). Текст
# не разбор: ключ внутри промпта засчитается, общая константа даст ложную подсказку; сохранённая
# волна (`name` без текста) не судится. Условие снятия: харнесс отдаст в payload разрешённые тип
# и модель вызова.
# НАЗВАННЫЙ ПРЕДЕЛ КАНАЛА: additionalContext на PreToolUse приходит вместе с результатом
# вызова, то есть ПОСЛЕ запуска. Волну в первую минуту остановить дёшево (TaskStop); для
# одиночного агента подсказка работает на следующий запуск.
set -uo pipefail

# jq нет — «прибора здесь нет»: молчим и выходим успехом, это не отказ.
command -v jq >/dev/null 2>&1 || exit 0
PAYLOAD=$(cat 2>/dev/null || true)
[ -n "$PAYLOAD" ] || exit 0

TOOL=$(printf '%s' "$PAYLOAD" | jq -r '.tool_name // empty' 2>/dev/null) || exit 0
# Параметры не объект — вход не прочитан: тип и модель из него не выводятся.
printf '%s' "$PAYLOAD" | jq -e '.tool_input | type == "object"' >/dev/null 2>&1 || exit 0
ROLES="без модели — haiku (поиск, чтение, сбор фактов, прогон тестов, механическая правка по точной инструкции); model: 'sonnet' — сборка по образцу, починка по замечаниям, промежуточные проверки; model: 'opus' — только финальный скептик и правка защитного слоя."
HEAVY="стартует со всем CLAUDE.md, скиллами и MCP (в ProjectA_NEW ~120 тыс. токенов против 6,7 тыс. у lean)"
OPUS_RULE="opus — только финальному скептику и правке защитного слоя"

case "$TOOL" in
    Agent|Task)
        TYPE=$(printf '%s' "$PAYLOAD" | jq -r '.tool_input.subagent_type // empty' 2>/dev/null)
        MODEL=$(printf '%s' "$PAYLOAD" | jq -r '.tool_input.model // empty' 2>/dev/null)
        [ "$TYPE" = fork ] && exit 0
        MSG=""
        # Тип не назван — это general-purpose (описание инструмента Agent).
        case "$TYPE" in ""|general-purpose)
            MSG="Агент типа general-purpose $HEAVY. Агенту без веба, MCP и скиллов — subagent_type: 'lean'." ;;
        esac
        case "$MODEL" in opus*|claude-opus*) MSG="$MSG Назван opus: $OPUS_RULE." ;; esac
        [ -n "$MSG" ] || exit 0
        MSG="🎚️ ${MSG# } По роли: $ROLES Осознанно — продолжай."
        ;;
    Workflow)
        SCRIPT=$(printf '%s' "$PAYLOAD" | jq -r '.tool_input.script // empty' 2>/dev/null)
        if [ -z "$SCRIPT" ]; then
            SPATH=$(printf '%s' "$PAYLOAD" | jq -r '.tool_input.scriptPath // empty' 2>/dev/null)
            [ -n "$SPATH" ] && [ -f "$SPATH" ] && SCRIPT=$(cat "$SPATH" 2>/dev/null || true)
        fi
        [ -n "$SCRIPT" ] || exit 0
        # Строки-комментарии не код: `agent(`, `agentType:` и `model:` в них не считаются.
        CODE=$(printf '%s\n' "$SCRIPT" | sed '/^[[:space:]]*\/\//d')
        # ponytail: счёт по тексту, не разбор JS — пределы названы в шапке; разбор опций
        # каждого вызова — когда замер покажет ложные подсказки на общих константах.
        CALLS=$(printf '%s\n' "$CODE" | grep -oE '(^|[^A-Za-z0-9_.])agent[[:space:]]*\(' | wc -l | tr -d '[:space:]')
        [ "${CALLS:-0}" -gt 0 ] || exit 0
        TYPED=$(printf '%s\n' "$CODE" | grep -oE "(^|[^A-Za-z0-9_.])[\"']?agentType[\"']?[[:space:]]*:" | wc -l | tr -d '[:space:]')
        OPUSN=$(printf '%s\n' "$CODE" | grep -oE "(^|[^A-Za-z0-9_.])[\"']?model[\"']?[[:space:]]*:[[:space:]]*[\"'\`](claude-)?opus" | wc -l | tr -d '[:space:]')
        MSG=""
        if [ "${TYPED:-0}" -eq 0 ]; then
            MSG="Ни у одного из $CALLS мест вызова agent( нет agentType: агент волны $HEAVY. Агентам без веба, MCP и скиллов — agentType: 'lean'."
        elif [ "$TYPED" -lt "$CALLS" ]; then
            MSG="agentType назван у $TYPED из $CALLS мест вызова agent( (задан общей константой — подсказка ложна): остальные агенты $HEAVY. Агентам без веба, MCP и скиллов — agentType: 'lean'."
        fi
        # Порог 2: одно место с opus — законный финальный скептик.
        [ "${OPUSN:-0}" -ge 2 ] && MSG="$MSG opus назван у $OPUSN мест вызова: $OPUS_RULE."
        [ -n "$MSG" ] || exit 0
        MSG="🎚️ ${MSG# } Не осознанно — останови (TaskStop) и перезапусти. По роли: $ROLES"
        ;;
    *) exit 0 ;;
esac

jq -cn --arg m "$MSG" '{hookSpecificOutput:{hookEventName:"PreToolUse",additionalContext:$m}}'
exit 0
