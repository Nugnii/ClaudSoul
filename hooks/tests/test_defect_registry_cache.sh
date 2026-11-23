#!/usr/bin/env bash
# СУДИТ: scripts/defect-class-carriers.py
# test_defect_registry_cache.sh — память реестра о своём входе не искажает ответ.
#
# Предмет: `scripts/defect-class-carriers.py` считает ВСЕ роды при любом вызове, а на границе
# хода его зовут трижды (показания родов F, G, H). Кэш по состоянию входа убирает два прогона
# из трёх. Ноги охраняют то, чем кэш опасен: он может соврать.
set -uo pipefail
DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$DIR/../.." && pwd)"
DCC="$ROOT/scripts/defect-class-carriers.py"
PASS=0; FAIL=0
ok() { PASS=$((PASS + 1)); }
bad() { FAIL=$((FAIL + 1)); echo "FAIL [$1]: $2"; }

STATE_TMP=$(mktemp -d)
export STATE_DIR="$STATE_TMP"
CACHE="$STATE_TMP/defect-class-carriers-cache.json"

# T1: кэш создаётся и им пользуются.
python3 "$DCC" --genus F >/dev/null 2>&1 || true  # реестр родов отвечает 1, когда носители есть: это штатный ответ прибора, а не отказ
if [ -s "$CACHE" ]; then ok; else bad "T1" "кэш не создан по адресу $CACHE"; fi

# T2: ответ ИЗ КЭША тождествен ответу, посчитанному заново. Это главная нога: кэш, который
# отдаёт другое, хуже отсутствующего — он врёт молча.
for g in F G H C I; do
    cached=$(python3 "$DCC" --genus "$g" 2>&1); crc=$?
    fresh=$(DCC_NO_CACHE=1 python3 "$DCC" --genus "$g" 2>&1); frc=$?
    if [ "$cached" = "$fresh" ] && [ "$crc" = "$frc" ]; then ok
    else bad "T2/$g" "ответ из кэша разошёлся со счётом (rc $crc против $frc)"; fi
done

# T3–T5 идут в ПРОБНОМ репозитории, а не в рабочем дереве (род H, D376): прежде T3 трогал
# mtime первого файла индекса, T4 — самого реестра, T5 дописывал и снимал строку в живом
# файле, и умри прогон между записью и снятием — правка осталась бы в дереве. Предмет ног —
# ключ кэша, и ему всё равно, чьё дерево: реестру хватает install.sh и каталога hooks/.
# Жертва по-прежнему берётся из ВСЕГО множества отслеживаемых файлов пробы (первый файл
# индекса), а не из hooks/*.sh — ключ покрывает всё дерево. Образец пробы — D360.
TMP_PROBE=$(mktemp -d)   # временное уберёт система
mkdir -p "$TMP_PROBE/scripts" "$TMP_PROBE/hooks"
cp "$DCC" "$TMP_PROBE/scripts/"; cp "$ROOT/install.sh" "$TMP_PROBE/"
printf '#!/usr/bin/env bash\necho x\n' > "$TMP_PROBE/hooks/probe.sh"
git -C "$TMP_PROBE" init -q && git -C "$TMP_PROBE" add -A && git -C "$TMP_PROBE" -c user.name=t -c user.email=t@t commit -qm x
PDCC="$TMP_PROBE/scripts/defect-class-carriers.py"
export STATE_DIR="$STATE_TMP/probe"; mkdir -p "$STATE_DIR"
PCACHE="$STATE_DIR/defect-class-carriers-cache.json"
_key() { python3 - "$PCACHE" <<'PY'
import json, sys
try: print(json.load(open(sys.argv[1], encoding="utf-8")).get("key", ""))
except Exception: print("")
PY
}
VF=$(git -C "$TMP_PROBE" ls-files | head -1)

# T3: КОНТРПРИМЕР — правка отслеживаемого файла обесценивает кэш. Без этой ноги кэш мог бы
# держать вечный ответ, и почищенный род продолжал бы показывать прежних носителей.
# Время ставится фиксированным, а не «сейчас»: файл создан мгновение назад, и на ФС с
# грубым разрешением mtime «сейчас» могло бы совпасть с прежним.
python3 "$PDCC" --genus F >/dev/null 2>&1 || true  # тот же штатный 1 у прогрева кэша: носители в дереве есть
KEY_BEFORE=$(_key)
touch -t 202001010000 "$TMP_PROBE/$VF"
python3 "$PDCC" --genus F >/dev/null 2>&1 || { echo "подготовка мира не удалась: hooks/tests/test_defect_registry_cache.sh:$LINENO" >&2; exit 1; }
KEY_AFTER=$(_key)
if [ -n "$KEY_BEFORE" ] && [ "$KEY_BEFORE" != "$KEY_AFTER" ]; then ok
else bad "T3" "правка отслеживаемого файла НЕ обесценила кэш (ключ «${KEY_BEFORE}» остался)"; fi

# T4: КОНТРПРИМЕР — правка самого реестра обесценивает кэш. Иначе изменённый признак рода
# продолжал бы отдавать прежний ответ, и правку было бы не увидеть.
touch -t 202001010000 "$PDCC"
python3 "$PDCC" --genus F >/dev/null 2>&1 || { echo "подготовка мира не удалась: hooks/tests/test_defect_registry_cache.sh:$LINENO" >&2; exit 1; }
KEY_SELF_AFTER=$(_key)
if [ "$KEY_AFTER" != "$KEY_SELF_AFTER" ]; then ok
else bad "T4" "правка самого реестра НЕ обесценила кэш"; fi

# T5: РАЗМЕР в ключ не входит намеренно. Механизмы границы хода правят файлы, сохраняя mtime
# (контракт backlog-refresh-readings.sh), и с размером в ключе кэш промахивался на КАЖДОЙ
# границе хода — то есть не работал вовсе. Нога держит именно это решение.
python3 "$PDCC" --genus F >/dev/null 2>&1 || { echo "подготовка мира не удалась: hooks/tests/test_defect_registry_cache.sh:$LINENO" >&2; exit 1; }
K1=$(_key)
python3 - "$TMP_PROBE/$VF" <<'PY'
import os, sys
p = sys.argv[1]
st = os.stat(p)
with open(p, "a", encoding="utf-8") as f:
    f.write("\n# проба размера\n")
os.utime(p, ns=(st.st_atime_ns, st.st_mtime_ns))   # размер изменён, mtime сохранён
PY
python3 "$PDCC" --genus F >/dev/null 2>&1 || { echo "подготовка мира не удалась: hooks/tests/test_defect_registry_cache.sh:$LINENO" >&2; exit 1; }
K2=$(_key)
if [ "$K1" = "$K2" ]; then ok
else bad "T5" "правка с сохранённым mtime обесценила кэш — размер вернулся в ключ, и на границе хода кэш снова не сработает"; fi

rm -rf "$STATE_TMP"
echo ""
echo "defect registry cache: $PASS passed, $FAIL failed"
exit $(( FAIL != 0 ))
