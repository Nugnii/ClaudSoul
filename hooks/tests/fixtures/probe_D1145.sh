#!/usr/bin/env bash
# СУДИТ: hooks/lib/reply-readers.tsv
# probe_D1145 — у каждого читателя признака «реплика владельца» объявлено понятие, которое ему нужно: граница хода до
# Stop, последняя речь владельца или реплика ДО текущей. Без объявления правку признака решают по виду записи, и она
# достаётся читателям другого понятия (D1142 ×2, D1143, D1144 — четыре первые редакции подряд). Реестр —
# `hooks/lib/reply-readers.tsv`: «путь<TAB>понятие». Читатель — файл хуков или инструментов (не тест), который зовёт
# общий признак или окно хода по имени либо держит вид записи "user" своей копией (любая форма: `==`, `!=`, `= "user"`,
# `\"user\"`, `in (…)`); строка-комментарий читателем не делает. `источник` законен только у файла, где признак
# определён, и определение у каждого признака одно; строка без файла, строка для не-читателя и дубль строки — дефект.
# Красная (1), пока реестра нет, у читателя нет строки или понятие вне словаря. Верно ли понятие читателю, проба не
# судит — это делает свидетель поведения `hooks/tests/test_reply_readers_behavior.sh` (D1149, проба probe_D1149).
R="${CLAUDSOUL_REPO:-$(cd "$(dirname "$0")/../../.." && pwd)}"
[ -d "$R/hooks" ] || exit 2
REG="$R/hooks/lib/reply-readers.tsv"
[ -f "$REG" ] || { echo "реестра нет"; exit 1; }
NAMES='owner_reply|HIL_OWNER_REPLY_JQ|turn_user|HIL_TURN_USER_JQ|is_owner_speech|as_reply|HIL_AS_REPLY_JQ|transcript_turn_window|transcript_user_texts|transcript_agent_text_before_reply|rc_turn_|rc_last_block|rc_trace|rc_why_count|rc_outcome_observed|transcript_fold|transcript_edit_then_reply|transcript_window\.py|turn_offset'
# Своя копия — любое упоминание "user" в кавычках (в том числе экранированных) вне комментария: перечень форм
# сравнения пропускал `!=`, `= "user"` оболочки и `\"user\"` внутри jq (скептик D1145, M2).
COPY="[\"'\\\\]user[\"'\\\\]"
bad=0
readers=" "
while IFS= read -r f; do
    rel="${f#"$R"/}"
    case "$rel" in */tests/*|tests/*) continue ;; esac
    grep -E "$NAMES|$COPY" "$f" | grep -qvE '^[[:space:]]*#' || continue
    readers="$readers$rel "
    concept=$(awk -F'\t' -v p="$rel" '$1 == p {print $2; exit}' "$REG")
    case "$concept" in
        граница-узкая|граница-широкая|граница-без-сводки|речь|до-текущей|не-реплика) ;;
        источник) grep -qE '^def is_owner_reply|^HIL_AS_REPLY_JQ=|^HIL_OWNER_REPLY_JQ=|^HIL_TURN_USER_JQ=' "$f" || { echo "источник без определения признака: $rel"; bad=1; } ;;
        *) echo "нет понятия: $rel"; bad=1 ;;
    esac
done < <(grep -rlE "$NAMES|$COPY" "$R/hooks" "$R/scripts" --include='*.sh' --include='*.py' 2>/dev/null)
# Определение у признака одно: третья копия, назвавшая себя источником, — второй владелец факта (корень R1).
for def in '^def is_owner_reply' '^def is_turn_user' '^HIL_AS_REPLY_JQ=' '^HIL_OWNER_REPLY_JQ=' '^HIL_TURN_USER_JQ='; do
    n=$(grep -rlE "$def" "$R/hooks" "$R/scripts" --include='*.sh' --include='*.py' 2>/dev/null | grep -vc '/tests/')
    [ "$n" -le 1 ] || { echo "признак определён в $n файлах: $def"; bad=1; }
done
seen=" "
while IFS=$'\t' read -r p _; do
    case "$p" in ''|'#'*) continue ;; esac
    [ -f "$R/$p" ] || { echo "строка без файла: $p"; bad=1; continue; }
    case "$readers" in *" $p "*) ;; *) echo "строка для не-читателя: $p"; bad=1 ;; esac
    case "$seen" in *" $p "*) echo "дубль строки: $p"; bad=1 ;; esac
    seen="$seen$p "
done < "$REG"
[ "$bad" -eq 0 ] || exit 1
echo "у каждого читателя признака реплики объявлено понятие"
exit 0
