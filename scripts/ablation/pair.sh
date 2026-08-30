#!/usr/bin/env bash
# pair.sh — завершение и аннулирование теневой тройки (протокол §9, §10).
#
# Единица наблюдения с версии 1.4 — ТРОЙКА плеч (full, core, vanilla) на одной
# задаче. Имена pair/pairs.jsonl/pair_done сохранены от версии 1.3 намеренно:
# журнал, протокол и тесты ссылаются на них взаимно, и переименование ради
# терминологии стоило бы дороже, чем эта строка объяснения.
#
#   complete <task_id> — ВСЕ ТРИ плеча классифицированы, ни одно не
#       infrastructure: бинаризация (success→1, прочее→0), строка в pairs.jsonl
#       (вход pair-analyze), событие pair_done. Страта — из dry_run.
#   annul <task_id> <reason> — инфраструктурный сбой ЛЮБОГО плеча аннулирует
#       попытку ЦЕЛИКОМ (§9): прогоны всех трёх плеч удаляются, снимок остаётся,
#       попытка фиксируется в журнале и публикуется в воронке. Максимум два
#       повтора: третья попытка исключает тройку (pair_excluded).
set -euo pipefail

DIR="${ABLATION_DIR:-$HOME/.claude/ablation}"
J="$DIR/journal.jsonl"
CMD="${1:?команда: complete|annul}"; shift
ID="${1:?task_id}"; shift || true

now() { date -u '+%Y-%m-%dT%H:%M:%SZ'; }
outcome_of() {
    # Только события текущей попытки — после последнего pair_annulled (§9).
    jq -rs --arg id "$ID" --arg a "$1" \
        '([to_entries[] | select(.value.e=="pair_annulled" and .value.id==$id) | .key] | max // -1) as $cut
         | to_entries | [.[] | select(.key > $cut) | .value
         | select(.e=="arm_result" and .id==$id and .arm==$a)] | last.outcome // empty' "$J"
}

case "$CMD" in
complete)
    if jq -es --arg id "$ID" '[.[] | select(.e=="pair_done" and .id==$id)] | length > 0' "$J" >/dev/null 2>&1; then
        echo "pair: $ID уже завершена" >&2; exit 1
    fi
    FULL=$(outcome_of full); CORE=$(outcome_of core); VAN=$(outcome_of vanilla)
    [ -n "$FULL" ] && [ -n "$CORE" ] && [ -n "$VAN" ] || { echo "pair: все три плеча должны быть классифицированы (full='$FULL' core='$CORE' vanilla='$VAN')" >&2; exit 1; }
    case "$FULL$CORE$VAN" in *infrastructure*) echo "pair: infrastructure_failure — аннулируй попытку целиком (annul), не завершай" >&2; exit 1 ;; esac
    FB=0; [ "$FULL" = "success" ] && FB=1
    CB=0; [ "$CORE" = "success" ] && CB=1
    VB=0; [ "$VAN" = "success" ] && VB=1
    SURF=$(jq -rs --arg id "$ID" '[.[] | select(.e=="dry_run" and .id==$id)][0].would_surface // false' "$J")
    jq -cn --arg id "$ID" --argjson f "$FB" --argjson c "$CB" --argjson v "$VB" --argjson s "$SURF" \
        '{task_id:$id, full:$f, core:$c, vanilla:$v, stratum_surface:$s}' >> "$DIR/pairs.jsonl"
    jq -cn --arg id "$ID" --arg ts "$(now)" --arg f "$FULL" --arg c "$CORE" --arg v "$VAN" \
        '{e:"pair_done", id:$id, ts:$ts, full:$f, core:$c, vanilla:$v}' >> "$J"
    echo "pair: $ID завершена (full=$FULL core=$CORE vanilla=$VAN)"
    ;;
annul)
    REASON="${1:-infrastructure_failure}"
    N=$(jq -s --arg id "$ID" '[.[] | select(.e=="pair_annulled" and .id==$id)] | length' "$J")
    ATTEMPT=$((N + 1))
    jq -cn --arg id "$ID" --arg ts "$(now)" --arg r "$REASON" --argjson n "$ATTEMPT" \
        '{e:"pair_annulled", id:$id, ts:$ts, reason:$r, attempt:$n}' >> "$J"
    # Аннулированные прогоны и их arm-события не переиспользуются; журнал
    # append-only — прошлые события остаются свидетельством попытки. Сносится
    # каталог задачи целиком: уцелевшее плечо получило бы лишний шанс (§9).
    rm -rf "$DIR/runs/$ID"
    if [ "$ATTEMPT" -ge 3 ]; then
        jq -cn --arg id "$ID" --arg ts "$(now)" \
            '{e:"pair_excluded", id:$id, ts:$ts, reason:"больше двух повторов (§9)"}' >> "$J"
        echo "pair: $ID исключена — больше двух повторов (§9)"
    else
        echo "pair: попытка $ATTEMPT аннулирована ($REASON); все три плеча повторяются из исходного снимка"
    fi
    ;;
*)  echo "pair: неизвестная команда" >&2; exit 1 ;;
esac
