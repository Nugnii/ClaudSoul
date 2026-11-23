#!/usr/bin/env bash
# СУДИТ: scripts/backlog-recheck.sh
# test_recheck_spiral_rule.sh — правило «спирали правок» инварианта D411 на песочном репозитории.
#
# Инвариант считает по истории: правка ОДНОГО файла спайки, за которой в трёх следующих
# коммитах идёт правка СОСЕДА. До 5 октября 2026 ответом считался любой коммит с иным набором
# файлов спайки, и серия починок одного механизма (файл и его тест; два носителя одного
# дефекта) дала четыре кандидата при пороге один — закрытый пункт «откатился» без спирали.
# Своего свидетеля у правила не было: оно судилось только живой историей.
#
# Ноги: T1 — сосед правится вслед, исходный файл не трогают, дважды → откат, кандидаты названы;
#       T2 — «ответ» правит тот же файл вместе с соседом, дважды → инвариант держится;
#       T3 — один настоящий кандидат → держится (порог — больше одного).
set -uo pipefail
RECHECK="$(cd "$(dirname "$0")/../.." && pwd)/scripts/backlog-recheck.sh"
[ -f "$RECHECK" ] || { echo "FAIL: нет $RECHECK"; exit 1; }
command -v git >/dev/null 2>&1 && command -v python3 >/dev/null 2>&1 || { echo "SKIP: нет git либо python3"; exit 0; }
# Свидетеля может позвать «Проверка» пункта — снять ограду вложенного прогона, как у соседей.
unset BACKLOG_CHECKS_NESTED BACKLOG_CMD_RUNNING BACKLOG_CMD_DEPTH_MAX

PASS=0; FAIL=0
ok()  { PASS=$((PASS + 1)); }
bad() { FAIL=$((FAIL + 1)); echo "FAIL [$1]: $2"; }
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

_repo() {   # <name> — репозиторий со спайкой из двух файлов a.sh и b.sh и посторонним c.sh
    local d="$TMP/$1"
    mkdir -p "$d/hooks" "$d/mcp-server/visualization"
    printf '%s\n' '{"nodes":[{"id":"a","key":"hooks/a.sh"},{"id":"b","key":"hooks/b.sh"}],' \
        '"edges":[{"source":"a","target":"b","type":"пишет"},{"source":"b","target":"a","type":"читает"}]}' \
        > "$d/mcp-server/visualization/project-graph-data.json"
    : > "$d/hooks/a.sh"; : > "$d/hooks/b.sh"; : > "$d/hooks/c.sh"
    printf '%s\n' '# BACKLOG' > "$d/BACKLOG.md"; printf '%s\n' '# BACKLOG — архив' > "$d/BACKLOG-archive.md"
    ( cd "$d" && git init -q . && git add -A && _commit "start" ) >/dev/null 2>&1
}
_commit() { git -c user.name=t -c user.email=t@example.com commit -q --no-gpg-sign -m "$1"; }
_touch() {   # <name> <сообщение> <файл>... — коммит, меняющий названные файлы
    local d="$TMP/$1" m="$2" f; shift 2
    for f in "$@"; do echo "$m" >> "$d/hooks/$f"; done
    ( cd "$d" && git add -A && _commit "$m" ) >/dev/null 2>&1
}
_d411() {   # <name> — строка сверки про D411
    CLAUDSOUL_REPO="$TMP/$1" LESSONS_DIR="$TMP/no-lessons" BACKLOG_RECHECK_VERBOSE=1 \
        bash "$RECHECK" 2>&1 | grep ' D411 ' || true
}

# === T1: настоящая спираль — сосед правится вслед, дважды ===
_repo spiral
_touch spiral e1 a.sh; _touch spiral e2 b.sh; _touch spiral e3 c.sh; _touch spiral e4 c.sh; _touch spiral e5 c.sh
_touch spiral e6 a.sh; _touch spiral e7 b.sh
LINE=$(_d411 spiral)
if grep -q '✗ D411' <<< "$LINE"; then ok; else bad T1a "две ответные правки соседа не дали отката: ${LINE}"; fi
if grep -q 'кандидаты (правка>ответ): [0-9a-f]\{8\}>[0-9a-f]\{8\}' <<< "$LINE"; then ok; else bad T1b "кандидаты не названы: ${LINE}"; fi

# === T2: «ответ» правит тот же файл вместе с соседом — это продолжение работы, не спираль ===
_repo same
_touch same e1 a.sh; _touch same e2 a.sh b.sh; _touch same e3 c.sh; _touch same e4 c.sh; _touch same e5 c.sh
_touch same e6 a.sh; _touch same e7 a.sh b.sh
LINE=$(_d411 same)
if grep -q '✓ D411 .*спайка данных законна' <<< "$LINE"; then ok; else bad T2 "продолжение работы над тем же файлом сочтено спиралью: ${LINE}"; fi

# === T3: один кандидат — порог не превышен ===
_repo one
_touch one e1 a.sh; _touch one e2 b.sh
LINE=$(_d411 one)
if grep -q '✓ D411 .*ответных правок 1 из' <<< "$LINE"; then ok; else bad T3 "один кандидат дал не «держится» с числом 1: ${LINE}"; fi

