#!/bin/bash
# state-lock-lib.sh — общий замок для файлов состояния и правки под ним.
# en: shared mutual exclusion for state files, plus the read-modify-write helpers.
#
# ПРЕФИКСЫ: atomic_ drain_ lock_ with_ write_
# Объявление пространства имён (11 сентября 2026, D390). Функция этой библиотеки
# носит один из названных префиксов; имя с ведущим `_` считается внутренним и под
# правило не подпадает. Сверяет `hooks/lib-prefix-guard.sh` при записи файла.
# Список собран ИЗ ФАКТА, а не придуман: он фиксирует нынешнее состояние, чтобы
# разнобой не рос дальше — из 21 библиотеки с 3+ функциями лишь 10 держали 80%+
# имён под одним префиксом, а объявления не было ни у одной из 29.
#
# Результат: у файла состояния, который правят несколько ходов сразу, окно read→write
#            закрыто замком — из N одновременных правок в файле остаются все N
# Проверка результата: bash hooks/tests/test_state_lock.sh даёт 0
#
# Зачем (род H, замер 4 сентября 2026). Тринадцать хуков читали общий файл целиком,
# правили в памяти и клали обратно. Между чтением и записью писателей не сериализовало
# ничто, и последний побеждал: восемь одновременных границ хода в `completion-gate.sh`
# оставляли 4-7 записей из 8. Правок было тринадцать, потому что общего помощника не
# существовало — каждый писатель решал задачу сам. Здесь он один.
#
# ЗАМОК — КАТАЛОГ, а не файл. `mkdir` атомарен на всякой POSIX-ФС и есть везде; `flock`
# на macOS отсутствует, `set -C` (noclobber) в подоболочках ведёт себя по-разному.
# Имя — `<путь>.lock` рядом с самим файлом: тот же каталог, значит те же права и та же ФС.
#
# ЗАМОК НЕ ЖДЁТ ВЕЧНО. Хук стоит на пути каждого вызова инструмента: зависший замок
# остановил бы сессию. После CLAUDSOUL_LOCK_TRIES проб (по умолчанию 100 × 20 мс = 2 с)
# работа продолжается БЕЗ замка — то есть ровно так, как она шла до этой библиотеки.
# Чужой замок старше CLAUDSOUL_LOCK_STALE_S (30 с) считается брошенным упавшим ходом
# и срывается: без этого один убитый хук запирал бы файл навсегда.
#
# Питоновская половина того же протокола (то же имя `<путь>.lock`, тот же `mkdir`) —
# в `hooks/lib/injection-log-rotate.py`: ротатор журнала подач живёт в питоне, а его
# писатель-аппендер в оболочке, и замок обязан быть у них общим.

PORTABLE_LIB_SL="${PORTABLE_LIB_SL:-$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" 2>/dev/null && pwd)/portable-lib.sh}"
[ -f "$PORTABLE_LIB_SL" ] || PORTABLE_LIB_SL="$HOME/.claude/hooks/portable-lib.sh"
# shellcheck source=/dev/null
if [ -f "$PORTABLE_LIB_SL" ]; then . "$PORTABLE_LIB_SL"; fi

# Взятые нами замки: `lock_release` снимает только свой. Иначе ход, не получивший замок
# по таймауту, сорвал бы чужой на выходе — и окно стало бы шире, чем без замка вовсе.
_SL_HELD=" "

# lock_acquire <путь> → 0 замок взят, 1 не взят (вызывающий продолжает без него)
#
# Ни одна ветвь не заканчивается «голым» ложным условием: три хука-потребителя стоят
# под `set -e`, и такая ветвь уронила бы весь хук вместо того, чтобы вернуть 1.
lock_acquire() {
    local target="${1:-}" i=0 d age now
    [ -n "$target" ] || return 1
    d="${target}.lock"
    while ! mkdir "$d" 2>/dev/null; do
        # Брошенный замок: владелец умер, каталог остался.
        now=$(date +%s 2>/dev/null || echo 0)
        age=$(file_mtime "$d" 2>/dev/null || echo 0)
        case "${age:-}" in ''|*[!0-9]*) age=0 ;; esac
        if [ "$age" -gt 0 ] && [ $((now - age)) -gt "${CLAUDSOUL_LOCK_STALE_S:-30}" ]; then
            if rmdir "$d" 2>/dev/null; then continue; fi
        fi
        i=$((i + 1))
        if [ "$i" -ge "${CLAUDSOUL_LOCK_TRIES:-100}" ]; then return 1; fi
        sleep "${CLAUDSOUL_LOCK_NAP:-0.02}" 2>/dev/null || sleep 1
    done
    _SL_HELD="${_SL_HELD}${target} "
    return 0
}

