#!/usr/bin/env bash
# accepted-alternative-gap.sh — Stop: принятие варианта собеседника = событие промаха.
# en: Stop hook — detects "your variant is better" acceptance in the assistant's last reply and demands the same gap analysis as external-correction-gap.
#
# Зачем. external-correction-gap ловит пересланную внешнюю рецензию, но класс
# шире: обстоятельство, вскрывшееся в диалоге и меняющее разработку, — тоже
# пойманный чужими руками собственный промах. Момент события — собственная
# фраза принятия («твой вариант лучше», «отличная идея»); она видна только в
# транскрипте на Stop. Поверхность выбрана по своей реплике, а не по словарю
# собеседника: детект своей фразы механический, словарь встречных предложений —
# гадание с гарантированными пропусками. Расширение класса — решение
# собеседника 2026-08-08 (вместе со снятием одноразовости external-correction-gap).
#
# Guards: нет transcript/session → тихо; distressed → тихо (AP2); в той же
# реплике уже есть «гэп-разбор» → молчит (дисциплина исполнена). Throttle нет
# намеренно: каждый акт принятия — отдельное событие.
# Output: jq hookSpecificOutput с additionalContext (advisory, придёт следующим
# ходом — как у output-language-check на Stop).

set -eo pipefail

PATHS_LIB="${PATHS_LIB:-$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/paths-lib.sh}"
if [ -f "$PATHS_LIB" ]; then source "$PATHS_LIB"; else : "${STATE_DIR:=$HOME/.claude/hooks/state}"; fi
# Окно текущего хода (D498): расшифровка читается от последней реплики владельца, а не
# целиком. Библиотеки нет — окно вырождается в файл целиком.
INPUT_LIB="${INPUT_LIB:-$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" 2>/dev/null && pwd)/hook-input-lib.sh}"
[ -f "$INPUT_LIB" ] || INPUT_LIB="$HOME/.claude/hooks/hook-input-lib.sh"
# shellcheck source=/dev/null
if [ -f "$INPUT_LIB" ]; then . "$INPUT_LIB"; fi

PORTABLE_LIB="${PORTABLE_LIB:-$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" 2>/dev/null && pwd)/portable-lib.sh}"
if [ -f "$PORTABLE_LIB" ]; then
    # shellcheck source=/dev/null
    source "$PORTABLE_LIB"
elif [ -f "$HOME/.claude/hooks/portable-lib.sh" ]; then
    # shellcheck source=/dev/null
    source "$HOME/.claude/hooks/portable-lib.sh"
else
    to_lower() { printf '%s' "${1:-}" | tr '[:upper:]' '[:lower:]'; }
fi

command -v jq >/dev/null 2>&1 || exit 0

INPUT=$(cat)
SESSION_ID=$(echo "$INPUT" | jq -r '.session_id // empty' 2>/dev/null)
TRANSCRIPT_PATH=$(echo "$INPUT" | jq -r '.transcript_path // empty' 2>/dev/null)

[ -z "$SESSION_ID" ] && exit 0
[ -n "$TRANSCRIPT_PATH" ] && [ -f "$TRANSCRIPT_PATH" ] || exit 0

# Самозацикливание (класс канарейки, 2026-08-16): additionalContext на Stop
# продолжает ход, а окно детекта «после последней реплики владельца»
# продолжением не очищается — фраза принятия остаётся в окне, алерт
# повторяется бесконечно. Два предохранителя (образец: timestamp-canary-check):
# 1) документированный флаг харнесса «ход уже продолжен Stop-хуком»;
STOP_ACTIVE=$(echo "$INPUT" | jq -r '.stop_hook_active // false' 2>/dev/null)
[ "$STOP_ACTIVE" = "true" ] && exit 0

