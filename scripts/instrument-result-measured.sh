#!/usr/bin/env bash
# instrument-result-measured.sh — объявленный результат инструмента ИЗМЕРЕН: есть свидетель,
# который краснеет, когда инструмент подменён заглушкой `exit 0`, и зелен на живом.
#
# Результат: у каждого инструмента scripts/ есть свидетель — тест hooks/tests/test_*.sh, красный
#            на выпотрошенном инструменте и зелёный на живом; инструментов без свидетеля ноль,
#            снимок совпадает с деревом.
# Проверка результата: bash scripts/instrument-result-measured.sh --check даёт 0 — снимок свеж и
#            не измеренных нет; 1 — есть не измеренные либо устаревшие; 2 — прибор сломан
#            (универсум пуст, копия дерева не собралась, нет hash-lib).
#
# Зачем (D282). Контракт ADR-013 требует от инструмента строк «# Результат:» и «# Проверка
# результата:», и страж `test_instrument_contract.sh` проверяет их НАЛИЧИЕ. Меряет ли вторая
# первую — не проверял никто: у `scripts/split-provenance-log.py` проверкой стоял
# `grep -l 'provenance_log:' …`, зелёный при одном совпавшем файле из 440. Признак, по которому
# это ловится, — ПОВЕДЕНЧЕСКИЙ, и это измерено в тот же день: маркер формы (упоминание имени
# инструмента в тесте) дал 25 инструментов с одним упоминанием, а упоминание не значит, что
# тест покраснеет на мёртвом инструменте (`pattern-marker-matches-form-not-role`, четыре
# инжекта 12 сентября 2026 без исхода). Поэтому здесь роль свидетеля устанавливается
# ИСПОЛНЕНИЕМ под мутацией, а не чтением: инструмент подменяется заглушкой, свидетель обязан
# покраснеть; тот же приём стоял руками в D282 и D379 («копия инструмента до правки,
# отдельное дерево на вариант»), здесь он стал механизмом.
#
# Устройство. Дерево копируется из индекса git во временный каталог (вместе с .git — универсум
# и 84 теста зовут git); в копии инструмент подменяется заглушкой `exit 0` (для .py — с
# шебангом, чтобы прямой вызов не падал кодом 126, что сошло бы за «покраснел»); кандидаты в
# свидетели гонятся ДЕШЕВЛЕ-ПЕРВЫМИ по базису набора (`suite-baseline.tsv`): тест из строки
# «Проверка результата», затем `test_<имя>.sh`, затем тесты, упоминающие имя инструмента.
# Красный под заглушкой кандидат прогоняется ещё раз без заглушки: красный и там — не
# свидетель, а сломанный тест (среда), и он не засчитывается. Зависший под заглушкой (снят
# сторожем) свидетелем тоже не считается: зависание — не вердикт.
#
# Что НЕ доказано (названный предел). Свидетель различает «инструмент мёртв» и «инструмент
# жив»; что режим `--check` инструмента меряет именно объявленный результат, а не соседний,
# заглушка целиком не различит — на это нужна мутация МИРА, то есть фикстура под каждый
# инструмент, как в `test_split_provenance_log.sh`. Условие снятия: мутант «режим проверки
# всегда отвечает 0» (подмена только ветки check) и свидетель, красный на нём.
#
# Снимок: $STATE_DIR/instrument-result-measured.tsv — инструмент, ключ, вердикт, свидетель,
# секунды, дата, причина. Ключ — хеш инструмента и всех его кандидатов: правка любого из них
# обесценивает строку. Снимком владеет этот прибор, и только он в него пишет (замок state-lock).
#
# Применение:
#   instrument-result-measured.sh [--all] [инструмент…]   замер; без --all строки с совпавшим
#                                                        ключом берутся из снимка
#   instrument-result-measured.sh --check                  только чтение: снимок против дерева
# Переменные: IRM_ROOT (корень дерева — для тестов), IRM_TIMEOUT (срок свидетеля без базиса,
# 120 с), STATE_DIR, SUITE_BASELINE_FILE.
set -uo pipefail
_here=$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" 2>/dev/null && pwd -P)
ROOT="${IRM_ROOT:-$(cd "${_here}/.." && pwd -P)}"
# shellcheck source=/dev/null
. "${_here}/../hooks/hash-lib.sh" 2>/dev/null || { echo "instrument-result-measured: нет hooks/hash-lib.sh рядом со скриптом" >&2; exit 2; }
# shellcheck source=/dev/null
. "${_here}/../hooks/lib/universe-lib.sh" 2>/dev/null || { echo "instrument-result-measured: нет hooks/lib/universe-lib.sh" >&2; exit 2; }
# shellcheck source=/dev/null
. "${_here}/../hooks/state-lock-lib.sh" 2>/dev/null || { echo "instrument-result-measured: нет hooks/state-lock-lib.sh" >&2; exit 2; }

