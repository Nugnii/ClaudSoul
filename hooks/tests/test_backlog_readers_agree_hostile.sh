#!/usr/bin/env bash
# test_backlog_readers_agree_hostile.sh — читатели документа долга опознают пункт ТАК ЖЕ,
# как владелец признака (`hooks/backlog-lib.sh`), на ВРАЖДЕБНОЙ фикстуре (D305).
#
# ПОВОД. Признак пункта сведён в библиотеку 3 сентября 2026 для трёх читателей, остальные
# держали свои копии. Замер 6 сентября 2026 по семи читателям
# (completion-gate, backlog-touch-check, backlog-vanish-check, backlog-recheck,
# backlog-refresh-readings, metrics-collector, session-collector): библиотеку берёт ОДИН.
# Страж расхождения (T6 в test_backlog_item_shape.sh) сверяет читателей на БОЕВОМ файле,
# где спорной формы нет, — то есть вторая копия проезжает мимо стража, заведённого против
# вторых копий.
#
# ПРЕДМЕТ — РАСХОЖДЕНИЕ НА ФОРМЕ, КОТОРУЮ БОЕВОЙ ФАЙЛ СЕГОДНЯ НЕ СОДЕРЖИТ:
#   · пункт-ОБРАЗЕЦ внутри забора кода — библиотека его снимает, копия видит пунктом;
#   · идентификатор вне D-нумерации рядом со ссылкой на чужой живой номер — библиотека
#     отдаёт X1, копия `re.search(r"D(\d+)")` винит D284.
# Обе формы законны и живут в настоящем BACKLOG.md (контракт пункта показан забором кода,
# в архиве 30 пунктов из 255 вне D-нумерации).

set -uo pipefail

HOOKS_DIR="$(cd "$(dirname "$0")/.." && pwd)"
REPO="$(cd "$HOOKS_DIR/.." && pwd)"
command -v jq >/dev/null 2>&1 || { echo "SKIP: нет jq"; exit 0; }
command -v python3 >/dev/null 2>&1 || { echo "SKIP: нет python3"; exit 0; }
# shellcheck source=/dev/null
. "$HOOKS_DIR/backlog-lib.sh"

PASS=0; FAIL=0
# Фикстура — ВНЕ /tmp намеренно (как в test_backlog_touch_check.sh): страж правки отбрасывает
# `*/tmp/*` как черновик, а `mktemp -d` на Linux даёт именно /tmp — H2 краснел на CI при
# зелёном macOS (/var/folders/…), 12 сентября 2026.
TMP=$(mktemp -d "${HOME}/.claudsoul-test-hostile.XXXXXX"); trap 'rm -rf "$TMP"' EXIT
mkdir -p "$TMP/state" "$TMP/proj"

ok()   { PASS=$((PASS+1)); }
bad()  { FAIL=$((FAIL+1)); echo "FAIL [$1]: $2"; }

# Фикстура собирается питоном: маркеры забора кода внутри heredoc оболочки читаются
# как разметка самим редактором, и собрать её кавычками надёжнее одним куском.
python3 - "$TMP/BACKLOG.md" <<'PY'
import sys
fence = "`" * 3
open(sys.argv[1], "w", encoding="utf-8").write("\n".join([
    "# BACKLOG (фикстура)",
    "",
    "**Легенда статусов:** ☐ todo · ◐ in-progress",
    "",
    "Контракт пункта показывается забором кода:",
    "",
    fence,
    "- ☐ **D960** ОБРАЗЕЦ внутри забора — пунктом не является",
    "  **Дефект.** образец называет hostile-marker.txt",
    "  **Показание.** `echo 1`",
    fence,
    "",
    "- ☐ **D961** настоящий открытый пункт",
    "  **Дефект.** тело называет hostile-marker.txt, строки «Проверка» у пункта нет.",
    "- Статус:     ☑ done — строка ТЕЛА пункта: префикс списка есть, метка не первая,",
    "  идентификатора нет. Свободный признак «метка где угодно» зовёт её пунктом и рвёт",
    "  блок надвое, унося показание НАСТОЯЩЕГО пункта в чужой блок.",
    "  **Показание.** `echo 2`",
    "  **Последнее показание (2026-09-06).** 2",
    "",
    "- ☑ **X1** закрыт по образцу D284 — идентификатор вне D-нумерации",
    "  **Результат.** пункт закрыт, а команда красная",
    "  **Проверка.** `false` → 0",
    "",
]))
PY

# --- эталон: что видит ВЛАДЕЛЕЦ признака ---
LIB_IDS=$(backlog_ids "$TMP/BACKLOG.md" | tr '\n' ' ')
case " $LIB_IDS " in
    *" D960 "*) bad "H0 эталон" "библиотека сама считает образец в заборе пунктом: $LIB_IDS" ;;
    *) ok ;;
esac
case " $LIB_IDS " in
    *" X1 "*) ok ;;
    *) bad "H0 эталон" "библиотека не видит идентификатор вне D-нумерации: $LIB_IDS" ;;
esac

# --- H1/H3: гейт закрытия ---
# Канал — очередь pending-alerts (systemMessage снят 12 сентября 2026: в мобильном клиенте
# рендерится построчно); предмет ног прежний.
printf '{"session_id":"bra1","cwd":"%s"}' "$TMP/proj" \
    | env -u BACKLOG_CHECKS_NESTED CG_BACKLOG="$TMP/BACKLOG.md" CG_LOCAL_BACKLOG="" \
      STATE_DIR="$TMP/state" bash "$HOOKS_DIR/completion-gate.sh" >/dev/null 2>&1
