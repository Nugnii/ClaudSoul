#!/usr/bin/env bash
# СУДИТ: hooks/paths-lib.sh hooks/pending-alerts-surface.sh hooks/session-collector.sh hooks/completion-gate.sh
# test_alerts_reach_their_addressee.sh — сообщение, адресованное сессии или проекту, доходит до своей сессии (своего
# проекта), а не до первой сессии с репликой (D1304, корень R6).
#
# Повод: в сессии ClaudSoul дважды за вечер показано «Закрытых пунктов проекта ProjectA_NEW унесено в архив — добавь в
# коммит»; за 14 дней 42 из 156 таких показов достались сессии другого проекта. Общую очередь `pending-alerts.txt`
# снимает первая сессия с репликой, вопроса «кому» у неё нет.
#
# T1 — канал сессии (`session_alert`): сессия B другого проекта сообщения A не видит, сама A — видит;
# T2 — канал проекта (`project_alert`): сессия другого проекта не видит, сессия того же проекта (из подкаталога) видит,
#      второй раз — нет (снято);
# T3 — сборщик: сессия B в проекте Q уносит в архив закрытый пункт бэклога проекта P — слово «унесено» не в общей очереди,
#      сессии B не показано, сессии проекта P показано;
# T4 — страж закрытия: находка главного бэклога — проекту этого бэклога, а не сессии другого проекта (M1 скептика);
# T5 — находка местного бэклога — своей сессии; T6 — корень рядом с каналом сессии и запасной путь без сессии;
# T7 — вложенный корень получает слово о проекте выше (H1); T8 — слово сборщика о сессии — своей сессии;
# T9 — постоянное «📋 … этого проекта» — каналу проекта (L3); T10 — молчание архиватора — каналу проекта бэклога;
# T11–T12 — «📋 залежавшийся пункт» стража: местный — своей сессии, главный — проекту главного бэклога.
set -uo pipefail
HOOKS_DIR="$(cd "$(dirname "$0")/.." && pwd)"
SURF="$HOOKS_DIR/pending-alerts-surface.sh"; COL="$HOOKS_DIR/session-collector.sh"; CG="$HOOKS_DIR/completion-gate.sh"
ARCHIVER="$HOOKS_DIR/../scripts/backlog-archive.sh"
for f in "$SURF" "$COL" "$CG" "$ARCHIVER" "$HOOKS_DIR/paths-lib.sh"; do [ -f "$f" ] || { echo "FAIL: нет $f"; exit 1; }; done
command -v jq >/dev/null 2>&1 || { echo "SKIP: нет jq"; exit 0; }
PASS=0; FAIL=0
ok() { PASS=$((PASS + 1)); }
bad() { FAIL=$((FAIL + 1)); echo "FAIL [$1]: $2"; }
TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT
TMP=$(cd "$TMP" && pwd -P) || exit 1
ST="$TMP/state"
mkdir -p "$ST" "$TMP/P/.git" "$TMP/P/sub" "$TMP/Q/.git" || { echo "FAIL: подготовка мира не удалась: mkdir"; exit 1; }
surface() { # <sid> <cwd> → что увидит реплика этой сессии
    jq -cn --arg s "$1" --arg c "$2" '{session_id:$s, cwd:$c, prompt:"x"}' \
        | STATE_DIR="$ST" bash "$SURF" 2>/dev/null | jq -r '.hookSpecificOutput.additionalContext // ""' 2>/dev/null
}
# shellcheck source=/dev/null
. "$HOOKS_DIR/paths-lib.sh"
command -v session_alert >/dev/null 2>&1 && command -v project_alert >/dev/null 2>&1 \
    || { echo "FAIL [T0]: в paths-lib.sh нет session_alert/project_alert"; echo "адресаты: прошло 0, упало 1"; exit 1; }

# T1. Канал сессии.
session_alert "$ST" sA "$TMP/P" "MSG-SESSION-A"
case "$(surface sB "$TMP/Q")" in *MSG-SESSION-A*) bad T1a "сообщение сессии A показано сессии B другого проекта" ;; *) ok ;; esac
case "$(surface sA "$TMP/P")" in *MSG-SESSION-A*) ok ;; *) bad T1b "своя сессия не получила своё сообщение" ;; esac