# git отдаёт пути без экранирования: при core.quotePath (умолчание) не-ASCII имя одного
# инструмента приходило октетами в кавычках, хеш не считался, и весь прогон падал кодом 2
# (прожарка 12 сентября 2026, атака 8). Переменная действует на universe-lib и на копию.
export GIT_CONFIG_PARAMETERS="${GIT_CONFIG_PARAMETERS:+${GIT_CONFIG_PARAMETERS} }'core.quotePath=false'"

STATE="${STATE_DIR:-${HOME}/.claude/hooks/state}"
SNAP="${STATE}/instrument-result-measured.tsv"
BASELINE="${SUITE_BASELINE_FILE:-${STATE}/suite-baseline.tsv}"
TIMEOUT="${IRM_TIMEOUT:-120}"
# Базиса нет — говорится вслух, а не гасится умолчанием: порядок кандидатов без него
# алфавитный, срок свидетеля общий (IRM_TIMEOUT), и читатель обязан это знать.
[ -f "${BASELINE}" ] || echo "instrument-result-measured: базиса набора нет (${BASELINE}) — кандидаты без порядка по цене, срок ${TIMEOUT} с" >&2

MODE=measure; ALL=0; ONLY=""
for _a in "$@"; do
    case "${_a}" in
        --check) MODE=check ;;
        --all) ALL=1 ;;
        -*) echo "применение: $(basename "$0") [--all] [инструмент…] | --check" >&2; exit 2 ;;
        *) ONLY="${ONLY}${_a}
" ;;
    esac
done

UNIVERSE_ROOT="${ROOT}"
LIST=$(universe_instruments) || exit 2
LIST=$(printf '%s\n' "${LIST}" | grep -v '^scripts/publish/')
TRACKED_TESTS=$(git -C "${ROOT}" ls-files 'hooks/tests/test_*.sh' 2>/dev/null)
if [ -n "${ONLY}" ]; then
    LIST=$(printf '%s\n' "${LIST}" | grep -F -x -f <(printf '%s' "${ONLY}"))
    [ -n "${LIST}" ] || { echo "instrument-result-measured: названные инструменты не в универсуме" >&2; exit 2; }
fi

