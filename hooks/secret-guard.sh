#!/usr/bin/env bash
# secret-guard.sh — PreToolUse[Edit|Write|MultiEdit]: секрет, вписываемый в файл, отбивается отказом, а не напоминанием.
# en: PreToolUse[Edit|Write|MultiEdit]: a secret being written into a file is refused, not merely flagged.
#
# Результат: токен, ключ или пароль не попадает в файл через инструменты записи агента.
# Проверка результата: bash hooks/tests/test_secret_guard.sh даёт 0
#
# Почему уровень 4 (отказ), а не инжект. У признака РОВНО ОДНО последствие: строка,
# опознанная gitleaks, — это живой секрет в исходнике, и продолжение записи всегда
# означает утечку. Разных исходов у него нет, значит нет и вилки «напомнить или отбить»
# (case-2026-08-28-enforcement-is-a-property-of-consequence). Для SAST-находок уровень 4
# НЕ ставится: там последствия разные — от «эксплуатируемо» до «тестовая фикстура», —
# и серьёзность решается достижимостью в реальной среде
# (case-2026-08-09-severity-needs-reachability-in-the-real-environment).
#
# Точность признака замерена перед установкой — см. ~/.claude/security/precision.md.
#
# Прибор имеет ТРИ состояния, не два:
#   gitleaks не установлен → молчать и выйти 0 (это другая установка, а не «чисто»)
#   gitleaks сломался      → СКАЗАТЬ и пропустить: молчание тут читается как «чисто»
#   отработал, чисто       → молчать
#
# Переносимость: только POSIX + BSD. Ни timeout, ни realpath, ни sha256sum —
# в macOS их нет (pattern-shell-portability, confirmed 39x).
#
# Input  (stdin): {tool_name, tool_input:{file_path, new_string|content|edits}, ...}
# Output (stdout): {hookSpecificOutput:{permissionDecision:"deny"|"ask", ...}} либо пусто
# Exit:  always 0.
set -uo pipefail

command -v jq >/dev/null 2>&1 || exit 0
command -v gitleaks >/dev/null 2>&1 || exit 0     # инструмента нет — это не «чисто», это молчание

INPUT=$(cat 2>/dev/null) || exit 0
[ -n "$INPUT" ] || exit 0

TOOL=$(printf '%s' "$INPUT" | jq -r '.tool_name // ""' 2>/dev/null)
case "$TOOL" in
  Edit|Write|MultiEdit|NotebookEdit) ;;
  *) exit 0 ;;
esac

# `notebook_path` рядом с `file_path`: у NotebookEdit путь зовётся иначе (10 сентября 2026).
FILE=$(printf '%s' "$INPUT" | jq -r '.tool_input.file_path // .tool_input.notebook_path // ""' 2>/dev/null)