# T2. Канал проекта.
project_alert "$ST" "$TMP/P" "MSG-PROJECT-P"
case "$(surface sB "$TMP/Q")" in *MSG-PROJECT-P*) bad T2a "сообщение о проекте P показано сессии проекта Q" ;; *) ok ;; esac
case "$(surface sC "$TMP/P/sub")" in *MSG-PROJECT-P*) ok ;; *) bad T2b "сессия проекта P (из подкаталога) не получила сообщение о нём" ;; esac
case "$(surface sD "$TMP/P")" in *MSG-PROJECT-P*) bad T2c "сообщение о проекте показано дважды" ;; *) ok ;; esac

# T3. Сборщик: сессия B (проект Q) уносит в архив закрытый пункт бэклога проекта P.
#     Вложенная рамка исполнителя «Проверок» (`BACKLOG_CHECKS_NESTED`) снимается: в ней архиватор отвечает «вложенный
#     прогон» и не уносит ничего — нога судила бы пустоту.
printf '%s\n' '# BACKLOG' '' '## Раздел' '' '- ☐ **L1** открытый пункт' '- ☑ **L2** закрытый пункт' '  **Результат.** Есть.' \
    '  **Проверка.** `true`' > "$TMP/P/BACKLOG.md" || { echo "FAIL: подготовка мира не удалась: бэклог P"; exit 1; }
: > "$ST/pending-alerts.txt"
jq -cn --arg c "$TMP/Q" '{session_id:"sB", cwd:$c}' \
    | env -u BACKLOG_CHECKS_NESTED STATE_DIR="$ST" CLAUDSOUL_BACKLOG="$TMP/P/BACKLOG.md" CLAUDSOUL_BACKLOG_ARCHIVER="$ARCHIVER" \
      CLAUDSOUL_MEASURE_DUE="$TMP/no-such-measure.sh" CG_LOCAL_BACKLOG="" BACKLOG_READINGS_EVERY_TURNS=20 \
      bash "$COL" >/dev/null 2>&1 || { echo "FAIL: подготовка мира не удалась: сборщик вернул не 0"; exit 1; }
grep -q 'L2' "$TMP/P/BACKLOG-archive.md" 2>/dev/null && ok || bad T3a "архиватор не унёс пункт — нога судила бы пустоту"
grep -qF 'унесено' "$ST/pending-alerts.txt" 2>/dev/null && bad T3b "слово о переносе ушло в общую очередь" || ok
case "$(surface sB "$TMP/Q")" in *унесено*) bad T3c "слово о бэклоге проекта P показано сессии проекта Q" ;; *) ok ;; esac
case "$(surface sE "$TMP/P")" in *унесено*) ok ;; *) bad T3d "сессия проекта P не получила слово о переносе в архив" ;; esac

# T4. Страж закрытия, находка в ГЛАВНОМ бэклоге проекта R, сессия sQ — в проекте Q (скептик opus по 9310f120, M1): адресат —
#     проект R, а не сессия sQ.
mkdir -p "$TMP/R/.git" || { echo "FAIL: подготовка мира не удалась: mkdir R"; exit 1; }
printf '%s\n' '# BACKLOG' '' '### D401 ☐ зелёная у открытого — дефект' '**Результат.** заявлено несделанным' \
    '**Проверка.** `true` → 0' > "$TMP/R/BACKLOG.md" || { echo "FAIL: подготовка мира не удалась: бэклог R"; exit 1; }
gate() { # <sid> <cwd> <главный> <местный>
    jq -cn --arg s "$1" --arg c "$2" '{session_id:$s, cwd:$c}' \
        | env -u BACKLOG_CHECKS_NESTED STATE_DIR="$ST" CG_BACKLOG="$3" CG_LOCAL_BACKLOG="$4" bash "$CG" >/dev/null 2>&1 \
        || { echo "FAIL: подготовка мира не удалась: страж закрытия вернул не 0"; exit 1; }
}
: > "$ST/pending-alerts.txt"
gate sQ "$TMP/Q" "$TMP/R/BACKLOG.md" ""
grep -qF 'D401' "$ST/pending-alerts.txt" 2>/dev/null && bad T4a "находка стража ушла в общую очередь" || ok
grep -qF 'D401' "$ST/stop-signals-sQ.txt" 2>/dev/null && bad T4b "находка главного бэклога ушла сессии другого проекта" || ok
case "$(surface sQ "$TMP/Q")" in *D401*) bad T4c "находка бэклога R показана сессии проекта Q" ;; *) ok ;; esac
case "$(surface sR "$TMP/R")" in *D401*) ok ;; *) bad T4d "сессия проекта R не получила находку о своём бэклоге" ;; esac

