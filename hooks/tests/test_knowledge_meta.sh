#!/usr/bin/env bash
# СУДИТ: hooks/lib/knowledge_meta.py hooks/knowledge-audit-digest.sh
# test_knowledge_meta.sh — записи modification_history: поточная и блочная формы дают одно (D339).
# Результат: у поточной формы и у блочной один счёт и одна последняя kind; пустой список — ноль
#            строк и код 0; файл без шапки — ноль строк; дайджест по поточной форме из трёх записей
#            взводит fragile так же, как по блочной.
# Проверка результата: bash hooks/tests/test_knowledge_meta.sh даёт 0
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
MOD="$ROOT/hooks/lib/knowledge_meta.py"
[ -f "$MOD" ] || { echo "FAIL: нет $MOD"; exit 1; }
command -v python3 >/dev/null 2>&1 || { echo "SKIP: python3 недоступен"; exit 0; }
python3 -c "import yaml" 2>/dev/null || { echo "SKIP: нет PyYAML"; exit 0; }
PASS=0; FAIL=0
ok()  { PASS=$((PASS + 1)); }
bad() { FAIL=$((FAIL + 1)); echo "FAIL [$1]: $2"; }
TMP=$(mktemp -d)   # временное уберёт система (D360)
printf '%s\n' '---' 'name: x' 'modification_history: [{date: 2026-01-01, kind: narrow}, {date: 2026-01-02, kind: rewrite}]' '---' 'тело' > "$TMP/flow.md"
printf '%s\n' '---' 'name: y' 'modification_history:' '  - date: 2026-01-01' '    kind: narrow' '  - date: 2026-01-02' '    kind: rewrite' '---' 'тело' > "$TMP/block.md"
printf '%s\n' '---' 'name: z' 'modification_history: []' '---' 'тело' > "$TMP/empty.md"
printf 'просто текст\n' > "$TMP/none.md"
F=$(python3 "$MOD" "$TMP/flow.md"); B=$(python3 "$MOD" "$TMP/block.md")
[ "$F" = "$B" ] && [ -n "$F" ] && ok || bad "T1" "поточная и блочная формы разошлись: «${F}» против «${B}»"
[ "$(printf '%s\n' "$F" | grep -c .)" = 2 ] && ok || bad "T1b" "счёт записей поточной формы не 2"
[ "$(printf '%s\n' "$F" | tail -n 1 | cut -f2)" = "rewrite" ] && ok || bad "T1c" "последняя kind не rewrite"
E=$(python3 "$MOD" "$TMP/empty.md"); RC=$?
[ "$RC" = 0 ] && [ -z "$E" ] && ok || bad "T2" "пустой список: rc=$RC, вывод «${E}»"
N=$(python3 "$MOD" "$TMP/none.md"); RC=$?
[ "$RC" = 0 ] && [ -z "$N" ] && ok || bad "T3" "файл без шапки: rc=$RC, вывод «${N}»"
python3 "$MOD" >/dev/null 2>&1; [ $? = 2 ] && ok || bad "T4" "без аргумента ожидался код 2"
# T5: дайджест — поточная форма из трёх записей взводит fragile (та же дорога, что у блочной).
# HOME в песочнице подменён, а PyYAML на машине автора живёт в пользовательском site-packages под
# настоящим домом — путь к нему берётся ДО подмены и передаётся PYTHONPATH; на раннере с системным
# PyYAML переменная безвредна.
YAML_PATH=$(python3 -c 'import os, yaml; print(os.path.dirname(os.path.dirname(yaml.__file__)))' 2>/dev/null)
for form in flow block; do
    L="$TMP/lessons-$form"; mkdir -p "$L" "$TMP/state-$form" "$TMP/home-$form"
    if [ "$form" = flow ]; then
        printf '%s\n' '---' 'name: pattern-p' 'confidence: 3' 'fragile: false' 'modification_history: [{date: 2026-01-01, kind: narrow}, {date: 2026-01-02, kind: rewrite}, {date: 2026-01-03, kind: narrow}]' '---' 'тело' > "$L/pattern-p.md"
    else
        printf '%s\n' '---' 'name: pattern-p' 'confidence: 3' 'fragile: false' 'modification_history:' '  - date: 2026-01-01' '    kind: narrow' '  - date: 2026-01-02' '    kind: rewrite' '  - date: 2026-01-03' '    kind: narrow' '---' 'тело' > "$L/pattern-p.md"
    fi
    HOME="$TMP/home-$form" PYTHONPATH="${YAML_PATH}${PYTHONPATH:+:$PYTHONPATH}" LESSONS_DIR="$L" STATE_DIR="$TMP/state-$form" bash "$ROOT/hooks/knowledge-audit-digest.sh" >/dev/null 2>&1 || { echo "подготовка мира не удалась: hooks/tests/test_knowledge_meta.sh:$LINENO" >&2; exit 1; }
    grep -q '^fragile: true' "$L/pattern-p.md" && ok || bad "T5 $form" "дайджест не взвёл fragile у формы $form: $(grep '^fragile' "$L/pattern-p.md")"
done
# T6: без PyYAML модуль отвечает кодом 2 и словами, а не нулём записей — проверяется там, где
# подмена дома действительно прячет yaml (у системного PyYAML состояния «нет модуля» не создать).
if ! HOME="$TMP/home-nope" python3 -c 'import yaml' 2>/dev/null; then
    OUT6=$(HOME="$TMP/home-nope" python3 "$MOD" "$TMP/flow.md" 2>&1); RC=$?
    if [ "$RC" = 2 ] && grep -q "не разобрано" <<< "$OUT6"; then ok; else bad "T6" "без PyYAML: rc=$RC, вывод «${OUT6}» — ожидались код 2 и слова"; fi
    # и дайджест при этом называет неразобранное, а не молчит
    L6="$TMP/lessons-nope"; mkdir -p "$L6" "$TMP/state-nope"; cp "$TMP/flow.md" "$L6/pattern-q.md"
    OUT6D=$(HOME="$TMP/home-nope" LESSONS_DIR="$L6" STATE_DIR="$TMP/state-nope" bash "$ROOT/hooks/knowledge-audit-digest.sh" 2>&1)
    # Подсказки дайджест кладёт в файлы состояния и памяти под HOME, а не только в stdout — ищем везде.
    if grep -q "modification_history не разобран" <<< "$OUT6D" \
       || grep -rq "modification_history не разобран" "$TMP/state-nope" "$TMP/home-nope" "$L6" 2>/dev/null; then ok
    else bad "T6b" "дайджест промолчал о неразобранной истории (stdout, состояние и дом просмотрены)"; fi
fi
echo "knowledge meta: PASS=$PASS FAIL=$FAIL"
exit $(( FAIL != 0 ))
