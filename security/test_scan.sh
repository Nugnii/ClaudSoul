#!/usr/bin/env bash
# test_scan.sh — обёртка сканеров отвечает РАЗНО на три разных состояния мира.
#
# Результат: «ни один сканер не отработал» и «сканер сломался» не выдаются за чистый прогон.
# Проверка результата: bash security/test_scan.sh даёт 0
#
# Повод, 10 сентября 2026. `scan.sh` объявлял в шапке проверку `test_scan.sh`, которой не
# было ни в репозитории, ни в установке: контракт обещал то, чего не существует. Сам прибор
# при этом устроен верно — его шапка называет дефект, найденный при постройке («без единого
# сканера в PATH печатал ✓ чисто с exit=0»), — но обещанного доказательства у него не было.
#
# Сканеры подменяются заглушками через PATH: тест не зависит от того, установлены ли
# gitleaks/opengrep/trivy на этой машине, и не запускает их по-настоящему.
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SCAN="$ROOT/security/scan.sh"
[ -f "$SCAN" ] || { echo "FAIL: нет $SCAN"; exit 1; }

TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT
P=0; F=0
ok()  { P=$((P+1)); printf '  ✅ %s\n' "$1"; }
bad() { F=$((F+1)); printf '  ❌ %s\n' "$1"; }

BIN="$TMP/bin"; mkdir -p "$BIN"
CLEAN="$TMP/clean"; mkdir -p "$CLEAN"; printf 'def add(a,b):\n    return a+b\n' > "$CLEAN/a.py"

# Заглушка gitleaks: <режим> задаётся файлом $TMP/mode — ok (пустой отчёт) либо broken.
cat > "$BIN/gitleaks" <<'STUB'
#!/usr/bin/env bash
case "$(cat "$TMPDIR_STUB/mode" 2>/dev/null)" in
  broken) echo "boom" >&2; exit 3 ;;
esac
out=""; prev=""
for a in "$@"; do [ "$prev" = "--report-path" ] && out="$a"; prev="$a"; done
[ -n "$out" ] && printf '[]' > "$out"
exit 0
STUB
chmod +x "$BIN/gitleaks"

run() {  # run <mode> <target> → печатает "код|вывод"
    printf '%s' "$1" > "$TMP/mode"
    o=$(PATH="$BIN:/usr/bin:/bin" TMPDIR_STUB="$TMP" bash "$SCAN" --fast "$2" 2>&1)
    printf '%s|%s' "$?" "$o"
}

echo "── три состояния прибора ──"

# 1. Инструментов нет вовсе: это НЕ «чисто», это отсутствие проверки.
o=$(PATH="/usr/bin:/bin" bash "$SCAN" --fast "$CLEAN" 2>&1); rc=$?
if [ "$rc" = "2" ] && grep -q 'НЕ БЫЛО' <<< "$o"; then ok "сканеров нет → код 2 и сказано вслух"
else bad "сканеров нет: код=$rc, вывод=${o:0:70}"; fi

# 2. Сканер сломался: молчание тут читалось бы как «чисто».
r=$(run broken "$CLEAN"); rc="${r%%|*}"; o="${r#*|}"
if [ "$rc" = "2" ] && grep -q 'сломались' <<< "$o"; then ok "сканер сломался → код 2 и назван"
else bad "сломанный сканер: код=$rc, вывод=${o:0:70}"; fi

# 3. Отработал, находок нет — молчать нельзя совсем, но код 0.
r=$(run ok "$CLEAN"); rc="${r%%|*}"; o="${r#*|}"
if [ "$rc" = "0" ] && grep -q 'чисто' <<< "$o"; then ok "отработал без находок → код 0"
else bad "чистый прогон: код=$rc, вывод=${o:0:70}"; fi

# 4. Число отработавших слоёв названо: «слоёв отработало: 0» и «чисто» вместе невозможны.
if grep -q 'слоёв отработало: [1-9]' <<< "$o"; then ok "число отработавших слоёв предъявлено"
else bad "в чистом прогоне не названо, сколько слоёв отработало: ${o:0:70}"; fi

# 5. Несуществующий путь — отказ, а не молчаливый ноль.
o=$(PATH="$BIN:/usr/bin:/bin" TMPDIR_STUB="$TMP" bash "$SCAN" --fast "$TMP/нет-такого" 2>&1); rc=$?
if [ "$rc" = "2" ]; then ok "несуществующий путь → код 2"
else bad "несуществующий путь: код=$rc"; fi

echo
echo "прошло $P, провалено $F"
exit $(( F != 0 ))
