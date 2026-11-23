#!/usr/bin/env bash
# carry-log.sh — журнал переносов из репозитория в ~/.claude и третий исход доставщика.
# Результат: у каждого состоявшегося переноса есть запись (когда, чем, откуда, куда, хеш
#            приёмника, коммит репозитория), а приёмник, чей хеш не равен последнему записанному,
#            НЕ перезаписывается — доставщик отказывается и называет файл (исход «разошлось в обе
#            стороны», ADR-019, D350)
# Проверка результата: bash hooks/tests/test_carry_log.sh даёт 0
#
# Библиотека: только функции, при source ничего не делает. Потребители — `install.sh` и
# `scripts/sync-drifted.sh`, обе дороги из репозитория в ~/.claude. Дорог ДВЕ, и журнал держится,
# только если пишут обе: перенос мимо журнала выглядит для следующего переноса как чужая правка.
#
# Почему журнал, а не время файла. Признак «приёмник новее источника» был реализован и снят
# 7 сентября 2026: `cp` без `-p` ставит приёмнику текущее время, то есть показание производится
# самим переносом (6 срабатываний, настоящих 0 из 6). Хеш, записанный В МОМЕНТ переноса, —
# источник, независимый от механизма: приёмник с другим хешем правлен не нами.
#
# Формат `hooks/state/carry-log.tsv`, шесть полей через табуляцию:
#   когда (UTC)  чем (install.sh | sync-drifted)  откуда (источник)  куда (приёмник)
#   хеш приёмника после записи («алгоритм:значение»)  коммит репозитория (короткий sha либо «-»)
#
# Названный предел. Приёмник, о котором журнал не знает (положен до появления журнала либо мимо
# него), судить нечем: он переносится как прежде, двумя исходами, и получает первую запись.
# Условие снятия: первый прогон `install.sh` либо `sync-drifted.sh --apply` после этой правки
# записывает все свои приёмники — с этого момента предел касается только файлов, положенных
# мимо обеих дорог.

carry_log_path() { printf '%s\n' "${CARRY_LOG:-${CLAUDE_HOME:-$HOME/.claude}/hooks/state/carry-log.tsv}"; }

# Хеш файла с именем алгоритма: значения разных алгоритмов не должны сравниваться молча.
# `shasum` есть на macOS и на раннере, `sha256sum` — на Linux без perl, `cksum` — POSIX.
carry_hash() {
    if command -v shasum >/dev/null 2>&1; then printf 'sha256:%s\n' "$(shasum -a 256 "$1" | cut -d' ' -f1)"
    elif command -v sha256sum >/dev/null 2>&1; then printf 'sha256:%s\n' "$(sha256sum "$1" | cut -d' ' -f1)"
    else printf 'cksum:%s\n' "$(cksum < "$1" | cut -d' ' -f1)"
    fi
}

# Последний записанный хеш приёмника $1; пусто — журнал о нём не знает.
carry_last_hash() {
    local log; log=$(carry_log_path)
    [ -f "$log" ] || return 0
    awk -F'\t' -v d="$1" '$4 == d { h = $5 } END { if (h != "") print h }' "$log"
}

_CARRY_HEAD=""
_carry_repo_head() {
    if [ -z "$_CARRY_HEAD" ]; then
        _CARRY_HEAD=$(git -C "${CARRY_REPO:-${CLAUDSOUL_REPO:-${CLAUDSOUL_DIR:-.}}}" rev-parse --short HEAD 2>/dev/null)
        [ -n "$_CARRY_HEAD" ] || _CARRY_HEAD="-"
    fi
    printf '%s\n' "$_CARRY_HEAD"
}

_carry_append() { printf '%s\n' "$2" >> "$1"; }

