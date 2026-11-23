#!/usr/bin/env bash
# test_pre_compact_finalizer.sh — характеризующий тест PreCompact-финализатора.
# СУДИТ: hooks/pre-compact-finalizer.sh
# Объявлено 20 сентября 2026 (D342), и повод поучителен: предмет был однозначен по индексу,
# пока в свидетель не добавили контроль работы, упомянувший вторую библиотеку
# (`intrusiveness-state-lib.sh` — состояние создаёт её владелец). Упоминание сделало предмет
# неоднозначным, и сторож замороженного реестра `test_witness_subject_declared.sh` поймал
# это на первом же прогоне после правки. Объявление снимает вопрос навсегда.
# Обёртка над intrusiveness-state-lib (покрыта). Финализирует метрики до компакта;
# вывода не даёт. Тест (F8): без state выходит тихо, без SID тихо, не падает.

set -uo pipefail

HOOKS_DIR="$(cd "$(dirname "$0")/.." && pwd)"
HOOK="$HOOKS_DIR/pre-compact-finalizer.sh"
[ -f "$HOOK" ] || { echo "FAIL: $HOOK not found"; exit 1; }
command -v jq >/dev/null 2>&1 || { echo "SKIP: jq недоступен"; exit 0; }

PASS=0
FAIL=0
assert_silent() { if [ -z "$1" ]; then PASS=$((PASS + 1)); else FAIL=$((FAIL + 1)); echo "FAIL [$2]: получено: $1"; fi; }
assert_rc0() { if [ "$1" -eq 0 ]; then PASS=$((PASS + 1)); else FAIL=$((FAIL + 1)); echo "FAIL [$2]: rc=$1"; fi; }

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
mkdir -p "$TMP/state"

run() { printf '{"session_id":"%s"}' "$1" | STATE_DIR="$TMP/state" bash "$HOOK" 2>/dev/null; }

# ПОЛОЖИТЕЛЬНЫЙ КОНТРОЛЬ (D342, 20 сентября 2026): при ЖИВОМ состоянии финализатор обязан
# дописать в историю запись с границей `precompact`. Без него свидетель зеленел и с
# ВЫХОЛОЩЕННЫМ хуком: обе ноги ниже требуют ТИШИНЫ и кода ноль, а заглушка `:` даёт ровно
# это — молчание есть то, что производит мёртвый механизм. Доказательство работы здесь в
# СОСТОЯНИИ МИРА: хук ничего не печатает по устройству (PreCompact), поэтому ни код, ни
# вывод сигналом служить не могут.
if command -v jq >/dev/null 2>&1; then
    # Состояние создаёт ЕГО ВЛАДЕЛЕЦ — `itr_init_state` из hooks/intrusiveness-state-lib.sh,
    # а не эта нога руками: у файла девять ключей (budget, cost_hints, metrics, silence_debt
    # и прочие), и слепленный вручную огрызок валит разбор `jq` в писателе истории. Первая
    # редакция контроля так и сделала и покраснела на ЖИВОМ хуке — контроль судил фикстуру,
    # а не финализатор.
    # ДВЕ ПЕРЕМЕННЫЕ, А НЕ ОДНА, и это поймано прогоном 20 сентября 2026. Хук ЧИТАЕТ
    # состояние из `STATE_DIR` (`hooks/pre-compact-finalizer.sh:49`), а библиотека метрик
    # ПИШЕТ историю в `ITR_STATE_DIR` (`hooks/intrusiveness-state-lib.sh:56`), и вторая от
    # первой НЕ наследуется — у неё свой дефолт `~/.claude/hooks/state`. Имя каталога
    # состояния собрано на каждом конце связи отдельно: корень R1 карты. В бою оба дефолта
    # совпадают, и симптома нет; он виден только в песочнице — род M реестра.
    # Контроль, задавший одну переменную, искал бы запись в песочнице, пока хук писал бы её
    # в настоящее состояние пользователя: краснота на живом хуке плюс мусор в мире.
    ( export ITR_STATE_DIR="$TMP/state"
      . "$HOOKS_DIR/intrusiveness-state-lib.sh"
      itr_init_state "ctl-live" >/dev/null 2>&1 )
    printf '{"session_id":"ctl-live"}' \
      | STATE_DIR="$TMP/state" ITR_STATE_DIR="$TMP/state" bash "$HOOK" >/dev/null 2>&1
    if ! grep -q '"boundary":"precompact"' "$TMP/state/intrusiveness-history.jsonl" 2>/dev/null; then
        echo "FAIL [рамка не собралась]: при живом состоянии финализатор не дописал запись"
        echo "     precompact в историю — значит он не отработал, и тишина на пустом"
        echo "     состоянии ничего не доказывает."
        exit 1
    fi
else
    echo "SKIP: нет jq — контроль работы финализатора непроверяем"
fi

# нет состояния сессии → ранний выход, тишина
out=$(run "sid-without-state"); rc=$?
assert_silent "$out" "T1 no state → silent"
assert_rc0 "$rc" "T1 rc=0"

# без session_id → тишина
out=$(run ""); rc=$?
assert_silent "$out" "T2 no session_id → silent"
assert_rc0 "$rc" "T2 rc=0"

echo ""
echo "pre-compact-finalizer tests: $PASS/$((PASS + FAIL)) passed"
exit $(( FAIL != 0 ))