# Кандидаты в свидетели, дешевле-первыми: тест из шапки и test_<имя>.sh идут с ценой 0,
# упоминающие имя — по базису набора, без базиса — в конец.
candidates() {
    local f="$1" b stem l w1 w2 t c
    b=$(basename "${f}"); stem="${b%.*}"; stem=$(printf '%s' "${stem}" | tr '-' '_')
    l=$(head -40 "${ROOT}/${f}" | grep -m1 -E '^#[[:space:]]*Проверка результата:')
    w1=$(printf '%s' "${l}" | grep -oE 'test_[A-Za-z0-9_]+\.sh' | head -1)
    w2="test_${stem}.sh"
    # Кандидаты — только тесты ИЗ ИНДЕКСА git, как и копия дерева: у понятия «что есть в
    # дереве» один владелец. Пока кандидаты брались шаблоном по каталогу, неотслеживаемый тест
    # был кандидатом в ROOT и отсутствовал в копии — «красен и без заглушки», а после
    # `git add` ключ не менялся, и вердикт жил в снимке (12 сентября 2026, свидетель проб).
    # Имя ищется ЦЕЛИКОМ, а не подстрокой: `log.sh` совпадало внутри `activity-log.sh`, и тесты
    # чужого хука входили в кандидаты и в ключ снимка — правка чужого теста старила снимок
    # (раунд 2, атака 3). Граница — символ, который не может быть частью имени файла.
    # Один `grep` на инструмент через xargs, а не по вызову на каждый тест: цикл по 461 тесту
    # для 88 инструментов давал ~40 000 процессов, и нога T14 теста прибора под параллелью
    # набора не укладывалась в срок сторожа (код 137 на 148-й секунде, 12 сентября 2026).
    local re; re=$(printf '%s' "${b}" | sed 's/[.]/\\./g')
    re="(^|[^A-Za-z0-9_.-])${re}([^A-Za-z0-9_.-]|\$)"
    {
        [ -n "${w1}" ] && grep -qx "hooks/tests/${w1}" <<< "${TRACKED_TESTS}" && printf '0\t%s\n' "${w1}"
        grep -qx "hooks/tests/${w2}" <<< "${TRACKED_TESTS}" && printf '0\t%s\n' "${w2}"
        [ -n "${TRACKED_TESTS}" ] && printf '%s\n' "${TRACKED_TESTS}" | ( cd "${ROOT}" && xargs grep -l -E -- "${re}" 2>/dev/null ) | while IFS= read -r t; do
            t=$(basename "${t}")
            c=$(awk -F'\t' -v n="${t}" '$2 == n { print $1; exit }' "${BASELINE}" 2>/dev/null)
            # Цены нет (теста нет в базисе либо базиса нет) — МАРКЕР, а не выдуманное число
            # (род B): неизвестные идут после известных по построению, а не по величине.
            case "${c}" in ''|*[!0-9]*) c='-' ;; esac
            printf '%s\t%s\n' "${c}" "${t}"
        done || true   # grep без находок отвечает 1, а это не отказ группы (pipefail)
    } | awk -F'\t' '{ print (($1 == "-") ? 1 : 0) "\t" $0 }' \
      | sort -t "$(printf '\t')" -k1,1n -k2,2n -k3,3 | awk -F'\t' '!seen[$3]++ { print $3 }'
}

# Ключ — содержимое инструмента и ИМЯ+содержимое каждого кандидата, отсортированные по имени:
# порядок цен из базиса в ключ не входит (прожарка 12 сентября 2026, атака 1 — перестановка
# цен обесценивала снимок при нетронутом дереве, так устарели 26 строк), а переименование
# кандидата его обесценивает (атака 7 — снимок держал свидетеля, которого в дереве нет).
key_of() {
    local f="$1" acc h t pairs=""
    acc=$(hash_file "${ROOT}/${f}") || return 1
    for t in $(candidates "${f}"); do
        h=$(hash_file "${ROOT}/hooks/tests/${t}") || return 1
        pairs="${pairs}${t} ${h}
"
    done
    hash_value "${acc}
$(printf '%s' "${pairs}" | sort)"
}

snap_row() { # $1 инструмент → строка снимка либо пусто
    [ -f "${SNAP}" ] || return 0
    awk -F'\t' -v f="$1" '$1 == f { print; exit }' "${SNAP}" 2>/dev/null
}

# ---------- режим --check: только чтение ----------
if [ "${MODE}" = check ]; then
    n=0; ok=0; bad=0
    while IFS= read -r f; do
        [ -n "${f}" ] || continue
        n=$((n + 1))
        key=$(key_of "${f}") || { echo "instrument-result-measured: не посчитан ключ ${f}" >&2; exit 2; }
        row=$(snap_row "${f}")
        if [ -z "${row}" ]; then
            bad=$((bad + 1)); printf 'НЕТ СНИМКА   %s\n' "${f}"; continue
        fi
        skey=$(printf '%s' "${row}" | cut -f2); verdict=$(printf '%s' "${row}" | cut -f3)
        if [ "${skey}" != "${key}" ]; then
            bad=$((bad + 1)); printf 'УСТАРЕЛ      %s\n' "${f}"
        elif [ "${verdict}" = "измерен" ] && [ ! -f "${ROOT}/hooks/tests/$(printf '%s' "${row}" | cut -f4)" ]; then
            bad=$((bad + 1)); printf 'УСТАРЕЛ      %s — свидетеля %s нет в дереве\n' "${f}" "$(printf '%s' "${row}" | cut -f4)"
        elif [ "${verdict}" != "измерен" ]; then
            bad=$((bad + 1)); printf 'НЕ ИЗМЕРЕН   %s — %s\n' "${f}" "$(printf '%s' "${row}" | cut -f7)"
        else
            ok=$((ok + 1))
        fi
    done <<< "${LIST}"
    [ "${n}" -gt 0 ] || { echo "instrument-result-measured: универсум пуст" >&2; exit 2; }
    echo "инструментов: ${n}; измерено и свежо: ${ok}; не измерено, устарело или без снимка: ${bad}"
    exit $(( bad != 0 ))