# Запись состоявшегося переноса: $1 — чем, $2 — откуда, $3 — куда. Хеш берётся у ПРИЁМНИКА
# после записи — с ним следующий перенос сравнит его состояние. Под замком, если библиотека
# замков загружена потребителем (род H): писателей у журнала два.
carry_record() {
    local log line; log=$(carry_log_path)
    mkdir -p "$(dirname "$log")" 2>/dev/null || return 1
    line=$(printf '%s\t%s\t%s\t%s\t%s\t%s' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$1" "$2" "$3" \
                  "$(carry_hash "$3")" "$(_carry_repo_head)")
    if command -v with_lock >/dev/null 2>&1; then with_lock "$log" _carry_append "$log" "$line"
    else _carry_append "$log" "$line"; fi
}

# Третий исход: 0 — приёмник $2 РАЗОШЁЛСЯ В ОБЕ СТОРОНЫ с источником $1 (отличается и от
# источника, и от последнего записанного хеша), 1 — нет. Единственный владелец этого суждения:
# доставщики зовут его и для отчёта сухого прогона, и перед записью.
carry_diverged() {
    local last
    [ -f "$2" ] || return 1
    cmp -s "$1" "$2" && return 1
    last=$(carry_last_hash "$2")
    [ -n "$last" ] || return 1
    [ "$(carry_hash "$2")" != "$last" ]
}

# Перенос одного файла: $1 — чем, $2 — источник, $3 — приёмник.
# 0 — перенесено либо уже совпадало (запись сделана, если такого хеша у приёмника ещё нет);
# 1 — источника нет или копирование не удалось; 3 — разошлось в обе стороны, приёмник не тронут.
carry_file() {
    [ -f "$2" ] || return 1
    if [ -f "$3" ] && cmp -s "$2" "$3"; then
        [ "$(carry_hash "$3")" = "$(carry_last_hash "$3")" ] || carry_record "$1" "$2" "$3"
        return 0
    fi
    carry_diverged "$2" "$3" && return 3
    mkdir -p "$(dirname "$3")" 2>/dev/null
    command cp "$2" "$3" 2>/dev/null || return 1
    carry_record "$1" "$2" "$3"
    return 0
}

# carry_ordered <перенос> <пропуск> <имя…> — переносит хуки и библиотеки хуков так, чтобы новая редакция не встала рядом
# со старой библиотекой (D1166, решение владельца «чинить в установщике»). Имена — относительно `hooks/` («x.sh», «lib/y.py»);
# библиотека — `lib/*` и `*-lib.sh`. `<перенос> <имя>` отвечает кодом: 0 — перенесено (или запланировано в сухом
# прогоне), иначе — отбито или не удалось. `<пропуск> <имя> <основание>` зовётся для файла, который не переносится.
# Порядок:
#   1. Отказ, известный ДО переноса, — у владельца суждения: `carry_diverged` по каждой библиотеке, когда известен каталог
#      приёмника (`CARRY_DST_HOOKS`). Без него (тесты функции) отказ узнаётся только по коду переноса.
#   2. Замыкание (второй круг, скептик H1): библиотека, которая ПОДКЛЮЧАЕТ отбитую (`_carry_ordered_uses`), отбита сама — до неподвижной
#      точки. Цепочка «библиотека → библиотека → хук» живая: `root-cause-lib.sh` подключает `hook-input-lib.sh`, а
#      `session-collector.sh` называет только первую. Комментарий, докстрока и реестр-данные отказ не несут (третий круг),
#      иначе он ложно доходил до самой библиотеки ввода и останавливал треть установки.
#   3. Перенос: библиотеки, затем хуки. Файл, подключающий отбитую библиотеку, не переносится — кроме НОВОГО
#      (приёмника нет): пропущенный новый хук остаётся зарегистрированным и падает кодом 127 на каждом событии (M1),
#      поэтому он ставится. Неожиданный сбой переноса библиотеки добавляет её к отбитым для дальнейших файлов.
# Отбитые библиотеки копятся в CARRY_REFUSED_LIBS полными именами. Код берётся `|| rc=$?`: `install.sh` идёт под `set -e`.
# Пределы (D1173): полное имя библиотеки в строке сообщения (`deny "…"`, `echo`, текст heredoc) пока считается
# подключением — лишний пропуск хука; докстрока, открытая в середине строки (`X = """`) и закрытая в начале строки,
# переворачивает разбор; `importlib`, `__import__`, имя из частей не видны; потребитель, зовущий функции библиотеки без
# её имени (их подключает другая библиотека), не виден; новая библиотека-посредник отказ дальше не несёт; имена с
# пробелом не поддерживаются.
_carry_ordered_uses() {  # <имя> <библиотека…> → первая библиотека, которую файл ПОДКЛЮЧАЕТ; 1 — ни одной
    # Третий круг D1166 (скептик второго, H1): упоминание основания — не подключение. Реестр-данные называют библиотеки, а
    # докстроки — пути, и по ним отказ ложно доходил до самой библиотеки ввода. Здесь: файлы-данные не потребители; в
    # Python-файлах докстроки (`"""`) и комментарии пропускаются, в прочих — комментарии; совпадение — полное имя библиотеки
    # с границами либо импорт Python (`import x`, `from x import`) — и во вставках Python внутри оболочки.
    local _cu_n=$1 _cu_f _cu_r _cu_py=0
    shift
    _cu_f="${CARRY_SRC_HOOKS:-}/$_cu_n"
    [ -f "$_cu_f" ] || return 1
    case "$_cu_n" in *.tsv|*.md|*.json|*.txt|*.yml|*.yaml) return 1 ;; *.py) _cu_py=1 ;; esac
    _cu_r=$(LC_ALL=C awk -v own="${_cu_n##*/}" -v libs="$*" -v py="$_cu_py" "$_CARRY_USES_AWK" "$_cu_f" 2>/dev/null)
    [ -n "$_cu_r" ] || return 1
    printf '%s\n' "$_cu_r"
}
_CARRY_USES_AWK=$(cat <<'AWK'
BEGIN { n = split(libs, L, " ") }
function edge(s, i, j,   a, b) {
    a = (i > 1) ? substr(s, i - 1, 1) : " "; b = (j <= length(s)) ? substr(s, j, 1) : " "
    return (a !~ /[A-Za-z0-9_-]/) && (b !~ /[A-Za-z0-9_]/)
}
{
    line = $0
    if (py) {
        t = line; c = gsub(/"""/, "", t)
        if (indoc) { if (c % 2 == 1) indoc = 0; next }
        if (line ~ /^[[:space:]]*"""/) { if (c % 2 == 1) indoc = 1; next }
    }
    if (line ~ /^[[:space:]]*#/) next
    for (k = 1; k <= n; k++) {
        b = L[k]
        if (b == "" || b == own) continue
        off = 0
        while ((p = index(substr(line, off + 1), b)) > 0) {
            p += off
            if (edge(line, p, p + length(b))) { print b; exit }
            off = p
        }
        if (b ~ /\.py$/) {
            st = b; sub(/\.py$/, "", st)
            if (line ~ ("(^|[^A-Za-z0-9_])from[[:space:]]+" st "[[:space:]]+import([^A-Za-z0-9_]|$)") ||
                line ~ ("(^|[^A-Za-z0-9_])import[[:space:]]+([A-Za-z0-9_]+[[:space:]]*,[[:space:]]*)*" st "([^A-Za-z0-9_]|$)")) { print b; exit }
        }
    }
}
AWK
)
_carry_ordered_new() {  # <имя> → 0, если приёмника нет (новый файл) и каталог приёмника известен
    [ -n "${CARRY_DST_HOOKS:-}" ] && [ ! -e "$CARRY_DST_HOOKS/$1" ]
}
carry_ordered() {
    local _co_fn=$1 _co_skip=$2 _co_n _co_rc _co_b _co_s _co_libs="" _co_rest="" _co_div="" _co_chg
    shift 2
    CARRY_REFUSED_LIBS="${CARRY_REFUSED_LIBS:-}"
    for _co_n in "$@"; do
        case "$_co_n" in lib/*|*-lib.sh) _co_libs="$_co_libs $_co_n" ;; *) _co_rest="$_co_rest $_co_n" ;; esac
    done
    if [ -n "${CARRY_DST_HOOKS:-}" ]; then
        for _co_n in $_co_libs; do
            if carry_diverged "${CARRY_SRC_HOOKS:-}/$_co_n" "$CARRY_DST_HOOKS/$_co_n"; then
                _co_div="$_co_div $_co_n"; CARRY_REFUSED_LIBS="$CARRY_REFUSED_LIBS ${_co_n##*/}"
            fi
        done
    fi
    _co_chg=1
    while [ "$_co_chg" = 1 ]; do
        _co_chg=0
        for _co_n in $_co_libs; do
            _co_s=${_co_n##*/}
            case " $CARRY_REFUSED_LIBS " in *" $_co_s "*) continue ;; esac
            _carry_ordered_new "$_co_n" && continue
            # shellcheck disable=SC2086
            _carry_ordered_uses "$_co_n" $CARRY_REFUSED_LIBS >/dev/null || continue
            CARRY_REFUSED_LIBS="$CARRY_REFUSED_LIBS $_co_s"; _co_chg=1
        done
    done
    for _co_n in $_co_libs $_co_rest; do
        case " $_co_div " in *" $_co_n "*) "$_co_fn" "$_co_n" || true; continue ;; esac   # «разошлось» назовёт переносчик
        # shellcheck disable=SC2086
        if _co_b=$(_carry_ordered_uses "$_co_n" $CARRY_REFUSED_LIBS) && ! _carry_ordered_new "$_co_n"; then
            "$_co_skip" "$_co_n" "$_co_b" || true
            continue
        fi
        _co_rc=0; "$_co_fn" "$_co_n" || _co_rc=$?
        case "$_co_n" in
            lib/*|*-lib.sh) if [ "$_co_rc" -ne 0 ]; then CARRY_REFUSED_LIBS="$CARRY_REFUSED_LIBS ${_co_n##*/}"; fi ;;
        esac
    done
    return 0
}