# === T4–T7: ответ связан с правкой по данным — пункт в заголовке коммита и ссылка в блоке пункта (D1146) ===
# Перемежение независимых серий (e5bd0c4e D1126 > 74b26847 D1132 > be37f162 D1133) давало откат без спирали.
_items() {  # <name> <D-номер> <текст блока> — блок пункта в архиве
    printf -- '- ☑ **D%s** %s\n' "$2" "$3" >> "$TMP/$1/BACKLOG-archive.md"
}
_repo indep; _items indep 2 "своё"; _items indep 4 "своё"
_touch indep "fix: D1" a.sh; _touch indep "fix: D2" b.sh; _touch indep "fix: D3" a.sh; _touch indep "fix: D4" b.sh
LINE=$(_d411 indep)
if grep -q '✓ D411 .*ответных правок 0 из' <<< "$LINE"; then ok; else bad T4 "независимые пункты в окне трёх коммитов сочтены спиралью: ${LINE}"; fi
_repo linked; _items linked 2 "регресс D1"; _items linked 4 "регресс D3"
_touch linked "fix: D1" a.sh; _touch linked "fix: D2" b.sh; _touch linked "fix: D3" a.sh; _touch linked "fix: D4" b.sh
LINE=$(_d411 linked)
if grep -q '✗ D411 .*снова 2 из' <<< "$LINE"; then ok; else bad T5 "пункт ответа называет пункт правки — спираль не названа: ${LINE}"; fi
_repo same_item
_touch same_item "fix: D1" a.sh; _touch same_item "fix: D1 сосед" b.sh; _touch same_item "fix: D3" a.sh; _touch same_item "fix: D3 сосед" b.sh
LINE=$(_d411 same_item)
if grep -q '✗ D411 .*снова 2 из' <<< "$LINE"; then ok; else bad T6 "общий пункт правки и ответа — спираль не названа: ${LINE}"; fi
_repo back; _items back 1 "регресс — D2"; _items back 3 "регресс — D4"
_touch back "fix: D1" a.sh; _touch back "fix: D2" b.sh; _touch back "fix: D3" a.sh; _touch back "fix: D4" b.sh
LINE=$(_d411 back)
if grep -q '✗ D411 .*снова 2 из' <<< "$LINE"; then ok; else bad T7 "блок пункта правки называет ответ — спираль не названа: ${LINE}"; fi

# === T8–T11: ноги по находкам финального скептика D1146 (H1, M1) ===
# T8 — ответ ссылается на исходную правку ХЕШЕМ коммита («скептик по <хеш>») — форма из мира, а не номером пункта.
_repo hash
_touch hash "fix: D1" a.sh; _h1=$(git -C "$TMP/hash" rev-parse --short=8 HEAD)
_touch hash "fix: D2" b.sh; _touch hash "fix: D3" a.sh; _h3=$(git -C "$TMP/hash" rev-parse --short=8 HEAD)
_touch hash "fix: D4" b.sh
_items hash 2 "Повод (финальный скептик opus по $_h1)."; _items hash 4 "Повод (скептик по $_h3)."
LINE=$(_d411 hash)
if grep -q '✗ D411 .*снова 2 из' <<< "$LINE"; then ok; else bad T8 "ответ со ссылкой хешем — спираль не названа: ${LINE}"; fi
# T9 — номер есть у одного коммита пары: судится позицией, как прежде.
_repo half
_touch half "fix: D1" a.sh; _touch half "fix b" b.sh; _touch half "fix: D3" a.sh; _touch half "fix b2" b.sh
LINE=$(_d411 half)
if grep -q '✗ D411 .*снова 3 из' <<< "$LINE"; then ok; else bad T9 "пара с номером у одного коммита судится не позицией: ${LINE}"; fi
# T10 — блок ответа ещё открыт (◐) и живёт в BACKLOG.md, а не в архиве.
_repo open_item
printf -- '- ◐ **D2** регресс D1\n- ◐ **D4** регресс D3\n' >> "$TMP/open_item/BACKLOG.md"
_touch open_item "fix: D1" a.sh; _touch open_item "fix: D2" b.sh; _touch open_item "fix: D3" a.sh; _touch open_item "fix: D4" b.sh
LINE=$(_d411 open_item)
if grep -q '✗ D411 .*снова 2 из' <<< "$LINE"; then ok; else bad T10 "открытый пункт в BACKLOG.md не прочитан: ${LINE}"; fi
# T11 — номер внутри длинного номера не связь: «D12» не называет D1.
_repo prefix; _items prefix 2 "своё, рядом D12"; _items prefix 4 "своё, рядом D32"
_touch prefix "fix: D1" a.sh; _touch prefix "fix: D2" b.sh; _touch prefix "fix: D3" a.sh; _touch prefix "fix: D4" b.sh
LINE=$(_d411 prefix)
if grep -q '✓ D411 .*ответных правок 0 из' <<< "$LINE"; then ok; else bad T11 "D12 в блоке сочтён ссылкой на D1: ${LINE}"; fi

echo "recheck spiral rule: $PASS passed, $FAIL failed"
exit $(( FAIL != 0 ))
