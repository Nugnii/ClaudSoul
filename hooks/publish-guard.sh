#!/usr/bin/env bash
# publish-guard.sh — PreToolUse: публикация наружу ждёт показанного сухого прогона.
# Подробно: необратимая отправка не выполняется, пока в этом же ходе не показано, ЧТО уйдёт.
# en: PreToolUse — blocks an irreversible outward publish until a dry run is shown in the turn.
#
# Повод — решение владельца 7 сентября 2026 по пункту D330. Знание
# `pattern-publication-carrier-mismatch` («личное сидит не в том носителе, в который смотрит
# очистка») стояло на уровне 3: у него есть detection_signals, то есть система НАПОМИНАЛА.
# Замер того же дня: 34 срабатывания на 21 658 вызовов Bash, ложных 0, частота 0,157% —
# фоном не станет. Оба контрпримера подтверждены МОЛЧАНИЕМ признака: 38 сухих прогонов в
# корпусе не пойманы ни разу, упоминание имени скрипта в тексте — тоже.
#
# ПОЧЕМУ ОТКАЗ, А НЕ ПОДСКАЗКА. Последствие здесь одно и необратимо: снимок ушёл наружу и
# не отзывается. Правило четырёх уровней embedded-ness требует для такого случая уровня 4
# (`permissionDecision`), и измерено, что первые три уровня напоминают, а не удерживают.
#
# ПРИЗНАК СНЯТИЯ — ДЕЙСТВИЕ, А НЕ РЕЧЬ: сухой прогон того же скрипта в этом же ходе.
# Обещание «я проверил» словами не принимается: 7 сентября 2026 трижды измерено, что
# признак, снятый с текста, выдаёт правдоподобное и при этом ложное показание.
#
# ОБЛАСТЬ УЖЕ ИЗМЕРЕННОГО. Отказ стоит только на `publish-public.sh --push` — форме, чья
# точность промерена. `npm publish` и `gh release create` в корпусе встретились 0 и 1 раз;
# признак с непроверенной точностью в уровень 4 не переводится (то же правило, из-за
# которого роды C и I не заведены).
#
# Input  (stdin): {tool_name, tool_input:{command}, transcript_path}
# Output (stdout): {hookSpecificOutput:{... permissionDecision:"deny" ...}} либо пусто
# Exit:  always 0 — решение передаётся полем, а не кодом возврата.
set -uo pipefail

command -v jq >/dev/null 2>&1 || exit 0
INPUT=$(cat 2>/dev/null) || exit 0
[ -n "$INPUT" ] || exit 0

TOOL=$(printf '%s' "$INPUT" | jq -r '.tool_name // ""' 2>/dev/null)
[ "$TOOL" = "Bash" ] || exit 0
CMD=$(printf '%s' "$INPUT" | jq -r '.tool_input.command // ""' 2>/dev/null)
[ -n "$CMD" ] || exit 0

[ "${PUBLISH_GUARD_OFF:-0}" = "1" ] && exit 0

# Имя скрипта в ПОЗИЦИИ КОМАНДЫ — начало строки либо после разделителя, необязательно через
# интерпретатор. `grep publish-public README.md` сюда не попадает: там имя стоит аргументом.
PUB_RE='(^|[;&|][[:space:]]*|&&[[:space:]]*|\|\|[[:space:]]*)((bash|sh|zsh)[[:space:]]+)?[^[:space:]]*publish-public\.sh'
grep -qE "$PUB_RE" <<< "$CMD" || exit 0
# Отправка наружу — только с --push; сухой прогон проходит свободно, он и есть предъявление.
grep -qE '(^|[[:space:]])--push([[:space:]]|$)' <<< "$CMD" || exit 0

TRANSCRIPT=$(printf '%s' "$INPUT" | jq -r '.transcript_path // ""' 2>/dev/null)

# Был ли в ЭТОМ ходе сухой прогон того же скрипта. Ход — после последней реплики
# собеседника, та же граница, что у контура разбора причин.
DRY_SEEN=0
if [ -n "$TRANSCRIPT" ] && [ -f "$TRANSCRIPT" ]; then
    DRY_SEEN=$(jq -rs --arg pub "$PUB_RE" '
        def role(x): x.message.role // x.role // "";
        def blocks(x): (x.message.content // x.content // []) as $c |
            if ($c | type) == "array" then $c else [] end;
        def get_text(x): (x.message.content // x.content // []) as $c |
            if ($c | type) == "array" then ($c | map(select(.type == "text") | .text) | join("\n"))
            elif ($c | type) == "string" then $c else "" end;
        . as $items | (length) as $n |
        ([range(0; $n) | ($n - 1 - .)
          | select(role($items[.]) == "user" and ((($items[.]).isMeta // false) | not) and ((get_text($items[.]) // "") | length > 0))]
          | first) as $pu |
        (if $pu == null then 0 else $pu + 1 end) as $from |
        [range($from; $n) | $items[.]
         | select(role(.) == "assistant") | blocks(.)[]
         | select(.type == "tool_use" and (.name == "Bash"))
         | (.input.command // "")
         | select(test($pub)) | select(test("(^|\\s)--push(\\s|$)") | not)]
        | length' "$TRANSCRIPT" 2>/dev/null || printf '0')
fi
case "${DRY_SEEN:-}" in ''|*[!0-9]*) DRY_SEEN=0 ;; esac
[ "$DRY_SEEN" -gt 0 ] && exit 0

REASON='⛔ Необратимая публикация наружу без предъявленного сухого прогона.

Снимок уходит наружу и не отзывается, а очистка смотрит не во все места, где может лежать
личное (знание pattern-publication-carrier-mismatch: 34 срабатывания, ложных 0).

Снять отказ — показать, ЧТО уйдёт, тем же скриптом без --push:
    bash scripts/publish-public.sh
После сухого прогона в этом же ходе отправка проходит без вопросов.

Отключить разово: env PUBLISH_GUARD_OFF=1.'

jq -n --arg ctx "$REASON" '{
    hookSpecificOutput: {
        hookEventName: "PreToolUse",
        permissionDecision: "deny",
        permissionDecisionReason: $ctx
    }
}' 2>/dev/null || true
exit 0