GATE_OUT=$(cat "$TMP/state/pending-alerts.txt" 2>/dev/null)

if grep -q 'D960' <<< "$GATE_OUT"; then
    bad "H1 гейт видит образец в заборе" "названо D960 — забор кода не снят"
else ok; fi

if grep -q 'D284' <<< "$GATE_OUT"; then
    bad "H3 гейт винит чужой номер" "названо D284 вместо X1 — идентификатор взят по виду"
else ok; fi
if grep -q 'X1' <<< "$GATE_OUT"; then ok
else bad "H3 гейт не назвал пункт" "X1 не назван, хотя его «Проверка» красная: $(printf '%s' "$GATE_OUT" | head -c 200)"; fi

# --- H2: страж правки (backlog-touch-check) ---
: > "$TMP/proj/hostile-marker.txt"
TOUCH_OUT=$(printf '{"session_id":"bra2","cwd":"%s","tool_name":"Edit","tool_input":{"file_path":"%s"}}' \
        "$TMP/proj" "$TMP/proj/hostile-marker.txt" \
    | env -u BACKLOG_CHECKS_NESTED CLAUDSOUL_ROOT="$TMP" STATE_DIR="$TMP/state" \
      bash "$HOOKS_DIR/backlog-touch-check.sh" 2>/dev/null)
if grep -q 'D960' <<< "$TOUCH_OUT"; then
    bad "H2 страж правки видит образец" "названо D960 — забор кода не снят"
else ok; fi
if grep -q 'D961' <<< "$TOUCH_OUT"; then ok
else bad "H2 страж правки не назвал настоящий пункт" "нет D961 в: $(printf '%s' "$TOUCH_OUT" | head -c 200)"; fi

# --- H5: писатель показаний считает открытые пункты так же, как владелец ---
# У писателя ложное опознание пункта дороже, чем у читателя: он правит чужие строки.
# Образец внутри забора несёт строку «Показание», и читатель без снятия забора считает
# его открытым пунктом — число «открытых» разойдётся с эталоном.
LIB_OPEN=$(backlog_ids "$TMP/BACKLOG.md" "$BACKLOG_OPEN_MARKS" | grep -c .)
REFRESH_OUT=$(CLAUDSOUL_REPO="$REPO" BACKLOG_FILE="$TMP/BACKLOG.md" \
    bash "$REPO/scripts/backlog-refresh-readings.sh" --check 2>&1)
if grep -q 'D960' <<< "$REFRESH_OUT"; then
    bad "H5 писатель видит образец в заборе" "названо D960 — забор кода не снят"
else ok; fi
REFRESH_OPEN=$(printf '%s' "$REFRESH_OUT" | grep -oE 'из [0-9]+ открытых' | grep -oE '[0-9]+' | head -1)
if [ "${REFRESH_OPEN:-x}" = "$LIB_OPEN" ]; then ok
else bad "H5 писатель считает пункты по-своему" "у владельца открытых $LIB_OPEN, у писателя ${REFRESH_OPEN:-нет числа}: $(printf '%s' "$REFRESH_OUT" | head -c 200)"; fi

# H6: показание НАСТОЯЩЕГО пункта писатель обязан увидеть. Форма взята из КОНТРПРИМЕРОВ
# владельца признака (шапка backlog-lib.sh), а не из уже виденных проявлений: строка тела
# «- Статус: ☑ done» пунктом не является (метка не первая, идентификатора нет), и
# свободный признак «метка где угодно», приняв её за пункт, рвёт блок — показание
# настоящего пункта уезжает в чужой закрытый блок и не осматривается вовсе.
REFRESH_SEEN=$(printf '%s' "$REFRESH_OUT" | grep -oE 'осмотрено [0-9]+' | grep -oE '[0-9]+' | head -1)
if [ "${REFRESH_SEEN:-x}" = "1" ]; then ok
else bad "H6 показание пункта потеряно" "осмотрено ${REFRESH_SEEN:-нет числа}, ожидалось 1: $(printf '%s' "$REFRESH_OUT" | head -c 200)"; fi

# --- H4: своей копии признака у читателей нет (замер числом) ---
# Читателей семь; пять из них — линия этой правки, два (metrics-collector, session-collector)
# в неё не входят и называются числом, а не молчанием.
MINE="hooks/completion-gate.sh hooks/backlog-touch-check.sh hooks/backlog-vanish-check.sh
scripts/backlog-refresh-readings.sh scripts/backlog-archive.sh"
OWN=0; OWNLIST=""
for f in $MINE; do
    [ -f "$REPO/$f" ] || continue
    if grep -qE 'backlog_strip_fenced|backlog_id_stream|BACKLOG_ITEM_RE|BACKLOG_ID_TOKEN_RE' "$REPO/$f"; then
        continue
    fi
    OWN=$((OWN+1)); OWNLIST="$OWNLIST $f"
done
if [ "$OWN" -eq 0 ]; then ok
else bad "H4 своя копия признака" "читателей со своей копией: $OWN —$OWNLIST"; fi

echo ""
echo "backlog readers agree (hostile): $PASS/$((PASS + FAIL)) passed"
exit $(( FAIL != 0 ))
