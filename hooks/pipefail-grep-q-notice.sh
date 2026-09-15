#!/usr/bin/env bash
# pipefail-grep-q-notice.sh — PreToolUse[Write|Edit|MultiEdit]: пайп в `grep -q` под `set -o pipefail`, чей статус проверяется, назван до записи.
# en: PreToolUse on writes — a pipe into `grep -q` under `set -o pipefail` whose exit status is checked gets reported before the file is written.
#
# Результат: форма, при которой зелёная проверка читается как красная, не попадает в дерево
#            незамеченной; автор видит её ДО записи, а не после прогона.
# Проверка результата: bash hooks/tests/test_pipefail_grep_q_notice.sh даёт 0
#
# ПОВОД — три повтора за одни сутки, 11 сентября 2026, все мои: `lib-prefix-guard.sh` (утро,
# `printf '%s' "$BODY" | grep -q`), ноги T2-T4 в `test_doc_status_consistency.sh` (14:20,
# `check | grep -qi` — три красные ноги при исправном сверщике), нога T6b в
# `test_run_all_parallel.sh` (17:20, `bash run_all.sh | grep -q`).
#
# ПРЕДШЕСТВЕННИК НАЙДЕН И СНЯТ С НЕГО ПРИЗНАК, А НЕ НАПИСАН СВОЙ. Класс заведён пунктом D50
# 31 июля 2026 и закрыт 11 августа стражем `hooks/tests/test_assert_no_sigpipe.sh` — тогда
# вычистили 139 мест в 66 тестах и 114 в 30 хуках. Все три моих случая он ПОЙМАЛ, и каждый
# раз постфактум: он живёт в наборе и краснеет после записи, на полном прогоне. Разрыв не
# в отсутствии механизма, а в МОМЕНТЕ — между чтением правила и его нарушением не было
# ни одной точки, где кто-то говорит «стой». Этот хук добавляет такую точку ДО записи и
# берёт признак у владельца (`SIGPIPE_RE` в том же файле): у факта остаётся один хозяин,
# потребителей два — тест набора и страж момента.
#
# УСТРОЙСТВО ДЕФЕКТА, измерено пробой: `grep -q` выходит на первом совпадении и закрывает
# пайп; производитель получает SIGPIPE и завершается кодом 141; под `pipefail` статус всего
# пайпа становится 141, и УСПЕШНАЯ проверка читается как провал. Проба 11 сентября 2026:
# короткий `printf 'a\nb\n' | grep -q a` → 0 (писатель успевает в буфер), `seq 1 100000 |
# grep -q '^1$'` → 141, `bash -c '…50000 строк' | grep -q` → 141, here-string → 0.
#
# ПОЧЕМУ ПОДСКАЗКА, А НЕ ОТКАЗ. Опасен не сам пайп, а ОБЪЁМ слева, и статически он неизвестен:
# `printf '%s' "$VAR" | grep -q` безопасен при коротком `$VAR` и ломается при длинном. В дереве
# на 11 сентября 2026 таких мест шесть, и все живут годами. Признак с неизмеримой точностью
# уровня отказа не получает (`case-2026-08-28-enforcement-is-a-property-of-consequence`).
#
# СУДИТСЯ ЗАПИСЫВАЕМЫЙ ТЕКСТ, А НЕ ФАЙЛ. Иначе шесть старых мест давали бы подсказку на каждой
# правке своих файлов — страж стал бы фоном, а фон не читают.
set -uo pipefail

PAYLOAD=$(cat 2>/dev/null || true)
FILE=$(printf '%s' "$PAYLOAD" | sed -n 's/.*"file_path"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -1)
case "$FILE" in *.sh) ;; *) exit 0 ;; esac

# Записываемый текст: content (Write) либо new_string (Edit/MultiEdit).
NEW=$(printf '%s' "$PAYLOAD" | python3 -c '
import json, sys
try: d = json.load(sys.stdin)
except Exception: sys.exit(0)
ti = d.get("tool_input", d)
out = []
for k in ("content", "new_string"):
    v = ti.get(k)
    if isinstance(v, str): out.append(v)
for e in ti.get("edits", []) or []:
    v = e.get("new_string")
    if isinstance(v, str): out.append(v)
sys.stdout.write("\n".join(out))
' 2>/dev/null) || NEW=""
[ -n "$NEW" ] || exit 0

# ПРИЗНАК БЕРЁТСЯ У БИБЛИОТЕКИ, КОТОРАЯ УСТАНАВЛИВАЕТСЯ, а не у теста (D393, 11 сентября
# 2026). Первая редакция читала `SIGPIPE_RE` из `hooks/tests/test_assert_no_sigpipe.sh`, и в
# ЧУЖОМ проекте этот страж молчал ВСЕГДА: в установку входят 14 файлов тестов из 437, и
# нужного среди них нет. Проверено вызовом с cwd вне ClaudSoul, а не чтением кода — путь
# строится в момент вызова. Молчание при этом неотличимо от «дефектов нет» (род B).
# Путь — РЯДОМ С СОБОЙ, без корня репозитория: библиотека лежит там же, где сам хук, поэтому
# он работает в любом проекте. Владелец у факта остаётся один: и страж, и тест набора берут
# признак из `token_sigpipe_re`.
PORTABLE_LIB="${PORTABLE_LIB:-$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)/portable-lib.sh}"
# Библиотеки нет — молчим и выходим нулём: «инструмента здесь нет», а не «дефекта нет».
[ -f "$PORTABLE_LIB" ] || exit 0
# shellcheck source=/dev/null
. "$PORTABLE_LIB" 2>/dev/null || exit 0
command -v token_sigpipe_re >/dev/null 2>&1 || exit 0
SIGPIPE_RE=$(token_sigpipe_re)
[ -n "$SIGPIPE_RE" ] || exit 0

# Комментарии и here-string отсеиваются здесь: у владельца своя область (файлы целиком),
# у этого хука — записываемый КУСОК, и в нём форма из комментария встречается чаще.
HITS=$(printf '%s\n' "$NEW" | grep -vE '^[[:space:]]*#' | grep -v '<<<' \
       | grep -E "$SIGPIPE_RE" | head -3)
[ -n "$HITS" ] || exit 0

# Файл без pipefail — дефекта нет: статус пайпа берётся у последней команды, то есть у grep.
case "$NEW" in *"o pipefail"*) ;; *)
    [ -f "$FILE" ] && grep -q 'o pipefail' "$FILE" 2>/dev/null || exit 0 ;;
esac

FIRST=$(printf '%s' "$HITS" | head -1 | sed 's/"/\\"/g' | cut -c1-100)
printf '%s\n' "{\"hookSpecificOutput\":{\"hookEventName\":\"PreToolUse\",\"additionalContext\":\"⚠️ Пайп в grep -q под pipefail, статус проверяется: «${FIRST}». grep выходит на первом совпадении, производитель получает SIGPIPE, статус пайпа 141 — и УСПЕШНАЯ проверка прочитается как провал. Это ловило трижды за 11 сентября 2026. Замена: here-string — grep -q 'что' <<\\\"\$(команда)\\\" — либо вывод в переменную, потом grep по ней.\"}}"
exit 0
