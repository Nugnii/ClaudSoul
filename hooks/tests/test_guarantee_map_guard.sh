#!/usr/bin/env bash
# СУДИТ: hooks/guarantee-map-guard.sh hooks/backlog-lib.sh
# test_guarantee_map_guard.sh — файл, названный находкой скептика у пункта ◐ защитного слоя, правится только после
# абзаца «**Карта гарантий.**» с его адресом, словом «прогон» и командой в обратных кавычках (D1158).
#
# Пункт ◐, блок и защитный слой — у библиотеки; здесь проверяется, что страж зовёт её верно, судит находку и карту по
# адресу файла и молчит там, где судить нечего. Фикстурный проект — свой: страж ищет BACKLOG.md подъёмом от файла.
set -uo pipefail
HOOKS_DIR="$(cd "$(dirname "$0")/.." && pwd)"
HOOK="$HOOKS_DIR/guarantee-map-guard.sh"
[ -f "$HOOK" ] || { echo "FAIL: нет $HOOK"; exit 1; }
command -v jq >/dev/null 2>&1 || { echo "SKIP: нет jq"; exit 0; }
command -v python3 >/dev/null 2>&1 || { echo "SKIP: нет python3"; exit 0; }

PASS=0; FAIL=0
ok()  { PASS=$((PASS+1)); }
bad() { FAIL=$((FAIL+1)); echo "FAIL [$1]: $2"; }
decision() { jq -r '.hookSpecificOutput.permissionDecision // ""' <<< "$1" 2>/dev/null; }
reason()   { jq -r '.hookSpecificOutput.permissionDecisionReason // ""' <<< "$1" 2>/dev/null; }
denied() { [ "$(decision "$1")" = "deny" ]; }
assert_empty() { [ -z "$1" ] && ok || bad "$2" "страж заговорил: $1"; }

TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT
P="$TMP/proj"; mkdir -p "$P/hooks"
printf 'echo x\n' > "$P/hooks/x.sh"; printf 'echo y\n' > "$P/hooks/y.sh"

HEAD='- ◐ **D9001** Страж `hooks/x.sh` теряет запись.
  **Корень.** R1 — нет.'
FIND='  **Скептик, первый круг (opus по abc1234).** H1 — `hooks/x.sh:12` теряет запись на пустом входе.'
CARD_RUN='  **Карта гарантий.** `hooks/x.sh` пишет журнал; крайний вход — пустой, прогон `bash hooks/tests/test_x.sh` → 0.'
bl() { printf '# Долг\n\n%s\n' "$1" > "$P/BACKLOG.md"; }
edit() { jq -cn --arg t "${2:-Edit}" --arg f "$1" '{tool_name:$t,tool_input:{file_path:$f,old_string:"echo",new_string:"printf"}}' \
    | bash "${3:-$HOOK}" 2>/dev/null; }

# T1: находка называет файл, карты нет — отказ; причина называет пункт, находку и прогон.
bl "$HEAD
$FIND"
OUT=$(edit "$P/hooks/x.sh")
if denied "$OUT"; then ok; else bad T1 "правка файла из находки прошла без карты: ${OUT:-<пусто>}"; fi
R=$(reason "$OUT")
case "$R" in *D9001*"Скептик, первый круг"*прогон*) ok ;; *) bad T1b "причина не называет пункт, находку и прогон: $R" ;; esac

