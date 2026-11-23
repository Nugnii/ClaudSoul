#!/usr/bin/env bash
# СУДИТ: scripts/probes/R1.sh scripts/probes/R2.sh scripts/probes/R3.sh scripts/probes/R4.sh scripts/probes/R5.sh
# test_probes_print_carriers.sh — проба корня печатает носителя, который есть, и молчит, когда его нет.
#
# Результат: у проб R1–R5 карты ROOTS.md есть свидетель поведения — на фикстуре с одним известным
#            носителем каждая печатает его строку, на чистой фикстуре не печатает ничего.
# Проверка результата: этот тест.
#
# Повод (D282, 12 сентября 2026). Прибор `scripts/instrument-result-measured.sh` назвал пробы
# R1–R5 неизмеренными: ни один тест их не гоняет, и объявленная проверка `| grep -c . — ноль
# строк значит достигнуто` отвечает «достигнуто» и на МЁРТВОЙ пробе (класс R6: два состояния
# мира в одном значении канала). У R6 свидетель уже есть — `test_root_map.sh`; здесь тот же
# приём для остальных: фикстура на пробу, положительный контроль плюс отрицательный.
#
# Фикстуры — отдельный каталог на пробу; пробы ходят в `${CLAUDSOUL_REPO}`, а R2 и R3 зовут git
# (git grep, git ls-files), поэтому их фикстуры — репозитории с добавленными файлами.
# НАЗВАННЫЙ ПРЕДЕЛ: отрицательный контроль R5 удовлетворяет каждую семью её же командой из
# пробы, то есть повторяет перечень семей; новая семья в пробе покраснит ногу T5b, пока сюда не
# добавят её удовлетворение. Условие снятия: проба R5 начнёт выводить семьи из дерева, а не из
# списка (её собственный названный предел).
set -uo pipefail
DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "${DIR}/../.." && pwd)"

# Предмет этого свидетеля в публичный снимок не входит (пробы корней scripts/probes/). В неполном дереве
# «файла нет» значит «изъят по решению», а не «пропал»: пропуск называется, дефект не
# объявляется — иначе один канал несёт два состояния мира (корень R6).
UNIVERSE_ROOT="$ROOT"; . "$ROOT/hooks/lib/universe-lib.sh" 2>/dev/null || true
if command -v universe_partial_tree >/dev/null 2>&1 && universe_partial_tree; then
    universe_skip_note "test_probes_print_carriers" "пробы корней scripts/probes/"; exit 0
fi
PROBES="${ROOT}/scripts/probes"
PASS=0; FAIL=0
ok() { PASS=$((PASS + 1)); }
bad() { FAIL=$((FAIL + 1)); echo "FAIL [$1]: $2"; }
TMP=$(mktemp -d); trap 'rm -rf "${TMP}"' EXIT

# Прогон пробы на фикстуре: stdout в переменную, код в RC. Имена проб ниже написаны
# БУКВАЛЬНО (R1.sh, а не R1 плюс .sh): прибор свидетелей ищет кандидатов по буквальному
# имени файла в тексте теста, и первая редакция с именем из частей для него не существовала.
probe() { # $1 файл пробы, $2 корень фикстуры
    OUT=$(CLAUDSOUL_REPO="$2" bash "${PROBES}/$1" 2>"${TMP}/$1.err"); RC=$?
}
mkfx() { # $1 каталог → hooks/ scripts/ внутри
    mkdir -p "$1/hooks" "$1/scripts"
}
gitfx() { git init -q "$1" && git -C "$1" add -A; }

for p in R1.sh R2.sh R3.sh R4.sh R5.sh; do
    [ -f "${PROBES}/${p}" ] || { bad "${p}" "пробы ${p} нет на месте — свидетеля нет"; }
done

# --- R1: одно имя файла состояния собрано литералом в двух файлах ---
FX="${TMP}/r1"; mkfx "${FX}"
printf '#!/usr/bin/env bash\nf="$STATE_DIR/shared.txt"\n' > "${FX}/hooks/a.sh"
printf '#!/usr/bin/env bash\ng="${STATE_DIR}/shared.txt"\n' > "${FX}/scripts/b.sh"
probe R1.sh "${FX}"
if grep -q 'shared.txt' <<< "${OUT}"; then ok; else bad T1a "R1 не напечатала носителя shared.txt: rc=${RC}, вывод «${OUT}», stderr «$(cat "${TMP}/R1.err")»"; fi
FX="${TMP}/r1clean"; mkfx "${FX}"
printf '#!/usr/bin/env bash\nf="$STATE_DIR/alone.txt"\n' > "${FX}/hooks/a.sh"
printf '#!/usr/bin/env bash\necho ok\n' > "${FX}/scripts/b.sh"
probe R1.sh "${FX}"
if [ -z "${OUT}" ]; then ok; else bad T1b "R1 напечатала носителя на чистой фикстуре: «${OUT}»"; fi