# T5. Находка в МЕСТНОМ бэклоге сессии — адресат своя сессия.
printf '%s\n' '# BACKLOG' > "$TMP/R/EMPTY.md" || { echo "FAIL: подготовка мира не удалась: пустой бэклог"; exit 1; }
printf '%s\n' '# BACKLOG' '' '### D402 ☐ зелёная у открытого — дефект' '**Результат.** заявлено несделанным' \
    '**Проверка.** `true` → 0' > "$TMP/Q/BACKLOG.md" || { echo "FAIL: подготовка мира не удалась: бэклог Q"; exit 1; }
gate sG "$TMP/Q" "$TMP/R/EMPTY.md" "$TMP/Q/BACKLOG.md"
grep -qF 'D402' "$ST/stop-signals-sG.txt" 2>/dev/null && ok || bad T5a "находка местного бэклога не в канале своей сессии"
case "$(surface sB "$TMP/P")" in *D402*) bad T5b "находка бэклога сессии G показана сессии другого проекта" ;; *) ok ;; esac
case "$(surface sG "$TMP/Q")" in *D402*) ok ;; *) bad T5c "своя сессия не получила находку стража" ;; esac

# T6. Запись корня рядом с каналом сессии и запасной путь без сессии.
session_alert "$ST" sF "$TMP/P/sub" "MSG-F"
[ "$(head -1 "$ST/stop-signals-sF.project" 2>/dev/null)" = "$TMP/P" ] && ok || bad T6a "корень проекта рядом с каналом сессии не записан"
: > "$ST/pending-alerts.txt"
session_alert "$ST" "" "$TMP/P" "MSG-NOSID"; session_alert "$ST" unknown "$TMP/P" "MSG-UNKNOWN"
[ "$(grep -c 'MSG-NOSID\|MSG-UNKNOWN' "$ST/pending-alerts.txt" 2>/dev/null)" = 2 ] && ok \
    || bad T6b "сообщение без сессии не ушло в общую очередь"

# T7. Вложенный корень (скептик, H1): сессия из подкаталога со своим CLAUDE.md получает слово о проекте выше.
mkdir -p "$TMP/P/web" && : > "$TMP/P/web/CLAUDE.md" || { echo "FAIL: подготовка мира не удалась: вложенный корень"; exit 1; }
project_alert "$ST" "$TMP/P" "MSG-NESTED"
case "$(surface sN "$TMP/P/web")" in *MSG-NESTED*) ok ;; *) bad T7 "сессия вложенного корня не получила слово о проекте выше" ;; esac

# Сборщик с управляемым окружением: <sid> <cwd> [местный бэклог] [архиватор]
collect() {
    jq -cn --arg s "$1" --arg c "$2" '{session_id:$s, cwd:$c}' \
        | env -u BACKLOG_CHECKS_NESTED STATE_DIR="$ST" CLAUDSOUL_BACKLOG="$TMP/R/EMPTY.md" CLAUDSOUL_BACKLOG_ARCHIVER="${4:-$ARCHIVER}" \
          CLAUDSOUL_MEASURE_DUE="$TMP/no-such-measure.sh" CG_LOCAL_BACKLOG="${3:-}" BACKLOG_READINGS_EVERY_TURNS=20 \
          CLAUDE_CODE_SESSION_ID="pid-$1" bash "$COL" >/dev/null 2>&1 \
        || { echo "FAIL: подготовка мира не удалась: сборщик вернул не 0"; exit 1; }
}
# T8. Сообщение сборщика о сессии («в сессии были ошибки») — своей сессии.
: > "$ST/had_struggle_pid-sS"; : > "$ST/pending-alerts.txt"
collect sS "$TMP/Q"
grep -qF 'В сессии были ошибки' "$ST/pending-alerts.txt" 2>/dev/null && bad T8a "слово о сессии ушло в общую очередь" || ok
case "$(surface sB2 "$TMP/P")" in *'В сессии были ошибки'*) bad T8b "слово о сессии S показано сессии другого проекта" ;; *) ok ;; esac
case "$(surface sS "$TMP/Q")" in *'В сессии были ошибки'*) ok ;; *) bad T8c "своя сессия не получила слово сборщика" ;; esac