# T2: файл вне находки — тишина; T3: сам бэклог и архив — тишина, даже названные находкой (иначе карту не записать).
assert_empty "$(edit "$P/hooks/y.sh")" T2
bl "$HEAD
  **Скептик (opus).** L1 — адрес в \`BACKLOG.md:5\` и \`BACKLOG-archive.md:9\` устарел, \`hooks/x.sh:12\`."
assert_empty "$(edit "$P/BACKLOG.md")" T3
assert_empty "$(edit "$P/BACKLOG-archive.md")" T3b

# T4: карта без прогона — отказ; T5: карта с прогоном — тишина.
bl "$HEAD
$FIND
  **Карта гарантий.** \`hooks/x.sh\` пишет журнал, читает вход; судит test_x; крайний вход — пустой."
if denied "$(edit "$P/hooks/x.sh")"; then ok; else bad T4 "карта без прогона пропустила правку"; fi
bl "$HEAD
$FIND
$CARD_RUN"
assert_empty "$(edit "$P/hooks/x.sh")" T5

# T6: карта стоит ДО новой находки следующего круга — отказ.
bl "$HEAD
$FIND
$CARD_RUN
  **Скептик, второй круг (opus по def5678).** H1 — \`hooks/x.sh:30\` снова теряет запись."
if denied "$(edit "$P/hooks/x.sh")"; then ok; else bad T6 "карта прошлого круга покрыла новую находку"; fi

# T7: карта в два абзаца строк — прогон на строке продолжения засчитан.
bl "$HEAD
$FIND
  **Карта гарантий.** \`hooks/x.sh\`:
  - пишет журнал, читает вход;
  - прогон крайнего входа \`bash hooks/tests/test_x.sh\` → 0."
assert_empty "$(edit "$P/hooks/x.sh")" T7

# T8: карта с прогоном, но о другом файле — отказ.
bl "$HEAD
$FIND
  **Карта гарантий.** \`hooks/y.sh\` — прогон \`bash t.sh\` → 0."
if denied "$(edit "$P/hooks/x.sh")"; then ok; else bad T8 "карта чужого файла пропустила правку"; fi

# T9: пункт ☐ — не в работе, тишина.
bl "- ☐ **D9001** Страж \`hooks/x.sh\` теряет запись.
  **Корень.** R1 — нет.
$FIND"
assert_empty "$(edit "$P/hooks/x.sh")" T9

# T9b: то же под русской UTF-8-локалью (D1158, третий круг, H1): `awk` macOS сравнивает строки по сортировке локали,
# и «☐» там равна «◐». Нет такой локали на машине — `awk` в C, молчание ничего не доказывает: нога не засчитывается,
# а называется (D1171 — положительный контроль рамки).
if env -u LC_ALL -u LC_COLLATE LANG=ru_RU.UTF-8 awk 'BEGIN { exit !("☐" == "◐") }'; then
    assert_empty "$(jq -cn --arg f "$P/hooks/x.sh" '{tool_name:"Edit",tool_input:{file_path:$f}}' \
        | env -u LC_ALL -u LC_COLLATE LANG=ru_RU.UTF-8 bash "$HOOK" 2>/dev/null)" T9b
else
    echo "T9b не судит: локаль ru_RU.UTF-8 здесь не сворачивает метки в awk"
fi

# T10: проект без каталога hooks/ в корне — не защитный слой, тишина.
Q="$TMP/plain"; mkdir -p "$Q/src"; printf 'x\n' > "$Q/src/x.sh"
printf '# Долг\n\n- ◐ **D9002** `src/x.sh`.\n  **Скептик, первый круг (opus).** H1 — `src/x.sh:1`.\n' > "$Q/BACKLOG.md"
assert_empty "$(edit "$Q/src/x.sh")" T10

# T11: голое имя — адрес; путь установленной копии `~/.claude/hooks/x.sh` — нет; `./hooks/x.sh` — адрес.
bl "$HEAD
  **Скептик (opus).** H1 — \`x.sh:12\` теряет запись."
if denied "$(edit "$P/hooks/x.sh")"; then ok; else bad T11 "голое имя файла не принято адресом"; fi
bl "- ◐ **D9001** Страж \`hooks/y.sh\`.
  **Скептик (opus).** H1 — \`~/.claude/hooks/x.sh:12\` в установке."
assert_empty "$(edit "$P/hooks/x.sh")" T11b
bl "$HEAD
  **Скептик (opus).** H1 — \`./hooks/x.sh:12\`."
if denied "$(edit "$P/hooks/x.sh")"; then ok; else bad T11c "./путь не принят адресом"; fi

# T12: имя с продолжением (`x.sh.bak`, `x.shell`) — не этот файл, тишина.
bl "- ◐ **D9001** Страж \`hooks/y.sh\`.
  **Скептик (opus).** H1 — \`hooks/x.sh.bak\` и \`hooks/x.shell\`."
assert_empty "$(edit "$P/hooks/x.sh")" T12

# T12b: составное имя без расширения — адрес (H1 скептика D1158: «`probe_D1148` — чинить здесь»), и имя из прописных
# (`CHANGELOG`, `META` — второй круг); префикс чужого имени (`x-y` при `x-y-one.py`), код корня `R6` при `R6.sh` и строчное
# однословное (`discovery`) — нет.
printf 'x\n' > "$P/hooks/probe_D7.sh"; printf 'x\n' > "$P/hooks/META.md"; printf 'x\n' > "$P/hooks/x-y-one.py"
printf 'x\n' > "$P/hooks/R6.sh"; printf 'x\n' > "$P/hooks/discovery.py"
bl "- ◐ **D9001** Страж \`hooks/y.sh\`.
  **Скептик (opus).** M2 — ноги в \`probe_D7\` и META, \`x-y\` — чинить здесь; тот же корень R6, сигнал discovery."
if denied "$(edit "$P/hooks/probe_D7.sh")"; then ok; else bad T12b "составное имя без расширения не принято адресом"; fi
if denied "$(edit "$P/hooks/META.md")"; then ok; else bad T12c "имя из прописных без расширения не принято адресом"; fi
assert_empty "$(edit "$P/hooks/x-y-one.py")" T12d
assert_empty "$(edit "$P/hooks/R6.sh")" T12e
assert_empty "$(edit "$P/hooks/discovery.py")" T12f

# T13: метка без «скептик» — не находка; «финальный скептик» в метке со строчной — находка.
bl "$HEAD
  **Повод (27 октября 2026, замер).** \`hooks/x.sh:12\` теряет запись."
assert_empty "$(edit "$P/hooks/x.sh")" T13
bl "$HEAD
  **Повод (27 октября 2026, финальный скептик opus по abc).** \`hooks/x.sh:12\` теряет запись."
if denied "$(edit "$P/hooks/x.sh")"; then ok; else bad T13b "перенесённая находка «Повод (…скептик…)» не судится"; fi

# T14: Write и MultiEdit судятся так же; Bash — не предмет этого входа (его путь — диспетчер).
bl "$HEAD
$FIND"
if denied "$(edit "$P/hooks/x.sh" Write)"; then ok; else bad T14 "Write прошёл без карты"; fi
if denied "$(edit "$P/hooks/x.sh" MultiEdit)"; then ok; else bad T14b "MultiEdit прошёл без карты"; fi
assert_empty "$(edit "$P/hooks/x.sh" Bash)" T14c

# T15: файл вне проекта (в предках нет BACKLOG.md) — тишина; новый файл в несуществующем каталоге — судится.
mkdir -p "$TMP/elsewhere"; printf 'x\n' > "$TMP/elsewhere/x.sh"
assert_empty "$(edit "$TMP/elsewhere/x.sh")" T15
bl "$HEAD
  **Скептик (opus).** H1 — нет пробы \`hooks/new/z.sh\`."
if denied "$(edit "$P/hooks/new/z.sh" Write)"; then ok; else bad T15b "новый файл из находки создан без карты"; fi

# T16: старая редакция библиотеки (нет `backlog_names_guard_layer`) — судить нечем, тишина.
OLDH="$TMP/oldhooks"; mkdir -p "$OLDH"; cp "$HOOK" "$OLDH/"
{ cat "$HOOKS_DIR/backlog-lib.sh"; printf '\nunset -f backlog_names_guard_layer\n'; } > "$OLDH/backlog-lib.sh"
bl "$HEAD
$FIND"
assert_empty "$(edit "$P/hooks/x.sh" Edit "$OLDH/guarantee-map-guard.sh")" T16

# T17: два пункта ◐ называют файл — оба в причине.
bl "$HEAD
$FIND

- ◐ **D9003** Ещё \`hooks/x.sh\`.
  **Скептик (opus по 111).** M1 — \`hooks/x.sh:40\`."
R=$(reason "$(edit "$P/hooks/x.sh")")
case "$R" in *D9001*D9003*) ok ;; *) bad T17 "в причине не оба пункта: $R" ;; esac

# T18 (D1169): находка, адрес и карта опознаются по РОЛИ, а не по вёрстке строки — формы из отчётов скептиков D1158
# (M2–M5, L1, L7, третий круг M1, длина имени из прописных). judge <нога> <deny|pass> <файл> <блок после головы>.
for f in README.md AB.md ABC.md ABc.md; do printf 'x\n' > "$P/$f"; done
PP=$(cd "$P" && pwd -P)
judge() {
    bl "$HEAD
$4"
    local got; got=$(decision "$(edit "$P/$3")"); [ -n "$got" ] || got=pass
    [ "$got" = "$2" ] && ok || bad "$1" "ждали $2, страж — $got"
}
judge T18a deny hooks/x.sh '  **Скептик (opus).** H1 — разбор ниже.

  Место: `hooks/x.sh:12` теряет запись.'
judge T18b deny hooks/x.sh '  - **Скептик, второй круг (opus).** H1 — `hooks/x.sh:12`.'
judge T18c deny hooks/x.sh '  **Скептик (opus).** H1 — воспроизведение:
  ```
  bash hooks/x.sh --empty
  ```'
judge T18d deny hooks/x.sh "  **Скептик (opus).** H1 — \`$PP/hooks/x.sh:12\`."
judge T18e deny hooks/x.sh '  **Скептик (opus).** H1 — `hooks/X.sh:12`.'
judge T18f deny hooks/x.sh '  **Скептик (opus).** H1 — `hooks/new/../x.sh:12`.'
judge T18g deny hooks/x.sh '  **Противник, раунд 2 (opus).** Атака — `hooks/x.sh:12`.'
judge T18h deny hooks/x.sh '  **Прожарка первой редакции.** Находка — `hooks/x.sh:12`.'
judge T18i pass hooks/x.sh '  **Скептик (opus).** H1 — `hooks/x.sh:12`.
  **Карта гарантий (по находке скептика H1).** `hooks/x.sh` пишет журнал; прогон `bash t.sh` → 0.'
judge T18j deny hooks/x.sh '  **Скептик (opus).** H1 — `hooks/x.sh:12`.
  **Карта гарантий.** `hooks/x.sh` — что пишет, что читает; прогон крайнего входа `<команда>` → <исход>'
judge T18k pass hooks/x.sh '  **Скептик (opus).** H1 — `hooks/x.sh:12`.
  - **Карта гарантий.** `hooks/x.sh` пишет журнал; прогон `bash t.sh` → 0.'
judge T18l pass hooks/x.sh '  **Скептик (opus).** H1 — `hooks/x.sh:12`.
  **КАРТА ГАРАНТИЙ.** `hooks/x.sh` пишет журнал; ПРОГОН `bash t.sh` → 0.'
judge T18m pass README.md '  **Скептик (opus).** H1 — `$README` пуст, `${README}` тоже.'
judge T18n deny README.md '  **Скептик (opus).** M1 — README отстал от кода.'
judge T18o pass AB.md '  **Скептик (opus).** L1 — AB и CD без ноги.'
judge T18p deny ABC.md '  **Скептик (opus).** L1 — ABC без ноги.'
judge T18q pass ABc.md '  **Скептик (opus).** L1 — ABc без ноги.'
# T18r: пункт-заголовок с отчётом подзаголовком — та же находка.
printf '# Долг\n\n### D9001 Страж `hooks/x.sh` ◐\n**Корень.** R1 — нет.\n#### Скептик (opus)\nH1 — `hooks/x.sh:12`.\n' > "$P/BACKLOG.md"
if denied "$(edit "$P/hooks/x.sh")"; then ok; else bad T18r "отчёт подзаголовком не судится"; fi

# T19 (D1169, второй круг скептика). Регрессы расширенного разбора (L1–L3) и формы, которые держали только ноги (L4).
printf 'x\n' > "$P/VERSION"
judge T19a deny hooks/x.sh '  **Скептик (opus).** Находки:
  - **H1** — `hooks/x.sh:12` теряет запись.'
judge T19b pass hooks/x.sh '  **Скептик (opus).** H1 — `hooks/x.sh:12`.
  **Карта гарантий.** Прогон `bash t.sh` → 0:
  - **hooks/x.sh** — пишет журнал.'
judge T19c deny hooks/x.sh '  **Скептик (opus).** H1 — шаги:
      # шаг 1
      `hooks/x.sh:12` теряет запись.'
judge T19d deny hooks/x.sh '  **Скептик (opus).** H1 — `{hooks/x.sh,hooks/y.sh}` теряют запись.'
judge T19e pass VERSION '  **Скептик (opus).** L1 — version в прозе не обновлена.'
judge T19f deny VERSION '  **Скептик (opus).** L1 — VERSION не обновлён.'
judge T19g deny hooks/x.sh '  **Скептик (opus).** H1 — запись теряет hooks/x.sh.'
judge T19h deny hooks/x.sh '  **Скептик (opus).** H1 — `hooks/x.sh:12`; воспроизведение:
  ```
  **Карта гарантий.** `hooks/x.sh` прогон `bash t.sh` → 0.
  ```'
judge T19i deny hooks/x.sh '  **Скептик (opus).** H1 — X.SH теряет запись.'
judge T19j deny hooks/x.sh "  **Скептик (opus).** H1 — \`$P/hooks/x.sh:12\`."
judge T19k pass hooks/x.sh "  **Скептик (opus).** H1 — \`$PP/hooks/x.sh.bak\` и \`$PP/hooks/x.shx\`."
# T19l: адрес только прописными — предварительный поиск без регистра (шапка пункта адреса не несёт).
printf '# Долг\n\n- ◐ **D9001** Страж теряет запись.\n  **Корень.** R1 — `hooks/y.sh` рядом.\n  **Скептик (opus).** H1 — `HOOKS/X.SH:12`.\n' > "$P/BACKLOG.md"
if denied "$(edit "$P/hooks/x.sh")"; then ok; else bad T19l "адрес прописными прошёл мимо предварительного поиска"; fi
# T19m (M2): бэклог в другом регистре — тот же файл на macOS, не судится.
bl "$HEAD
  **Скептик (opus).** L1 — адрес в \`BACKLOG.md:5\` устарел, \`hooks/x.sh:12\`."
assert_empty "$(edit "$P/backlog.md")" T19m
# T19n, T19o (M1): писатель меняет живой бэклог после того, как страж взял блок, — страж судит одну копию.
RH="$TMP/racehooks"; mkdir -p "$RH"; cp "$HOOK" "$RH/"
{ cat "$HOOKS_DIR/backlog-lib.sh"; cat <<'EOF'
eval "_orig_bib() $(declare -f backlog_item_block | tail -n +2)"
backlog_item_block() {
    _orig_bib "$@"; _rc=$?
    if [ -n "${RACE_FILE:-}" ] && [ ! -e "$RACE_FILE.raced" ]; then
        : > "$RACE_FILE.raced"
        case "$RACE_MODE" in
            prepend) { printf '%s\n' '- ☐ **D9100** Новый.' '  **Корень.** R1.' '  строка' '  строка' '  строка'; cat "$RACE_FILE"; } > "$RACE_FILE.tmp" ;;
            drop) awk 'NR < 6 || NR > 7' "$RACE_FILE" > "$RACE_FILE.tmp" ;;
        esac
        cat "$RACE_FILE.tmp" > "$RACE_FILE"
    fi
    return $_rc
}
EOF
} > "$RH/backlog-lib.sh"
race() { rm -f "$P/BACKLOG.md.raced"; RACE_FILE="$P/BACKLOG.md" RACE_MODE="$1" edit "$P/hooks/x.sh" Edit "$RH/guarantee-map-guard.sh"; }
bl "$HEAD
$FIND"
if denied "$(race prepend)"; then ok; else bad T19n "писатель добавил строки над пунктом — находка потеряна"; fi
bl '- ☐ **D9000** Старый пункт.
  **Корень.** R1.
  строка
  строка
- ◐ **D9001** Страж `hooks/x.sh` теряет запись.
  **Корень.** R1 — нет.
  **Скептик (opus).** H1 — `hooks/y.sh:12`.
  **Карта гарантий.** `hooks/y.sh` прогон `bash t.sh` → 0.
- ☐ **D9002** Другой.
  **Скептик (opus).** H1 — `hooks/x.sh:3`.
  строка
  строка'
assert_empty "$(race drop)" T19o

echo "guarantee-map-guard: $PASS passed, $FAIL failed"
exit $(( FAIL != 0 ))
