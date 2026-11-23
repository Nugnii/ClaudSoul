#!/usr/bin/env bash
# test_secret_guard.sh — проверка secret-guard на ОБОИХ классах.
# Отказ проверяется не только тем, что срабатывает, но и тем, что НЕ срабатывает
# на рабочем коде: страж уровня 4 с ложными обязан вернуться на уровень подсказки.
set -uo pipefail
# Проверяется РЕПОЗИТОРНЫЙ хук, а не установленный (10 сентября 2026). Прежде здесь стоял
# `$HOME/.claude/hooks/secret-guard.sh`, и рамка проверки была смещена в обе стороны:
# правка репозитория тестом не проверялась вовсе, а правка установки красила репозиторный
# тест зелёным (`pattern-verification-frame-mismatch`). Адрес пришёл из контракта самого
# хука, а тот импортирован из чужой установки целиком, вместе с адресами. Из 415 тестов
# набора установку адресуют два, законен один — `drift-check.sh` сверяет копии по назначению.
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
H="$ROOT/hooks/secret-guard.sh"
# Страж по правилу «инструмента здесь нет — молчать» выходит без решения, когда нет gitleaks;
# без него все шесть ног «должен отказать» красны не о страже, а о машине (CI, контейнер —
# 12 сентября 2026). Пропуск НАЗВАН, как у соседей.
command -v jq >/dev/null 2>&1 || { echo "SKIP: нет jq"; exit 0; }
command -v gitleaks >/dev/null 2>&1 || { echo "SKIP: нет gitleaks — страж секретов здесь не измерен"; exit 0; }
[ -f "$H" ] || { echo "FAIL: нет $H"; exit 1; }
# Свой временный файл на прогон: `run_all.sh` гоняет до восьми тестов параллельно, а
# фиксированный `/tmp/_sg.out` у них был бы общим — вывод одного попадал бы в разбор другого.
OUT_TMP=$(mktemp); trap 'rm -f "$OUT_TMP"' EXIT
P=0; F=0
rnd() { LC_ALL=C tr -dc 'A-Za-z0-9' < /dev/urandom | head -c "$1"; }

run() {  # run <tool> <file_path> <content> → печатает permissionDecision или "-"
  # Пустой вывод хука = он промолчал = не отказал. Читать это надо явно:
  # jq на пустом входе отдаёт пустую строку, а не ветку `// "-"`, и тест
  # засчитывает молчание как провал. Дефект найден собственным прогоном.
  jq -n --arg t "$1" --arg f "$2" --arg c "$3" \
    '{tool_name:$t, tool_input:{file_path:$f, content:$c}}' \
  | bash "$H" 2>/dev/null > "$OUT_TMP"
  if [ ! -s "$OUT_TMP" ]; then
    printf -- '-'
  else
    jq -r '.hookSpecificOutput.permissionDecision // "-"' "$OUT_TMP" 2>/dev/null || printf -- '-'
  fi
}
chk() { if [ "$2" = "$3" ]; then echo "  ✅ $1"; P=$((P+1)); else echo "  ❌ $1 (ждали $3, вышло $2)"; F=$((F+1)); fi; }

echo "── должен ОТКАЗАТЬ ──"
chk "AWS key"        "$(run Write /tmp/a.py "AWS = \"AKIA3KJH2LK4J5HG6PQR\"")"          deny
chk "GitHub PAT"     "$(run Write /tmp/a.py "T = \"ghp_$(rnd 36)\"")"                    deny
chk "Anthropic key"  "$(run Write /tmp/a.py "K = \"sk-ant-api03-$(rnd 95)\"")"           deny
chk "OpenAI key"     "$(run Write /tmp/a.py "K = \"sk-proj-$(rnd 74)T3BlbkFJ$(rnd 74)\"")" deny
chk "Edit, не Write" "$(jq -n --arg s "AWS = \"AKIA3KJH2LK4J5HG6PQR\"" \
                        '{tool_name:"Edit", tool_input:{file_path:"/tmp/a.py", new_string:$s}}' \
                        | bash "$H" 2>/dev/null | jq -r '.hookSpecificOutput.permissionDecision // "-"')" deny

# NotebookEdit объявлен в универсуме хука, и его поля зовутся ИНАЧЕ: `notebook_path` вместо
# `file_path`, `new_source` вместо `content`. До 10 сентября 2026 ни одно из них не читалось,
# `NEW` выходил пустым, и тот же секрет, что через Write даёт отказ, в тетрадь проходил молча.
chk "NotebookEdit"   "$(jq -n --arg s "AWS = \"AKIA3KJH2LK4J5HG6PQR\"" \
                        '{tool_name:"NotebookEdit", tool_input:{notebook_path:"/tmp/a.ipynb", new_source:$s}}' \
                        | bash "$H" 2>/dev/null | jq -r '.hookSpecificOutput.permissionDecision // "-"')" deny

echo "── НЕ должен трогать (ложный отказ дороже пропуска) ──"
chk "обычный код"    "$(run Write /tmp/a.py "def add(a, b):\n    return a + b")"         -
chk "UUID сессии"    "$(run Write /tmp/s.jsonl "{\"key\": \"$(uuidgen 2>/dev/null || python3 -c 'import uuid; print(uuid.uuid4())')\", \"n\": 1}")"    -
chk "хеш в json"     "$(run Write /tmp/c.json "{\"key\": \"$(rnd 64)\"}")"                -
chk ".env.example"   "$(run Write /tmp/.env.example "AWS = \"AKIA3KJH2LK4J5HG6PQR\"")"   -
chk "testdata/"      "$(run Write /tmp/testdata/x.py "AWS = \"AKIA3KJH2LK4J5HG6PQR\"")"  -
chk "чужой tool"     "$(run Bash /tmp/a.py "AWS = \"AKIA3KJH2LK4J5HG6PQR\"")"            -

echo
echo "прошло $P, провалено $F"
exit $(( F != 0 ))