# Файлы, где секрет-подобная строка ОЖИДАЕМА и не является утечкой.
# Список узкий намеренно: широкий превратил бы отказ в решето.
case "$FILE" in
  *.example|*.sample|*.template|*/.env.example|*/.env.sample) exit 0 ;;
  */test/fixtures/*|*/testdata/*|*_test.go|*/tests/fixtures/*) exit 0 ;;
  */.claude/security/*) exit 0 ;;                 # свои же фикстуры и документация
esac

# Содержимое, которое СОБИРАЮТСЯ записать — по всем формам записи.
#
# `new_source` — поле NotebookEdit (10 сентября 2026). Инструмент был объявлен в универсуме
# выше, но НИ ОДНО его поле здесь не читалось: схема у него своя — `notebook_path` вместо
# `file_path` и `new_source` вместо `content`/`new_string`. Итог: `NEW` всегда выходил
# пустым, следующая строка выходила с нулём, и секрет, вписываемый в тетрадь, проходил
# молча — при том что тот же секрет через Write давал отказ. Объявление без чтения полей
# читается как защита, которой нет (`pattern-detector-wired-to-failure`).
NEW=$(printf '%s' "$INPUT" | jq -r '
  .tool_input.content
  // .tool_input.new_string
  // .tool_input.new_source
  // ((.tool_input.edits // []) | map(.new_string // "") | join("\n"))
  // ""' 2>/dev/null)
[ -n "$NEW" ] || exit 0

REPORT=$(mktemp) || exit 0
ERR=$(mktemp) || { rm -f "$REPORT"; exit 0; }
# Конфиг — из установленной копии, а без неё (CI, контейнер, прогон из репозитория) — из
# `security/gitleaks.toml` рядом с репозиторием: единственный адрес `~/.claude` делал страж
# немым на любой машине без установки (12 сентября 2026, решение владельца — gitleaks на CI).
SG_CFG="${SECRET_GUARD_CONFIG:-$HOME/.claude/security/gitleaks.toml}"
[ -f "$SG_CFG" ] || SG_CFG="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")/.." 2>/dev/null && pwd)/security/gitleaks.toml"
printf '%s' "$NEW" | gitleaks stdin -c "$SG_CFG" --no-banner --redact \
  --report-format json --report-path "$REPORT" >/dev/null 2>"$ERR"
RC=$?                                              # exit ИМЕННО gitleaks, до любой трубы

# Сломался — сказать. Молчание здесь неотличимо от «чисто», а это ложно-зелёное.
#
# РАЗЛИЧИТЕЛЬ — НАЛИЧИЕ ОТЧЁТА, а не только код (10 сентября 2026, находка противника).
# До этой правки ветка поломки стояла на `RC -ge 2`, и замер показал, почему это дыра:
# gitleaks 8.30.1 отвечает кодом 1 на ТРИ разных исхода —
#   битый конфиг      → 1, отчёта НЕТ  (FTL unable to load gitleaks config)
#   конфига нет       → 1, отчёта НЕТ
#   секрет найден     → 1, отчёт ЕСТЬ
# Один код на два смысла: первые два уходили в ветку «находок нет», `jq length` по
# несозданному файлу давал 0, и хук молчал. То есть пропажа или порча
# `~/.claude/security/gitleaks.toml` ОТКЛЮЧАЛА страж уровня 4 полностью и беззвучно —
# ровно то ложно-зелёное, против которого он и написан.
# Комментарий `install.sh` при этом утверждал «без файла gitleaks взял бы правила по
# умолчанию»; это неверно и здесь же опровергнуто замером: он не берёт умолчания, он падает.
#
# Признак с ОДНИМ последствием: отчёта нет и код не 0 → инструмент не отработал, слой не
# проверен. Ноль остаётся успехом (при чистом входе отчёт создаётся пустым).
if [ "$RC" -ne 0 ] && [ ! -s "$REPORT" ]; then
  printf '%s' "$INPUT" | jq -n --arg m "⚠️ secret-guard: gitleaks не отработал (exit=$RC, отчёт не создан) — слой секретов НЕ проверен, это не «чисто». Проверь ~/.claude/security/gitleaks.toml. $(head -2 "$ERR" | tr '\n' ' ')" \
    '{hookSpecificOutput:{hookEventName:"PreToolUse", additionalContext:$m}}' 2>/dev/null || true
  rm -f "$REPORT" "$ERR"
  exit 0
fi
if [ "$RC" -ge 2 ]; then
  printf '%s' "$INPUT" | jq -n --arg m "⚠️ secret-guard: gitleaks сломался (exit=$RC) — слой секретов НЕ проверен, это не «чисто». $(head -2 "$ERR" | tr '\n' ' ')" \
    '{hookSpecificOutput:{hookEventName:"PreToolUse", additionalContext:$m}}' 2>/dev/null || true
  rm -f "$REPORT" "$ERR"
  exit 0
fi

N=$(jq 'length' "$REPORT" 2>/dev/null || echo 0)
rm -f "$ERR"

if [ "${N:-0}" -gt 0 ]; then
  RULES=$(jq -r '[.[].RuleID] | unique | join(", ")' "$REPORT" 2>/dev/null)
  LINES=$(jq -r '[.[].StartLine] | join(", ")' "$REPORT" 2>/dev/null)
  rm -f "$REPORT"
  jq -n --arg m "⛔ Секрет в записываемом содержимом: $RULES (строка: $LINES).

Запись отменена — попавший в файл секрет остаётся в истории git даже после удаления.

Что делать вместо этого:
  · значение → в переменную окружения, в файл читается os.environ / process.env
  · пример для репозитория → в .env.example с ЗАГЛУШКОЙ, не с рабочим ключом
  · если это заведомо не секрет (тестовая фикстура) → положи под */testdata/ или *.example,
    там проверка не действует

Если ключ уже настоящий и куда-то ушёл — его нужно отозвать, а не просто стереть." \
    '{hookSpecificOutput:{hookEventName:"PreToolUse", permissionDecision:"deny", permissionDecisionReason:$m}}' 2>/dev/null || true
  exit 0
fi

rm -f "$REPORT"
exit 0