# T9. Постоянное «📋 … этого проекта» (скептик, L3) — каналу проекта.
printf '%s\n' '# BACKLOG' '' '## Раздел' '' '- ☐ **L7** открытый пункт' > "$TMP/Q/BACKLOG.md" \
    || { echo "FAIL: подготовка мира не удалась: бэклог Q"; exit 1; }
: > "$ST/pending-alerts.txt"
collect sX "$TMP/Q" "$TMP/Q/BACKLOG.md"
grep -qF 'этого проекта' "$ST/pending-alerts.txt" 2>/dev/null && bad T9a "долг проекта ушёл в общую очередь" || ok
case "$(surface sY "$TMP/Q")" in *'этого проекта'*) ok ;; *) bad T9b "сессия проекта не получила его долг" ;; esac

# T10. Архиватор не ответил ни одним известным исходом — слово каналу проекта бэклога.
printf '%s\n' '# BACKLOG' '' '## Раздел' '' '- ☑ **L8** закрытый пункт' '  **Результат.** Есть.' '  **Проверка.** `true`' \
    > "$TMP/P/BACKLOG.md" || { echo "FAIL: подготовка мира не удалась: бэклог P"; exit 1; }
printf '#!/bin/sh\necho "непонятный ответ"\n' > "$TMP/fake-arch.sh" && chmod +x "$TMP/fake-arch.sh" \
    || { echo "FAIL: подготовка мира не удалась: фальшивый архиватор"; exit 1; }
: > "$ST/pending-alerts.txt"
jq -cn --arg c "$TMP/Q" '{session_id:"sA2", cwd:$c}' \
    | env -u BACKLOG_CHECKS_NESTED STATE_DIR="$ST" CLAUDSOUL_BACKLOG="$TMP/P/BACKLOG.md" CLAUDSOUL_BACKLOG_ARCHIVER="$TMP/fake-arch.sh" \
      CLAUDSOUL_MEASURE_DUE="$TMP/no-such-measure.sh" CG_LOCAL_BACKLOG="" BACKLOG_READINGS_EVERY_TURNS=20 \
      bash "$COL" >/dev/null 2>&1 || { echo "FAIL: подготовка мира не удалась: сборщик вернул не 0"; exit 1; }
grep -qF 'НЕ ОТВЕТИЛ' "$ST/pending-alerts.txt" 2>/dev/null && bad T10a "молчание архиватора ушло в общую очередь" || ok
case "$(surface sP2 "$TMP/P")" in *'НЕ ОТВЕТИЛ'*) ok ;; *) bad T10b "сессия проекта бэклога не получила слово о молчании архиватора" ;; esac

# T11–T12. «📋 Залежавшийся пункт» стража: местный бэклог — своей сессии, главный — проекту главного бэклога. Снимок
#     бэклога заводится до вызова (как у старта сессии), иначе страж залежавшихся не называет.
# shellcheck source=/dev/null
. "$HOOKS_DIR/backlog-lib.sh" 2>/dev/null
command -v backlog_snapshot >/dev/null 2>&1 || { echo "FAIL: подготовка мира не удалась: нет backlog_snapshot"; exit 1; }
mkdir -p "$TMP/Q2/.git" "$TMP/R2/.git" || { echo "FAIL: подготовка мира не удалась: mkdir Q2 R2"; exit 1; }
for d in Q2 R2; do
    printf '%s\n' '# BACKLOG' '' "### D50$d ☐ старый открытый пункт" '**Результат.** дефект жив' '**Проверка.** `false` → 0' \
        > "$TMP/$d/BACKLOG.md" || { echo "FAIL: подготовка мира не удалась: бэклог $d"; exit 1; }
