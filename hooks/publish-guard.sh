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
# `(` — тоже начало команды: подоболочка и открытие подстановки, которое `executable_part` выводит
# `( ` (D1212); без него `out=$(./scripts/publish-public.sh --push)` проходил мимо отказа.
PUB_RE='(^|[;&|(][[:space:]]*|&&[[:space:]]*|\|\|[[:space:]]*)((bash|sh|zsh)[[:space:]]+)?[^[:space:]]*publish-public\.sh'

# ОБЛАСТЬ ПОИСКА ОБЪЯВЛЕНА, И У ПРИЗНАКА ОДИН ИСПОЛНИТЕЛЬ (D426, 17 сентября 2026).
# Прежде `PUB_RE` был объявлен строкой и применён ДВУМЯ способами с разной семантикой: здесь
# `grep <<<` судил ПОСТРОЧНО, а ниже jq `test()` без multiline — всю строку целиком. Один
# объявленный признак судил по двум правилам (корень R1: поведение собрано на каждом конце
# отдельно). Оба конца теперь зовут ЭТУ функцию, и правило у них одно.
#
# Судится ИСПОЛНЯЕМАЯ ЧАСТЬ, а не весь текст (корень R3, тот же, что у закрытых D424 и D425):
# разделитель ВНУТРИ кавычек считался разделителем, и имя в теле чужого heredoc, в сообщении
# коммита или в пути к файлу попадало в «позицию команды».
# ЗАМЕР по корпусу (331 команда с упоминанием скрипта): признак срабатывал на сыром тексте 88
# раз, на исполняемой части — 75; расхождение 13, и ВСЕ ТРИНАДЦАТЬ без `--push`, то есть все
# они накручивали счётчик сухих прогонов и СНИМАЛИ отказ с настоящей публикации. Ложных
# отказов на текущей команде в корпусе 0 — эта сторона возможна по построению, но не измерена.
#
# НЕТ БИБЛИОТЕКИ — СУДИМ ПО СЫРОМУ ТЕКСТУ, А НЕ МОЛЧИМ. У соседа `rules-write-bypass` при
# пропаже библиотеки страж замолкает, и это верно ТАМ: его промах даёт лишний отказ. Здесь
# цена обратная и необратимая — пропущенная публикация наружу не отзывается, а лишний отказ
# снимается разово (`PUBLISH_GUARD_OFF=1`). Поэтому деградация идёт к ПРЕЖНЕМУ поведению.
_CS_LIB="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" 2>/dev/null && pwd)/command-scope-lib.sh"
[ -f "$_CS_LIB" ] || _CS_LIB="$HOME/.claude/hooks/command-scope-lib.sh"
# shellcheck source=/dev/null
{ [ -f "$_CS_LIB" ] && . "$_CS_LIB" 2>/dev/null; } || _CS_LIB=""

pub_is_launch() {   # pub_is_launch <команда> → 0, если вызов ЗАПУСКАЕТ publish-public.sh
    local _t="${1:-}"
    [ -n "$_CS_LIB" ] && _t=$(executable_part "$_t" 2>/dev/null) || :
    grep -qE "$PUB_RE" <<< "$_t"
}

pub_is_launch "$CMD" || exit 0
# Отправка наружу — только с --push; сухой прогон проходит свободно, он и есть предъявление.
grep -qE '(^|[[:space:]])--push([[:space:]]|$)' <<< "$CMD" || exit 0

# Расшифровка ТОГО, чей вызов проверяется (D455). Свидетельство сухого прогона лежит в
# расшифровке актора: текст субагента в родительскую не попадает вовсе — замер по трём
# родительским расшифровкам (526, 885 и 1778 строк) дал 0 записей `isSidechain`. Пока страж
# смотрел родительскую, субагент, честно сделавший сухой прогон, предъявить его не мог и
# получал ОТКАЗ уровня 4. Владелец резолва — `hooks/paths-lib.sh`; библиотеки нет либо
# расшифровка актора не найдена — свидетельства нет, то есть отказ, и это строгая сторона.
_PG_PATHS_LIB="${PATHS_LIB:-$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" 2>/dev/null && pwd)/paths-lib.sh}"
[ -f "$_PG_PATHS_LIB" ] || _PG_PATHS_LIB="$HOME/.claude/hooks/paths-lib.sh"
# shellcheck source=/dev/null
[ -f "$_PG_PATHS_LIB" ] && . "$_PG_PATHS_LIB" 2>/dev/null || true
# Граница хода — `turn_user` из библиотеки ввода (D1153); её нет — `true`: сухой прогон хода не виден, и публикация
# отбивается, а не пропускается.
_PG_INPUT_LIB="${INPUT_LIB:-$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" 2>/dev/null && pwd)/hook-input-lib.sh}"
[ -f "$_PG_INPUT_LIB" ] || _PG_INPUT_LIB="$HOME/.claude/hooks/hook-input-lib.sh"
[ -f "$_PG_INPUT_LIB" ] && . "$_PG_INPUT_LIB" 2>/dev/null || true
if command -v resolve_actor_transcript >/dev/null 2>&1; then
    TRANSCRIPT=$(resolve_actor_transcript "$INPUT")
else
    TRANSCRIPT=$(printf '%s' "$INPUT" | jq -r '.transcript_path // ""' 2>/dev/null)
fi

# Был ли в ЭТОМ ходе сухой прогон того же скрипта. Ход — после последней реплики
# собеседника, та же граница, что у контура разбора причин.
DRY_SEEN=0
if [ -n "$TRANSCRIPT" ] && [ -f "$TRANSCRIPT" ]; then
    # jq отдаёт КОМАНДЫ хода, а роль «это запуск скрипта» решает `pub_is_launch` — та же
    # функция, что судит текущий вызов. Прежде здесь стоял свой `test($pub)`, и он расходился
    # с грепом выше на одном и том же тексте.
    DRY_SEEN=0
    while IFS= read -r _enc; do
        [ -n "$_enc" ] || continue
        _c=$(printf '%s' "$_enc" | python3 -c 'import json,sys;sys.stdout.write(json.load(sys.stdin))' 2>/dev/null) || continue
        # Сухой прогон — это запуск БЕЗ отправки наружу.
        grep -qE '(^|[[:space:]])--push([[:space:]]|$)' <<< "$_c" && continue
        pub_is_launch "$_c" && DRY_SEEN=$((DRY_SEEN + 1))
    done < <(jq -rs "${HIL_TURN_USER_JQ:-def turn_user: true;}"'
        def role(x): if (x.type // "") == "api-request-blob" then "" else (x.message.role // x.role // "") end;  # копия запроса — не ответ модели (D1346)
        def blocks(x): (x.message.content // x.content // []) as $c |
            if ($c | type) == "array" then $c else [] end;
        def get_text(x): (x.message.content // x.content // []) as $c |
            if ($c | type) == "array" then ($c | map(select(.type == "text") | .text) | join("\n"))
            elif ($c | type) == "string" then $c else "" end;
        . as $items | (length) as $n |
        ([range(0; $n) | ($n - 1 - .)
          | select($items[.] | turn_user)]
          | first) as $pu |
        (if $pu == null then 0 else $pu + 1 end) as $from |
        [range($from; $n) | $items[.]
         | select(role(.) == "assistant") | blocks(.)[]
         | select(.type == "tool_use" and (.name == "Bash"))
         | (.input.command // "") | @json] | .[]' "$TRANSCRIPT" 2>/dev/null)
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