# Реплики ассистента после последнего сообщения собеседника (образец:
# output-language-check.sh — та же выборка, тот же формат транскрипта).
# Ход берётся из окна хода библиотеки ввода (D1153). Помощника `transcript_turn_window` нет (файла библиотеки нет) — не
# судить: окном был бы весь файл. У старой редакции помощник есть и окно начинается с последней реплики владельца: без
# ядра `HIL_TURN_USER_JQ` его запасное `false` оставляет окно одним ходом — текущим (скептик, третий круг, M1). Ниже
# пишутся только метки этого суждения — глушить нечего лишнего.
command -v transcript_turn_window >/dev/null 2>&1 || exit 0
_TW=$(transcript_turn_window "$TRANSCRIPT_PATH" wide)   # окно от своей границы, а не от реплики (D1235)
# Итог из поля входа Stop достраивает окно, если файл расшифровки его не догнал (D1210, `with_final` библиотеки ввода).
LAM=$(command -v transcript_final_text >/dev/null 2>&1 && transcript_final_text "$INPUT") || LAM=""
PARSED=$(printf '%s\n' "$_TW" | jq -s --arg lam "$LAM" "${HIL_TURN_USER_JQ:-def turn_user: false;}${HIL_WITH_FINAL_JQ:-def with_final(l): .;}"'
    def role(x): x.message.role // x.role // "";
    def get_text(x):
        (x.message.content // x.content // []) as $c |
        if ($c | type) == "array" then
            ($c | map(select(.type == "text") | .text) | join("\n"))
        elif ($c | type) == "string" then $c
        else "" end;
    with_final($lam) | . as $items | (length) as $n |
    ([range(0; $n) | ($n - 1 - .)
      | select($items[.] | turn_user)]
      | first) as $pu |
    {pu: ($pu // -1),
     text: (if $pu == null then
        ([range(0; $n) | $items[.] | select(role(.) == "assistant")]
         | map(get_text(.)) | map(select(. != "")) | join("\n"))
    else
        ([range($pu + 1; $n) | $items[.] | select(role(.) == "assistant")]
         | map(get_text(.)) | map(select(. != "")) | join("\n"))
    end)}
' 2>/dev/null)

PU=$(printf '%s' "$PARSED" | jq -r '.pu // -1' 2>/dev/null)
# Метка хода — не голый индекс во входе (противник окна, атака 1): окно начинается с реплики,
# и индекс там почти всегда 0 — метка «уже сказали» совпала бы со всеми следующими ходами.
# Ход опознаётся первой строкой окна (сама реплика) плюс индексом; окно выродилось в файл —
# первая строка постоянна, а индекс абсолютный.
# ПЕРВАЯ СТРОКА — ЧТЕНИЕМ, А НЕ ПОДСТАНОВКОЙ (D1000, 17 октября 2026). Здесь стояло
# `${_TW%%$'\n'*}`: bash 3.2 в UTF-8 ищет самый длинный хвост перебором позиций, и цена равна
# «длина первой строки × размер окна». Первая строка окна — реплика владельца, со вставленным
# текстом она бывает огромной: 584 КБ × окно 2,3 МБ = 271 с на одной этой строке (трасса по
# строкам в песочнице, сессия 19c775dd), а сосед timestamp-canary-check с той же строкой шёл
# «одинаковое время» — общая строка, а не общий замок. Первую запись отдаёт awk — 0,07 с на том
# же входе. awk, а не `read` из здесь-строки: здесь-строке нужен временный файл, и при отказе его
# создать `read` молча отдавал пустоту — метка хода становилась постоянной, и алерты следующих
# ходов глушились как «уже сказано» (противник, 17 октября 2026); `read` bash 5.2 к тому же
# глотает перевод строки после оборванного многобайтного символа. awk дочитывает ввод до конца —
# производитель не получает SIGPIPE под `pipefail`. Сумма прежняя — 18 краевых входов (пусто, без
# перевода строки, ведущий перевод, CRLF, обратные слэши, кириллица, битый UTF-8) совпали в UTF-8
# и C, поэтому метки «уже сказано» не сбрасываются. Нога T11 теста закрепляет саму метку.
_TW_FIRST=$(printf '%s\n' "$_TW" | awk 'NR == 1')
TURN_ID="$(printf '%s' "$_TW_FIRST" | cksum | awk '{print $1}'):${PU}"
LAST_ASSISTANT=$(printf '%s' "$PARSED" | jq -r '.text // empty' 2>/dev/null)

[ -z "$LAST_ASSISTANT" ] && exit 0
[ "$LAST_ASSISTANT" = "null" ] && exit 0

# 2) маркер «на этот ход владельца уже алертили» (ключ: сессия + позиция
# последней реплики владельца) — не полагается на семантику флага из п.1;
# новая реплика владельца двигает позицию и взводит детектор заново.
MARK="$STATE_DIR/accepted-alt-alerted-${SESSION_ID}"
[ -f "$MARK" ] && [ "$(cat "$MARK" 2>/dev/null)" = "$TURN_ID" ] && exit 0

LOWER=$(to_lower "$LAST_ASSISTANT")

# Маркеры принятия чужого варианта — узко, по своей фразе (правило «узко,
# иначе алерт становится фоном»). Обычное согласие («да», «ок») не ловится.
MATCHED=0
case "$LOWER" in
    *"твой вариант лучше"*|*"ваш вариант лучше"*|*"вариант лучше моего"*|*"лучше моего варианта"*|*"отличная идея"*|*"беру твой вариант"*|*"беру ваш вариант"*) MATCHED=1 ;;
esac
[ "$MATCHED" -eq 0 ] && exit 0

# Дисциплина уже исполнена в той же реплике → молчим
case "$LOWER" in
    *"гэп-разбор"*|*"катчабельн"*) exit 0 ;;
esac

# AP2: в distressed ничего не инжектим
STATE_FILE="$STATE_DIR/intrusiveness-${SESSION_ID}.json"
if [ -f "$STATE_FILE" ]; then
    CURRENT_STATE=$(jq -r '.state.current // "idle"' "$STATE_FILE" 2>/dev/null)
    [ "$CURRENT_STATE" = "distressed" ] && exit 0
fi

MESSAGE="🔁 В прошлой реплике принят вариант/обстоятельство собеседника («твой вариант лучше» / «отличная идея»). Это то же событие, что внешняя рецензия: пойманный чужими руками собственный промах, а не только прогресс. Гэп-разбор, если ещё не сделан:

1. Катчабельно ли принятое внутренним знанием? Если да — назови файл знания и зафиксируй разрыв «знание→действие» (исход через knowledge-counter-bump.sh либо запись applicable_not_followed).
2. Цепочка «почему не предложил сам» — минимум 3 уровня «почему».
3. SESSION.md → Predictions: exact/adjacent/miss + при miss gap:literal/pragmatic/strategic.

Происхождение: case-2026-08-08-ablation-as-maturity-step (расширение класса external-correction-gap)."

mkdir -p "$STATE_DIR" 2>/dev/null
printf '%s' "$TURN_ID" > "$MARK" 2>/dev/null

printf '%s' "$MESSAGE" | jq -Rs '{
  hookSpecificOutput: {
    hookEventName: "Stop",
    additionalContext: .
  }
}'