done
backlog_snapshot "$ST" sK "$TMP/Q2/BACKLOG.md" >/dev/null; backlog_snapshot "$ST" sK "$TMP/R/EMPTY.md" >/dev/null
: > "$ST/pending-alerts.txt"
gate sK "$TMP/Q2" "$TMP/R/EMPTY.md" "$TMP/Q2/BACKLOG.md"
grep -qF 'Залежавшийся' "$ST/stop-signals-sK.txt" 2>/dev/null && ok || bad T11a "залежавшийся местного бэклога не в канале своей сессии"
grep -qF 'Залежавшийся' "$ST/pending-alerts.txt" 2>/dev/null && bad T11b "залежавшийся ушёл в общую очередь" || ok
backlog_snapshot "$ST" sM "$TMP/R2/BACKLOG.md" >/dev/null
gate sM "$TMP/Q" "$TMP/R2/BACKLOG.md" ""
grep -qF 'D50R2' "$ST/stop-signals-sM.txt" 2>/dev/null && bad T12a "залежавшийся главного бэклога ушёл сессии другого проекта" || ok
grep -qF 'D50R2' "$ST/pending-alerts.txt" 2>/dev/null && bad T12b "залежавшийся главного бэклога ушёл в общую очередь" || ok
case "$(surface sR3 "$TMP/R2")" in *D50R2*) ok ;; *) bad T12c "проект главного бэклога не получил залежавшийся пункт" ;; esac

# T13 (D1344): одна и та же строка о проекте, сказанная несколькими сессиями, показана один раз; разные строки и их
# порядок целы. Очередь проекта общая, дроссель писателей — по сессии, поэтому повтор в очереди законен.
mkdir -p "$TMP/D/.git"
for _s in 1 2 3; do project_alert "$ST" "$TMP/D" "MSG-DUP строка о проекте"; done
project_alert "$ST" "$TMP/D" "MSG-OTHER вторая строка"
project_alert "$ST" "$TMP/D" "MSG-DUP строка о проекте"
OUT13=$(surface sD13 "$TMP/D")
N13=$(grep -c 'MSG-DUP' <<< "$OUT13")
[ "$N13" -eq 1 ] && ok || bad T13a "одинаковая строка о проекте показана ${N13} раз(а)"
grep -q 'MSG-OTHER' <<< "$OUT13" && ok || bad T13b "непохожая строка о проекте потеряна при склейке"
[ "$(grep -n 'MSG-DUP\|MSG-OTHER' <<< "$OUT13" | head -1 | grep -c 'MSG-DUP')" -eq 1 ] && ok || bad T13c "порядок первого появления строк нарушен"

# T14 (скептик D1344, M1): тот же повтор в соседних разделах показа — общая очередь отложенных уведомлений и сигналы
# старта сессии — склеивается так же; разные строки целы.
mkdir -p "$TMP/E/.git"
printf '%s\n' 'MSG-ALERT-DUP строка' 'MSG-ALERT-DUP строка' 'MSG-ALERT-OTHER строка' 'MSG-ALERT-DUP строка' >> "$ST/pending-alerts.txt"
printf '%s\n' 'MSG-START-DUP строка' 'MSG-START-DUP строка' 'MSG-START-OTHER строка' > "$ST/startup-signals-sE14.txt"
OUT14=$(surface sE14 "$TMP/E")
[ "$(grep -c 'MSG-ALERT-DUP' <<< "$OUT14")" -eq 1 ] && ok || bad T14a "повтор в отложенных уведомлениях показан $(grep -c 'MSG-ALERT-DUP' <<< "$OUT14") раз(а)"
grep -q 'MSG-ALERT-OTHER' <<< "$OUT14" && ok || bad T14b "непохожая строка отложенных уведомлений потеряна"
case "$(grep -c 'MSG-START-DUP' <<< "$OUT14"):$(grep -c 'MSG-START-OTHER' <<< "$OUT14")" in
    1:1) ok ;;
    *) bad T14c "сигналы старта: повтор $(grep -c 'MSG-START-DUP' <<< "$OUT14"), иная строка $(grep -c 'MSG-START-OTHER' <<< "$OUT14")" ;; esac

echo "адресаты: прошло $PASS, упало $FAIL"
exit $(( FAIL != 0 ))