fi

# ---------- режим замера ----------
# Зависимость проверяется ДО замера: без perl сторож отвечал 127 в обоих плечах, и это
# ложилось в снимок вердиктом «красен и без заглушки» кодом 1 — отказ прибора выглядел как
# сломанный тест и переживал возвращение perl (атака 2). Отказ прибора — код 2 и ни строки.
command -v perl >/dev/null 2>&1 || { echo "instrument-result-measured: нет perl — сторож свидетеля не собрать, замер не начат" >&2; exit 2; }
W=$(mktemp -d "${TMPDIR:-/tmp}/irm.XXXXXX") || { echo "instrument-result-measured: mktemp отказал" >&2; exit 2; }
trap 'rm -rf "${W}"' EXIT
T="${W}/tree"; mkdir -p "${T}" "${W}/sessions"
# Копия из ИНДЕКСА, а не каталога: неотслеживаемое (venv, node_modules) не тащится, а
# файл, удалённый из рабочего дерева без git rm, пропускается, а не роняет tar.
# `-h` разыменовывает симлинки: иначе заглушка ложилась сквозь ссылку в файл ВНЕ копии
# (атака 6), а `cp -p` восстанавливал его так, что снаружи следа не оставалось.
( cd "${ROOT}" && git ls-files -z | while IFS= read -r -d '' p; do [ -f "${p}" ] && printf '%s\0' "${p}"; done \
    | tar -chf - --null -T - ) | tar -xf - -C "${T}" 2>/dev/null
# Собралась ли копия, судится по РОЛИ (первый инструмент универсума лежит в копии), а не по
# имени файла настоящего дерева: ориентир `hooks/lib/universe-lib.sh` был верен в репозитории и
# ложен в любой фикстуре — поймано первым же прогоном теста, 12 сентября 2026.
_first=$(printf '%s\n' "${LIST}" | head -1)
[ -f "${T}/${_first}" ] || { echo "instrument-result-measured: копия дерева не собралась в ${T} (нет ${_first})" >&2; exit 2; }
# Linked worktree держит в `.git` ФАЙЛ-указатель, и его копия делила бы индекс и HEAD с
# настоящим деревом — git-операции свидетеля из «копии» ложились в живой worktree (атака 9).
# Такой копии даётся свой репозиторий из скопированных файлов: универсум и тесты видят
# индекс, истории нет, и это сказано вслух.
if [ -d "${ROOT}/.git" ]; then
    cp -R "${ROOT}/.git" "${T}/.git" 2>/dev/null || { echo "instrument-result-measured: не скопирован .git" >&2; exit 2; }
elif [ -f "${ROOT}/.git" ]; then
    echo "instrument-result-measured: ${ROOT} — linked worktree, копия получает свой git без истории" >&2
    ( cd "${T}" && git init -q && git add -A ) 2>/dev/null || { echo "instrument-result-measured: не собран git копии" >&2; exit 2; }
else
    echo "instrument-result-measured: в ${ROOT} нет .git" >&2; exit 2
fi

