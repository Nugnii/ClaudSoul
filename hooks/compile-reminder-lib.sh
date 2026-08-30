#!/usr/bin/env bash
# compile-reminder-lib.sh — v1.0.0 (Фаза 3 конвейера L1→L2): мягкое напоминание
# запустить /compile, когда накопилось ≥ порога сессий сырья с последней
# консолидации. Бесплатно (без headless-прогонов) и в духе L6-гейта: нудж
# раз в сессию, только при пересечении порога; запуск — решение пользователя.
#
# Контракт:
#   compile_reminder_check <session_id>   → echo текст нуджа (или пусто), return 0
#   compile_reminder_reset                 → снимает маркеры (совместимость, см. ниже)
#
# Состояние (`STATE_DIR`, по умолчанию $HOME/.claude/hooks/state):
#   compile-counted-<sid>     — маркер: эта сессия учтена (счёт раз/сессию)
#   compile-reminded-<sid>    — маркер: в этой сессии уже напомнили (нудж раз/сессию)
#
# Порог: COMPILE_REMINDER_THRESHOLD (по умолчанию 5).
#
# --- Почему счётчика больше нет (D40, 2026-07-31) --------------------------------
#
# Было два независимых дефекта, и чинить их порознь бесполезно.
#
# ПЕРВЫЙ. `state_dir` был жёстко прописан как `$HOME/...` в обеих функциях, мимо
# `STATE_DIR`. Поэтому ЛЮБОЙ тест, поднимающий свой каталог состояния, всё равно
# инкрементировал живой счётчик. Замер на момент починки: `compile-pending` = 140 при
# ПЯТИ настоящих сессиях (маркеры UUID-вида) — завышение в 28 раз. Нудж сообщал
# «накопилось 140 сессий сырья», и число не значило ничего.
#
# ВТОРОЙ. Обнулить счётчик мог только человек, вспомнивший чекбокс: `skills/compile/
# SKILL.md:63,85` предписывает вызвать `compile_reminder_reset`, но НИ ОДНА строка кода
# его не вызывает. На прогоне 2026-07-28T23:00 сброс был пропущен — маркеры того же
# вечера остались живы. Это уровень 1 embedded-ness по `principle-knowledge-in-the-world`:
# правило текстом там, где нужен механизм.
#
# Починка убирает саму возможность обоих: отдельного счётчика больше не существует.
# Число выводится из `last_compiled` в `_compile-state.json` — считаются маркеры сессий,
# созданные ПОЗЖЕ последней консолидации. Тогда сброс происходит сам в тот момент, когда
# `/compile` записывает `last_compiled`, и вспоминать про него некому и не нужно.

# Переносимые примитивы — из единой библиотеки, а не переписанные здесь. Сначала рядом с
# собой, потом в установленном каталоге: хук, запущенный из репозитория на машине без
# установки, иначе молча остался бы без `iso_epoch`/`file_mtime` (класс D35).
for _cr_lib in "$(cd "$(dirname "${BASH_SOURCE[0]}")" 2>/dev/null && pwd)/portable-lib.sh" \
               "$HOME/.claude/hooks/portable-lib.sh"; do
    if [ -f "$_cr_lib" ]; then
        # shellcheck source=/dev/null
        . "$_cr_lib"
        break
    fi
done
unset _cr_lib

_compile_state_dir() { printf '%s' "${STATE_DIR:-$HOME/.claude/hooks/state}"; }

# Эпоха последней консолидации; 0 — если файла нет или разобрать не удалось.
# При 0 считаются все маркеры, то есть нудж скорее прозвучит, чем промолчит: пропущенная
# консолидация дешевле молчания о накопленном сырье.
_compile_last_epoch() {
    local f="${COMPILE_STATE_FILE:-$HOME/.claude/global-lessons/_compile-state.json}"
    [ -f "$f" ] || { echo 0; return; }
    local ts
    ts=$(sed -n 's/.*"last_compiled"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' "$f" 2>/dev/null | head -1)
    [ -n "$ts" ] || { echo 0; return; }
    if command -v iso_epoch >/dev/null 2>&1; then
        iso_epoch "$ts"
    else
        echo 0   # библиотеки нет — считаем все маркеры, см. пояснение выше
    fi
}

compile_reminder_check() {
    local sid="${1:-}"
    [ -z "$sid" ] && return 0

    local state_dir; state_dir=$(_compile_state_dir)
    local counted_file="$state_dir/compile-counted-${sid}"
    local reminded_file="$state_dir/compile-reminded-${sid}"
    local threshold="${COMPILE_REMINDER_THRESHOLD:-5}"
    mkdir -p "$state_dir" 2>/dev/null || true

    # Отметить эту сессию (Stop срабатывает много раз за сессию — маркер один)
    [ -f "$counted_file" ] || : > "$counted_file" 2>/dev/null || true

    # Сессии ПОСЛЕ последней консолидации. Отдельного счётчика нет: он расходился с
    # реальностью ровно потому, что жил своей жизнью и обнулялся только вручную.
    local since; since=$(_compile_last_epoch)
    local n=0 m
    for f in "$state_dir"/compile-counted-*; do
        [ -f "$f" ] || continue
        m=$(file_mtime "$f")
        [ "${m:-0}" -gt "${since:-0}" ] && n=$((n + 1))
    done

    # Уборка: маркеры старше COMPILE_MARKER_TTL_DAYS не влияют на счёт и только копятся.
    find "$state_dir" -maxdepth 1 -name 'compile-counted-*' \
        -mtime "+${COMPILE_MARKER_TTL_DAYS:-60}" -delete 2>/dev/null || true

    # Уже напоминали в этой сессии — молчим
    [ -f "$reminded_file" ] && return 0

    if [ "$n" -ge "$threshold" ]; then
        : > "$reminded_file" 2>/dev/null || true
        # Формулировка — поручение сказать, а не статус. Замер 2026-08-21: нудж приходил
        # в контекст 125 сессий и был озвучен собеседнику не более 8 раз (117 проглочены).
        # Канал исправен: таймштамп-канарейка в том же additionalContext доходит всегда —
        # у неё текст «начни ответ этим таймштампом». Единственная владелец-видимая
        # поверхность в расширении VS Code — диалог, то есть текст агента; статус,
        # адресованный агенту, до собеседника не доходит (principle-knowledge-in-the-world).
        printf '🧱 СКАЖИ собеседнику одной строкой: накопилось %s сессий сырья с последней консолидации — пора /compile (кандидаты знаний в _drafts). ' "$n"
    fi
    return 0
}

# Оставлен для совместимости: `skills/compile/SKILL.md` его зовёт, и снять маркеры руками
# иногда нужно. Но счёт от него больше НЕ ЗАВИСИТ — пропущенный вызов ничего не ломает.
compile_reminder_reset() {
    local state_dir; state_dir=$(_compile_state_dir)
    mkdir -p "$state_dir" 2>/dev/null || true
    rm -f "$state_dir"/compile-reminded-* "$state_dir"/compile-counted-* "$state_dir"/compile-pending 2>/dev/null || true
    return 0
}

# When invoked directly: subcommand dispatch
if [ "${BASH_SOURCE[0]}" = "${0:-}" ]; then
    case "${1:-}" in
        check) compile_reminder_check "${2:-}" ;;
        reset) compile_reminder_reset ;;
        *) echo "usage: $0 {check <sid>|reset}" >&2; exit 2 ;;
    esac
fi