# --- R2: файл состояния только пишется, читателя нет ---
FX="${TMP}/r2"; mkfx "${FX}"
printf '#!/usr/bin/env bash\nprintf "x\\n" >> "$STATE_DIR/orphan.log"\n' > "${FX}/hooks/w.sh"
gitfx "${FX}" || bad T2 "фикстура R2 не стала git-репозиторием"
probe R2.sh "${FX}"
if grep -q 'orphan.log' <<< "${OUT}"; then ok; else bad T2a "R2 не напечатала носителя orphan.log: rc=${RC}, вывод «${OUT}», stderr «$(cat "${TMP}/R2.err")»"; fi
printf '#!/usr/bin/env bash\ncat "$STATE_DIR/orphan.log"\n' > "${FX}/hooks/r.sh"
git -C "${FX}" add -A
probe R2.sh "${FX}"
if [ -z "${OUT}" ]; then ok; else bad T2b "R2 напечатала носителя при живом читателе: «${OUT}»"; fi

# --- R3: роль решается регулярным выражением по свободной речи (команда из tool_input) ---
FX="${TMP}/r3"; mkfx "${FX}"
printf '#!/usr/bin/env bash\ncmd=$(jq -r .tool_input.command)\ngrep -qE "rm -rf|git push" <<< "$cmd" && echo x\n' > "${FX}/hooks/g.sh"
gitfx "${FX}" || bad T3 "фикстура R3 не стала git-репозиторием"
probe R3.sh "${FX}"
if grep -q '^hooks/g.sh:3' <<< "${OUT}"; then ok; else bad T3a "R3 не напечатала носителя hooks/g.sh:3: rc=${RC}, вывод «${OUT}», stderr «$(cat "${TMP}/R3.err")»"; fi
printf '#!/usr/bin/env bash\ncmd="static"\ngrep -qE "rm -rf|git push" <<< "$cmd" && echo x\n' > "${FX}/hooks/g.sh"
git -C "${FX}" add -A
probe R3.sh "${FX}"
if grep -q '^hooks/' <<< "${OUT}"; then bad T3b "R3 напечатала носителя без свободной речи: «${OUT}»"; else ok; fi

# --- R4: прошедшее считается вычитанием меток и делится на 86400 ---
FX="${TMP}/r4"; mkfx "${FX}"
printf '#!/usr/bin/env bash\nage=$(( (now_s - last) / 86400 ))\n' > "${FX}/hooks/t.sh"
probe R4.sh "${FX}"
if grep -q '^hooks/t.sh:2' <<< "${OUT}"; then ok; else bad T4a "R4 не напечатала носителя hooks/t.sh:2: rc=${RC}, вывод «${OUT}», stderr «$(cat "${TMP}/R4.err")»"; fi
printf '#!/usr/bin/env bash\necho ok\n' > "${FX}/hooks/t.sh"
probe R4.sh "${FX}"
if [ -z "${OUT}" ]; then ok; else bad T4b "R4 напечатала носителя на чистой фикстуре: «${OUT}»"; fi

# --- R5: семья объявлений без сверщика ---
FX="${TMP}/r5"; mkfx "${FX}"
probe R5.sh "${FX}"
if grep -q 'контракт-результата' <<< "${OUT}"; then ok; else bad T5a "R5 на голой фикстуре не назвала семью контракт-результата: rc=${RC}, вывод «${OUT}»"; fi
# Каждая семья удовлетворяется тем, что ищет её команда в пробе (см. предел в шапке).
mkdir -p "${FX}/hooks/tests" "${FX}/scripts"
printf '#!/usr/bin/env bash\nexit 1\n' > "${FX}/scripts/instrument-result-measured.sh"; chmod +x "${FX}/scripts/instrument-result-measured.sh"
printf '# required_from_template\n' > "${FX}/hooks/k.sh"
printf '# min\n' > "${FX}/hooks/tests/test_ablation_protocol_claims.sh"
printf '# by-name\n' > "${FX}/scripts/doc-claims.tsv"
printf '# critic_rounds\n' > "${FX}/scripts/measurements.tsv"
printf '# Корень\n' > "${FX}/hooks/tests/test_backlog_item_shape.sh"
printf 'import sys\nsys.exit(0)\n' > "${FX}/scripts/signal-precision-corpus.py"
printf '# global-lessons\n' > "${FX}/hooks/tests/test_five_whys_gate.sh"
gitfx "${FX}" || bad T5 "фикстура R5 не стала git-репозиторием"
probe R5.sh "${FX}"
if [ -z "${OUT}" ]; then ok; else bad T5b "R5 назвала семью при удовлетворённых сверщиках: «${OUT}»"; fi

echo ""
echo "probes print carriers: ${PASS}/$((PASS + FAIL)) passed"
exit $(( FAIL != 0 ))