stub() { # $1 путь в копии
    cp -p "$1" "${W}/orig" || return 1
    # Шапка (шебанг и комментарии до первой строки кода) СОХРАНЯЕТСЯ: заглушка, стиравшая
    # шапку, делала тест формы — `grep "^# Результат:"` — красным под заглушкой, и тест,
    # ни разу не исполнивший инструмент, сходил за свидетеля поведения (атака 4).
    awk '/^#/ || /^[[:space:]]*$/ { print; next } { exit }' "${W}/orig" > "$1"
    # Заглушка оставляет СЛЕД исполнения в файле из IRM_TRACE: свидетель засчитывается, только
    # если инструмент под заглушкой действительно исполнялся. Без следа тест, сверяющий байты
    # файла — `git diff --quiet`, хеш, размер, mtime, — краснел от самой подмены и сходил за
    # свидетеля поведения, ни разу не исполнив инструмент (раунд 2, атака 1).
    case "$1" in
        *.py) printf 'import os, sys\ntry:\n    open(os.environ.get("IRM_TRACE", os.devnull), "a").write("x")\nexcept Exception:\n    pass\nsys.exit(0)\n' >> "$1" ;;
        # `return` — для инструмента, который тест ИСТОЧАЕТ: голый `exit 0` завершал сам тест
        # кодом 0, и настоящий свидетель отвергался (атака 5); при запуске `return` вне
        # функции отказывает, и срабатывает `exit`.
        *)    printf 'printf x >> "${IRM_TRACE:-/dev/null}" 2>/dev/null\nreturn 0 2>/dev/null || exit 0\n' >> "$1" ;;
    esac
}
unstub() { cp -p "${W}/orig" "$1"; }

deadline() { # $1 тест → секунд
    local b
    b=$(awk -F'\t' -v n="$1" '$2 == n { print $1; exit }' "${BASELINE}" 2>/dev/null)
    case "${b:-}" in ''|*[!0-9]*) printf '%s' "${TIMEOUT}"; return ;; esac
    b=$((b * 2)); [ "${b}" -lt 15 ] && b=15
    printf '%s' "${b}"
}

