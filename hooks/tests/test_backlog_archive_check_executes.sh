#!/usr/bin/env bash
# test_backlog_archive_check_executes.sh — характеризующий тест: режим `check` архиватора ИСПОЛНЯЕТ команду «Проверки» (аудит B3).
# Результат: закреплено НЫНЕШНЕЕ поведение — `check` запускает команду закрытого пункта (маркер появляется),
#            но не пишет ни BACKLOG.md, ни архив; `run` переносит пункт с зелёной командой (положительный контроль).
# Проверка результата: bash hooks/tests/test_backlog_archive_check_executes.sh даёт 0
#
# ПРЕДЕЛ, А НЕ КОНТРАКТ. Решение от 1 сентября 2026 (`scripts/backlog-archive.sh:390-397`): блокеры
# называются в ОБОИХ режимах, а назвать красную «Проверку» нельзя, не исполнив её, — поэтому `check`
# не является режимом без действий: команда из документа запускается с cwd у бэклога и оставляет
# всё, что оставляет. Аудит `docs/backlog-development-rules-audit.ru.md` §3 назвал это пробой B3.
# Снимает этап W1 того же аудита (§7, «режим без исполнения»): тогда нога T1 ПЕРЕВОРАЧИВАЕТСЯ
# (маркер в `check` НЕ создаётся), а контрактные ноги T2–T4 остаются как есть.
set -uo pipefail

# Рамку задаёт тест, а не окружение (D334): маркер вложенности от completion-gate иначе выводит
# архиватор на дверь `BACKLOG_CHECKS_NESTED`, и красный от рамки неотличим от красного по делу.
unset BACKLOG_CHECKS_NESTED

REPO="$(cd "$(dirname "$0")/../.." && pwd)"
SCRIPT="$REPO/scripts/backlog-archive.sh"
[ -f "$SCRIPT" ] || { echo "FAIL: нет $SCRIPT"; exit 1; }
command -v python3 >/dev/null 2>&1 || { echo "SKIP: нет python3"; exit 0; }
command -v git >/dev/null 2>&1 || { echo "SKIP: нет git"; exit 0; }

PASS=0; FAIL=0
ok()  { PASS=$((PASS + 1)); }
bad() { FAIL=$((FAIL + 1)); echo "FAIL [$1]: $2"; }
TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT
PROJ="$TMP/proj"; STATE="$TMP/state"; mkdir -p "$PROJ" "$STATE"
MARK="$PROJ/audit-marker.txt"

# Свой репозиторий: «файл не изменён» предъявляется `git diff`, а не сравнением хешей на глаз.
git -C "$PROJ" init -q 2>/dev/null || { echo "FAIL: git init не удался"; exit 1; }
cat > "$PROJ/BACKLOG.md" <<'EOF'
# BACKLOG

## Раздел

- ☑ **D901** Закрыт; команда «Проверки» оставляет след (B3).
  **Результат.** След есть.
  **Проверка.** `printf audited > audit-marker.txt`

- ☐ **D902** Открытый, держит раздел.
  **Проверка.** `false` → 0
EOF
printf '# BACKLOG — архив\n' > "$PROJ/ARCH.md"
git -C "$PROJ" add -A && git -C "$PROJ" -c user.name=t -c user.email=t@t commit -qm base >/dev/null 2>&1 \
    || { echo "FAIL: базовый коммит не состоялся"; exit 1; }

arch() {  # <режим> → вывод архиватора на фикстуре
    ( cd "$PROJ" && BACKLOG_FILE="$PROJ/BACKLOG.md" BACKLOG_ARCHIVE="$PROJ/ARCH.md" \
      CLAUDSOUL_REPO="$REPO" STATE_DIR="$STATE" bash "$SCRIPT" "$1" 2>&1 )
}

# --- T0: фундамент — до прогона маркера нет, иначе T1 судит не о прогоне ---
[ ! -e "$MARK" ] && ok || bad "T0" "маркер существует до прогона — фундамента нет"

# --- T1 (B3, ПРЕДЕЛ, не контракт): режим check ИСПОЛНЯЕТ команду «Проверки» — маркер создан ---
# Снимает W1 («режим без исполнения»): тогда эта нога переворачивается — маркера быть НЕ должно.
OUT=$(arch check); RC=$?
if [ -f "$MARK" ] && [ "$(cat "$MARK")" = "audited" ]; then ok
else bad "T1" "check не исполнил команду «Проверки» (маркера нет) — предел B3 снят? Проверь W1 и переверни ногу: $OUT"; fi
# T1b (контракт режима, W1 не трогает): есть что переносить — код 1.
[ "$RC" -eq 1 ] && ok || bad "T1b" "check с накопленным закрытием вернул $RC, а не 1: $OUT"

# --- T2 (B3, контракт, W1 не трогает): check не пишет BACKLOG.md ---
git -C "$PROJ" diff --quiet -- BACKLOG.md && ok || bad "T2" "режим check изменил BACKLOG.md"
grep -q 'D901' "$PROJ/BACKLOG.md" && ok || bad "T2b" "режим check унёс закрытый пункт из BACKLOG.md"

# --- T3 (B3, контракт, W1 не трогает): check не пишет архив ---
git -C "$PROJ" diff --quiet -- ARCH.md && ok || bad "T3" "режим check записал в архив"

# --- T4 (положительный контроль): run переносит пункт с зелёной командой ---
# Без него «check ничего не пишет» проходило бы и на онемевшем архиваторе.
rm -f "$MARK"
OUT=$(arch run); RC=$?
[ "$RC" -eq 0 ] && ok || bad "T4" "run с зелёной «Проверкой» вернул $RC: $OUT"
grep -q 'D901' "$PROJ/ARCH.md" && ok || bad "T4b" "run не перенёс D901 в архив: $OUT"
grep -q 'D901' "$PROJ/BACKLOG.md" && bad "T4c" "run оставил закрытый D901 в BACKLOG.md" || ok
grep -q 'D902' "$PROJ/BACKLOG.md" && ok || bad "T4d" "run унёс ОТКРЫТЫЙ D902"
# T4e (контракт, не предел): run исполняет команду — так «Проверка» и судится перед переносом.
[ -f "$MARK" ] && ok || bad "T4e" "run не исполнил команду «Проверки» — перенос без суда"

echo "backlog archive check executes: $PASS passed, $FAIL failed"
exit $(( FAIL != 0 ))
