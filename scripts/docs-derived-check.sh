#!/usr/bin/env bash
# docs-derived-check.sh — производная языковая версия не отстаёт от источника, и отставание названо поимённо.
#
# Результат: перед публикацией ни один производный документ не отстаёт от источника; в работе
#            отставание видно поимённо и не красит чужие сверщики
# Проверка результата: bash hooks/tests/test_docs_derived.sh даёт 0
#
# Применение (роль CLI владельца объявлена здесь — законный потребитель по mechanism-has-consumer):
#   bash scripts/docs-derived-check.sh                  # сверка: 0 — свежи или производных нет, 1 — отстали, 2 — сломан
#   bash scripts/docs-derived-check.sh list             # каждый производный документ и его состояние
#   bash scripts/docs-derived-check.sh stale            # только имена отставших — для сверщиков, которые их пропускают
#   bash scripts/docs-derived-check.sh fresh            # только имена свежих — снимок ДО прогона генератора чисел
#   bash scripts/docs-derived-check.sh stamp <файл> [<источник>]
#       после пересборки перевода: записать хеш источника в шапку; источник по умолчанию —
#       тот, что уже в шапке, либо <файл без .md>.ru.md рядом
#
# Потребители в коде: scripts/publish-public.sh (предусловие — отказ на отставшем или сломанном),
# scripts/docs-refresh-claims.sh, scripts/docs-inventory.sh, scripts/docs-staleness.sh,
# hooks/docs-family-check.sh (пропуск отставшего производного в работе — с названным числом).
#
# Три состояния прибора: производных нет — одна строка и 0 (нет предмета, не отказ); сломан
# (шапка есть, источника нет) — 2 и имя; отстал — 1, имя, оба хеша и команда пересборки.
# Библиотеки нет — 2 и «НЕ ИЗМЕРЕНО»: это свой инструмент, его отсутствие есть поломка.
set -uo pipefail

REPO="${CLAUDSOUL_REPO:-$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")/.." 2>/dev/null && pwd -P)}"
LIB="$REPO/hooks/docs-derived-lib.sh"
[ -f "$LIB" ] || { echo "docs-derived-check: нет $LIB — отставание переводов НЕ ИЗМЕРЕНО" >&2; exit 2; }
# shellcheck source=../hooks/docs-derived-lib.sh
. "$LIB"
export DOCS_DERIVED_ROOT="$REPO"
cd "$REPO" || exit 2

MODE="${1:-check}"
case "$MODE" in
    check|list|stale|fresh) ;;
    stamp)
        f="${2:-}"; src="${3:-}"
        [ -n "$f" ] || { echo "применение: $0 stamp <производный> [<источник>]" >&2; exit 2; }
        [ -f "$REPO/$f" ] || { echo "нет файла $f" >&2; exit 2; }
        if [ -z "$src" ]; then
            src=$(docs_derived_source "$REPO/$f" 2>/dev/null || true)
            if [ -z "$src" ]; then _c="${f%.md}.ru.md"; [ -f "$REPO/$_c" ] && src="$_c"; fi
        fi
        [ -n "$src" ] || { echo "источник для $f не назван, и рядом нет ${f%.md}.ru.md" >&2; exit 2; }
        docs_derived_stamp "$REPO/$f" "$src" || { echo "не удалось записать шапку в $f (источник $src)" >&2; exit 2; }
        echo "записано: $f ← $src@$(docs_derived_recorded_hash "$REPO/$f")"
        exit 0 ;;
    *) echo "применение: $0 [check|list|stale|fresh|stamp <файл> [<источник>]]" >&2; exit 2 ;;
esac

fresh=0; stale=0; broken=0; total=0; lines=""
while IFS= read -r p; do
    [ -n "$p" ] || continue
    total=$((total + 1))
    st=$(docs_derived_state "$REPO/$p")
    src=$(docs_derived_source "$REPO/$p" 2>/dev/null || true)
    case "$st" in
        fresh)  fresh=$((fresh + 1))
                if [ "$MODE" = fresh ]; then echo "$p"
                elif [ "$MODE" = list ]; then lines="$lines  ✓ свеж:   $p ← $src"$'\n'
                fi ;;
        stale)  stale=$((stale + 1))
                if [ "$MODE" = stale ]; then echo "$p"; elif [ "$MODE" = fresh ]; then :; else
                    lines="$lines  ✗ отстал: $p ← $src (в шапке $(docs_derived_recorded_hash "$REPO/$p"), источник $(docs_derived_hash "$REPO/$src")) — пересобери перевод и запиши: bash scripts/docs-derived-check.sh stamp $p"$'\n'
                fi ;;
        broken) broken=$((broken + 1))
                case "$MODE" in stale|fresh) ;; *) lines="$lines  ✗ сломан: $p — источник ${src:-?} не найден или не читается"$'\n' ;; esac ;;
    esac
done <<EOF
$(docs_derived_list "$REPO")
EOF

case "$MODE" in stale|fresh) exit 0 ;; esac   # перечень для потребителей — не вердикт
if [ "$total" -eq 0 ]; then echo "производных документов нет"; exit 0; fi
echo "производных документов: $total — свежих $fresh, отставших $stale, сломанных $broken"
printf '%s' "$lines"
[ "$broken" -gt 0 ] && exit 2
[ "$stale" -gt 0 ] && exit 1
exit 0