_rc=0; _secs=0; _run_n=0
run_test() { # $1 тест; кладёт код в _rc, секунды в _secs
    local t="$1" dl t0
    dl=$(deadline "${t}"); t0=$(date +%s); _run_n=$((_run_n + 1))
    # Сторож — perl: своя группа процессов, по сроку убивается ВСЯ группа (в bash без
    # coreutils нет ни timeout, ни setsid; `_kill_tree` раннера здесь не библиотека).
    # Каталог сессий и вывод — СВОИ у каждого плеча: общие между плечом под заглушкой и
    # плечом без неё, они делали свидетелем тест, красный на первом прогоне и зелёный на
    # втором, который инструмент не исполнял ни разу (атака 3). Названный предел: HOME и
    # STATE_DIR общие — тест, пишущий состояние туда, тем же способом обманет прибор;
    # условие снятия — песочница HOME на каждое плечо.
    # Сторож отвечает 124 ТОЛЬКО когда срок вышел: прежде он убивал свою группу вместе с
    # собой, и любой код ≥ 128 читался как «завис» — в том числе 141 (SIGPIPE) и 143 от самого
    # теста, и настоящий свидетель отвергался, а плечо без заглушки не стартовало (раунд 2,
    # атака 2). Теперь в своей группе только ребёнок, сторож переживает его и различает.
    ( cd "${T}/hooks/tests" && CLAUDSOUL_ROOT="${T}" CLAUDSOUL_REPO="${T}" SR_SESSIONS_DIR="${W}/sessions/${t}.${_run_n}" \
        IRM_TRACE="${W}/trace.${_run_n}" \
        perl -e 'my $t = shift; my $pid = fork; if (!$pid) { setpgrp(0, 0); exec @ARGV }
                 my $late = 0; $SIG{ALRM} = sub { $late = 1; kill "KILL", -$pid, $pid }; alarm $t;
                 my $r = waitpid($pid, 0); $r = waitpid($pid, 0) if $r == -1;
                 my $s = $?; exit 124 if $late;
                 exit(($s & 127) ? 128 + ($s & 127) : $s >> 8)' \
            "${dl}" bash "${t}" >"${W}/out.${_run_n}.txt" 2>&1 </dev/null )
    _rc=$?
    _secs=$(( $(date +%s) - t0 ))
}

measure_one() { # $1 инструмент → в переменные: R_VERDICT R_WITNESS R_SECS R_WHY
    local f="$1" t n=0 total=0 why=""
    local cands; cands=$(candidates "${f}")
    R_VERDICT="НЕ ИЗМЕРЕН"; R_WITNESS="-"; R_SECS=0; R_WHY=""
    if [ -z "${cands}" ]; then
        R_WHY="кандидатов нет: ни тест из шапки, ни test_<имя>.sh, ни упоминание в hooks/tests"
        return
    fi
    stub "${T}/${f}" || { R_WHY="заглушка не легла"; return; }
    for t in ${cands}; do
        n=$((n + 1))
        run_test "${t}"; total=$((total + _secs)); _stub_run="${_run_n}"
        if [ "${_rc}" -eq 0 ]; then why="${why} ${t}=зелёный"; continue; fi
        if [ "${_rc}" -eq 124 ]; then why="${why} ${t}=завис"; continue; fi
        # Красен, а инструмент не исполнялся (след заглушки пуст): тест судит о ФАЙЛЕ —
        # git diff, хеш, размер, шапка, — а не о поведении. Не свидетель (раунд 2, атака 1).
        if [ ! -s "${W}/trace.${_stub_run}" ]; then why="${why} ${t}=красен_не_исполнив_инструмент"; continue; fi
        # Красный под заглушкой — обязан быть зелёным без неё, иначе это сломанный тест.
        unstub "${T}/${f}"; run_test "${t}"; total=$((total + _secs))
        if [ "${_rc}" -eq 0 ]; then
            R_VERDICT="измерен"; R_WITNESS="${t}"; R_SECS="${total}"; return
        fi
        stub "${T}/${f}"; why="${why} ${t}=красен_и_без_заглушки"
    done
    unstub "${T}/${f}"
    R_SECS="${total}"; R_WHY="кандидатов ${n}, свидетеля нет:${why}"
}

NEW="${W}/snap.tsv"; : > "${NEW}"
n=0; measured=0; unmeasured=0; from_snap=0; ran=0; t_all=$(date +%s)
while IFS= read -r f; do
    [ -n "${f}" ] || continue
    n=$((n + 1))
    key=$(key_of "${f}") || { echo "instrument-result-measured: не посчитан ключ ${f}" >&2; exit 2; }
    row=$(snap_row "${f}")
    if [ "${ALL}" -eq 0 ] && [ -n "${row}" ] && [ "$(printf '%s' "${row}" | cut -f2)" = "${key}" ]; then
        from_snap=$((from_snap + 1))
        printf '%s\n' "${row}" >> "${NEW}"
        verdict=$(printf '%s' "${row}" | cut -f3)
        if [ "${verdict}" = "измерен" ]; then
            measured=$((measured + 1)); printf 'измерен      %s ← %s (из снимка)\n' "${f}" "$(printf '%s' "${row}" | cut -f4)"
        else
            unmeasured=$((unmeasured + 1)); printf 'НЕ ИЗМЕРЕН   %s — %s (из снимка)\n' "${f}" "$(printf '%s' "${row}" | cut -f7)"
        fi
        continue
    fi
    ran=$((ran + 1))
    measure_one "${f}"
    printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\n' "${f}" "${key}" "${R_VERDICT}" "${R_WITNESS}" "${R_SECS}" "$(date +%Y-%m-%d)" "${R_WHY}" >> "${NEW}"
    if [ "${R_VERDICT}" = "измерен" ]; then
        measured=$((measured + 1)); printf 'измерен      %s ← %s (%s с)\n' "${f}" "${R_WITNESS}" "${R_SECS}"
    else
        unmeasured=$((unmeasured + 1)); printf 'НЕ ИЗМЕРЕН   %s — %s (%s с)\n' "${f}" "${R_WHY}" "${R_SECS}"
    fi
done <<< "${LIST}"
[ "${n}" -gt 0 ] || { echo "instrument-result-measured: универсум пуст" >&2; exit 2; }

# Снимок: строки, не попавшие в этот прогон (замер по списку), переносятся из прежнего как есть.
_merge() {
    { cat "${NEW}"
      if [ -f "${SNAP}" ]; then awk -F'\t' 'NR == FNR { seen[$1] = 1; next } !($1 in seen)' "${NEW}" "${SNAP}"; fi
    } | sort > "${SNAP}.tmp" && mv -f "${SNAP}.tmp" "${SNAP}"
}
mkdir -p "${STATE}" 2>/dev/null
with_lock "${SNAP}" _merge || { echo "instrument-result-measured: снимок не записан в ${SNAP}" >&2; exit 2; }

echo "инструментов: ${n}; измерено: ${measured}; не измерено: ${unmeasured}; из снимка: ${from_snap}; прогнано: ${ran}; время: $(( $(date +%s) - t_all )) с; снимок: ${SNAP}"
exit $(( unmeasured != 0 ))
