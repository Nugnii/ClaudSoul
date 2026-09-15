#!/usr/bin/env bash
# test_completion_gate_hostile_backlog.sh — характеризующий тест D244.
# Держит границу доверия: команда «Проверки» исполняется через `bash -c`, значит строка
# из markdown становится вызовом. Путь, пришедший из cwd сессии, — вход извне.
#
# Ловушка теста: «не исполняет» легко получить, отключив исполнение вовсе. Поэтому рядом
# с враждебным случаем стоит ПОЛОЖИТЕЛЬНЫЙ КОНТРОЛЬ — явно названный бэклог обязан
# исполниться, иначе страж починен ценой собственной работы.
set -uo pipefail
REPO="$(cd "$(dirname "$0")/../.." && pwd)"
GATE="$REPO/hooks/completion-gate.sh"
[ -f "$GATE" ] || { echo "FAIL: $GATE not found"; exit 1; }

PASS=0; FAIL=0
ok()  { PASS=$((PASS+1)); }
bad() { FAIL=$((FAIL+1)); echo "FAIL [$1]: $2"; }

TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT
mkdir -p "$TMP/evil" "$TMP/state"
printf '# Чужой проект\n' > "$TMP/evil/CLAUDE.md"
( cd "$TMP/evil" && git init -q . 2>/dev/null )
cat > "$TMP/evil/BACKLOG.md" <<EOF
# BACKLOG чужого проекта

- ☑ **D999** Пункт, который выглядит закрытым.
  **Результат.** Ничего.
  **Проверка.** \`touch $TMP/PWNED\` → 0
EOF

# Присваивание окружения пишется ЛИТЕРАЛОМ перед командой. Первая редакция ставила
# `${2:+CG_LOCAL_BACKLOG="$2"}`: после подстановки это обычное слово, а не присваивание,
# переменная до хука не доходила — положительный контроль краснел на дефекте теста.
# Маркер вложенности гасится ЯВНО: этот тест сам бывает «Проверкой» пункта долга, а
# исполнитель Проверок ставит BACKLOG_CHECKS_NESTED=1 — и гейт выходит первой же строкой.
# Тест тогда проверял бы пустоту и краснел у архиватора, оставаясь зелёным в руках
# (замер 1 сентября 2026: 5/5 напрямую, rc=1 из архиватора). Кольцо этим не открывается:
# фикстура исполняет `touch`, вложенность остаётся глубиной 1.
# Канал — очередь pending-alerts (systemMessage снят 12 сентября 2026: в мобильном клиенте
# рендерится построчно); предмет ног прежний. Очередь и дроссель гейта чистятся перед вызовом.
run_gate() {
    : > "$TMP/state/pending-alerts.txt" 2>/dev/null || true
    rm -f "$TMP/state"/completion-gate-fired-*.jsonl 2>/dev/null || true
    printf '{"session_id":"t-d244","cwd":"%s"}' "$1" \
    | STATE_DIR="$TMP/state" CG_BACKLOG="$TMP/none.md" CG_LOCAL_BACKLOG="${2:-}" \
      BACKLOG_CHECKS_NESTED=0 bash "$GATE" >/dev/null 2>&1
    cat "$TMP/state/pending-alerts.txt" 2>/dev/null; }

# T1-T2: путь из cwd — команда НЕ исполняется, и об этом сказано.
OUT=$(run_gate "$TMP/evil")
[ -f "$TMP/PWNED" ] && bad T1 "команда из чужого BACKLOG.md исполнилась" || ok
grep -q "не исполнено" <<< "$OUT" && ok || bad T2 "пропуск не назван: $OUT"

# T3: молчание тоже дефект — пропуск обязан быть виден, а не проглочен.
grep -q "D244" <<< "$OUT" && ok || bad T3 "в сообщении нет ссылки на пункт: $OUT"

# T4-T5: ПОЛОЖИТЕЛЬНЫЙ КОНТРОЛЬ — путь назван явно, команда обязана исполниться.
rm -f "$TMP/PWNED"; rm -f "$TMP/state"/completion-gate-*.ok
OUT2=$(run_gate "$TMP/evil" "$TMP/evil/BACKLOG.md")
[ -f "$TMP/PWNED" ] && ok || bad T4 "явно названный бэклог не исполнился — страж сломан"
grep -q "не исполнено" <<< "$OUT2" && bad T5 "явный путь помечен недоверенным" || ok

echo "$PASS passed, $FAIL failed"
exit $(( FAIL != 0 ))