# lock_release <путь> — снять СВОЙ замок; чужой не трогается.
lock_release() {
    local target="${1:-}"
    [ -n "$target" ] || return 0
    case "$_SL_HELD" in
        *" $target "*) ;;
        *) return 0 ;;
    esac
    _SL_HELD="${_SL_HELD/ $target / }"
    rmdir "${target}.lock" 2>/dev/null || true
    return 0
}

# with_lock <путь> <команда...> — выполнить команду, держа замок на файле.
# Код возврата — команды, а не замка: не взятый замок работу не отменяет.
with_lock() {
    local target="${1:-}" rc=0
    shift || return 0
    lock_acquire "$target" || true
    "$@" || rc=$?
    lock_release "$target"
    return "$rc"
}

# atomic_filter <файл> <фильтр...> — заменить файл выводом фильтра, под замком.
# Файл подаётся фильтру на stdin (jq/awk/sed без аргумента-файла читают именно его).
# Промежуточный файл — рядом с целью, поэтому `mv` здесь переименование, а не копия.
# Ненулевой код фильтра оставляет файл нетронутым.
atomic_filter() {
    local target="${1:-}" tmp rc=0
    shift || return 1
    [ -n "$target" ] && [ -f "$target" ] || return 1
    tmp="${target}.tmp.$$"
    lock_acquire "$target" || true
    if "$@" <"$target" >"$tmp" 2>/dev/null; then
        mv "$tmp" "$target" 2>/dev/null || rc=1
    else
        rc=1
        rm -f "$tmp" 2>/dev/null
    fi
    lock_release "$target"
    return "$rc"
}

# write_if_changed <файл> <значение> → 0 записано, 1 значение уже было тем же.
# Сравнение и запись — под одним замком: два хода одного сеанса (инструменты идут
# параллельно) иначе оба видят старое значение и оба считают, что изменили они.
write_if_changed() {
    local target="${1:-}" value="${2:-}" cur="" rc=1
    [ -n "$target" ] || return 1
    lock_acquire "$target" || true
    if [ -f "$target" ]; then cur=$(cat "$target" 2>/dev/null || true); fi
    if [ "$cur" != "$value" ]; then
        # Решение «изменилось» отдаётся по РАЗНИЦЕ значений, а не по успеху записи:
        # хук печатает по нему сообщение, и непишущийся каталог состояния не должен
        # молча отменять сообщение — до правки оно печаталось независимо от записи.
        printf '%s' "$value" >"$target" 2>/dev/null || true
        rc=0
    fi
    lock_release "$target"
    return "$rc"
}

# drain_file <файл> — напечатать содержимое и опустошить файл одним движением.
# Переименование, а не `cat` + обрезка: писатель, открывший путь ПОСЛЕ него, заводит
# свежий файл и не теряется вовсе — обрезка же съедает всё, что дописано между чтением
# и ею. Пустой вывод и код 0, если файла нет.
drain_file() {
    local target="${1:-}" tmp
    [ -n "$target" ] || return 0
    [ -s "$target" ] || return 0
    tmp="${target}.drain.$$"
    lock_acquire "$target" || true
    mv "$target" "$tmp" 2>/dev/null || tmp=""
    lock_release "$target"
    [ -n "$tmp" ] || return 0
    cat "$tmp" 2>/dev/null
    rm -f "$tmp" 2>/dev/null
    return 0
}
