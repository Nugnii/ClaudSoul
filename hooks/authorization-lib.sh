#!/usr/bin/env bash
# authorization-lib.sh — ADR-010 Ф1: авторизация как состояние задачи.
# en: ADR-010 phase 1 — standing task authorization state, not a prior-turn property.
#
# Проблема, которую закрывает: itr-event-detector проверял авторизацию по ОДНОЙ
# предыдущей реплике. В длинной авторизованной работе предыдущей «user»-строкой
# оказывается task-notification, маркер «делай» лежит выше — и правки писались
# как proactive (62% «превышений» бюджета, разбор в ADR-010).
#
# Модель: маркер explicit/continuation в реальной реплике собеседника ВЗВОДИТ
# состояние; гасит его только следующая реальная реплика, не являющаяся
# поручением/продолжением (вопрос, поправка, «стой»). Синтетические user-строки
# до писателя не доходят по построению: writer вызывается из UserPromptSubmit
# (событие только на настоящие реплики) и стоит ЗА guard'ом is_non_user_turn —
# двойная гарантия сильнее любого фильтра по содержимому.
#
# Маркеры — единый источник: перенесены из itr-event-detector (инлайн-массивы
# там удалены, детектор source-ит эту библиотеку).

# portable-lib: to_lower обязан сворачивать кириллицу («Делай» → «делай»).
_AUTH_PORTABLE="${PORTABLE_LIB:-$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" 2>/dev/null && pwd)/portable-lib.sh}"
if ! command -v to_lower >/dev/null 2>&1; then
    if [ -f "$_AUTH_PORTABLE" ]; then . "$_AUTH_PORTABLE";
    elif [ -f "$HOME/.claude/hooks/portable-lib.sh" ]; then . "$HOME/.claude/hooks/portable-lib.sh";
    else to_lower() { printf '%s' "${1:-}" | tr '[:upper:]' '[:lower:]'; }
    fi
fi

# Поручение — подстрока в любом месте реплики.
AUTH_EXPLICIT_MARKERS=(
    # Russian imperatives — bare verb forms, not infinitives.
    "сделай" "делай" "измени" "запусти" "напиши" "добавь" "создай"
    "удали" "поправь" "исправь" "обнови" "почини" "переделай"
    "перепиши" "убери" "замени" "проверь" "запушь" "пушни"
    "закоммить" "коммитни" "откати" "сбрось" "собери"
    "скомпилируй" "установи" "разверни" "отрефактори" "форматни"
    "реализуй" "внеси" "примени" "перенеси" "упрости" "калибруй"
    # Russian compound requests
    "нужно сделать" "нужно изменить" "нужно исправить"
    "нужно починить" "нужно добавить" "нужно удалить"
    "давай сделаем" "давай изменим" "давай создадим"
    "давай добавим" "давай уберём" "давай уберем"
    # English imperatives — trailing space avoids "doing"/"fixed".
    "do " "make " "create " "edit " "modify " "change " "fix "
    "run " "execute " "add " "delete " "remove " "write " "update "
    "patch " "deploy " "commit " "push " "implement " "build "
    "refactor " "rewrite " "install " "compile " "apply "
    # English compound / polite requests
    "please " "can you " "could you " "would you "
    "need to fix" "need to change" "need to add" "let's "
)

# Продолжение — строго В НАЧАЛЕ реплики (короткие токены вроде «дальше» в середине
# длинного сообщения — не сигнал).
# Стоп-слова: реплика, гасящая авторизацию явно. Перечень здесь уместен — это КОРОТКИЙ
# закрытый класс («стой», «подожди», «отмена»), в отличие от бесконечного класса поручений.
AUTH_STOP_MARKERS=(
    "стоп" "стой" "подожди" "погоди" "отмена" "отставить" "не надо" "не делай"
    "прекрати" "хватит" "останови" "wait" "stop" "hold on" "cancel" "abort"
    # Поправка — не поручение: собеседник исправляет сделанное, а не заказывает новое.
    # Поймано собственным тестом при первом же прогоне правила D207: реплика «не так — я
    # имел в виду другое» была признана поручением и взвела авторизацию на следующий ход.
    # НАЗВАННЫЙ ПРЕДЕЛ: ловятся формы С ОТРИЦАНИЕМ; поправка без него («имел в виду
    # другое», «наоборот») правилом не отсекается и будет принята за содержательную реплику.
    # Условие снятия: предел уйдёт, когда источником станет `user-correction-guard` — он уже
    # различает поправку тремя сигналами, включая позиционный, и его вердикт точнее слов.
    "не так" "не то" "неверно" "не туда" "не этого" "я имел в виду" "я имела в виду"
)

AUTH_CONTINUATION_MARKERS=(
    "дальше" "продолжай" "продолжаем" "продолжим" "продолжи"
    "теперь" "далее" "следующий" "следующее" "следующая"
    "и потом" "и затем" "после этого" "поехали" "погнали"
    "да" "ок" "ok" "окей" "хорошо" "согласен" "согласна" "готово"
    "next" "continue" "go on" "keep going" "and then" "after that"
    "now " "yes" "go ahead" "proceed" "sure" "do it" "lgtm" "+1"
)

# auth_state_path <session_id> → путь состояния (тот же STATE_DIR, что у itr-*).
auth_state_path() {
    printf '%s/authorization-%s.json\n' \
        "${ITR_STATE_DIR:-${STATE_DIR:-$HOME/.claude/hooks/state}}" "${1:-unknown}"
}

# auth_classify <реплика> → "explicit:<маркер>" | "continuation:<маркер>" | "" .
auth_classify() {
    local lower trimmed marker
    lower=$(to_lower "${1:-}")
    trimmed=$(printf '%s' "$lower" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')
    for marker in "${AUTH_EXPLICIT_MARKERS[@]}"; do
        if grep -qF -- "$marker" <<< "$lower"; then
            printf 'explicit:%s\n' "$marker"
            return 0
        fi
    done
    for marker in "${AUTH_CONTINUATION_MARKERS[@]}"; do
        case "$trimmed" in
            "$marker"|"$marker "*|"$marker,"*|"$marker."*|"$marker!"*|"$marker?"*)
                printf 'continuation:%s\n' "$marker"
                return 0
                ;;
        esac
    done

    # ── Третья ветвь: ПРАВИЛО вместо перечня форм (D207) ──────────────────────
    # Замер по корпусу 29 августа 2026: из 1711 реплик собеседника перечни признавали
    # поручением 340 (19%), и 504 раза агент правил файлы при формальном «авторизации
    # нет». Среди пропущенных — прямые поручения: «Нужно интегрировать в систему»,
    # «Ставь debug-лог», «А теперь разгребаем этот бэклог». Русский даёт поручение
    # бесконечным числом форм: первое лицо мн. ч., безличное, назывное, — и словарь
    # повелительных глаголов стареет молча (pattern-subject-checked-by-enumeration).
    #
    # ПРАВИЛО. Авторизация — состояние ЗАДАЧИ (ADR-010), а не свойство глагола. Реплика
    # авторизует работу, если она НЕ вопрос и НЕ короткая реакция: содержательная реплика
    # в идущей работе есть поручение по умолчанию. Гасят авторизацию ровно два случая —
    # вопрос (собеседник ждёт ответа, а не правки) и стоп-слово.
    #
    # КОНТРПРИМЕРЫ, оба проверяются тестом: реплика с «?» авторизацией не является, даже
    # длинная; короткая реакция («ок», «ага», «иии») — тоже, для неё есть перечень
    # продолжений выше, и он остаётся единственным способом её распознать.
    case "$trimmed" in
        *"?"*) return 1 ;;
    esac
    for marker in "${AUTH_STOP_MARKERS[@]}"; do
        case "$trimmed" in
            *"$marker"*) return 1 ;;
        esac
    done
    # Длина в СИМВОЛАХ, не в байтах: кириллица иначе считается вдвое и порог смещается.
    _auth_len=$(printf '%s' "$trimmed" | awk '{print length($0)}')
    case "${_auth_len:-0}" in ''|*[!0-9]*) _auth_len=0 ;; esac
    if [ "$_auth_len" -ge "${AUTH_TASK_MIN_CHARS:-12}" ]; then
        printf 'task:content\n'
        return 0
    fi
    return 1
}

# auth_update <session_id> <реплика> — переклассификация на КАЖДОЙ реальной
# реплике: поручение/продолжение → active, всё прочее → гашение. Атомарная запись.
auth_update() {
    local sid="${1:-}" prompt="${2:-}"
    [ -n "$sid" ] || return 0
    command -v jq >/dev/null 2>&1 || return 0
    local path marker active ts tmp
    path=$(auth_state_path "$sid")
    mkdir -p "$(dirname "$path")" 2>/dev/null || return 0
    if marker=$(auth_classify "$prompt"); then active=true; else active=false; marker=""; fi
    ts=$(date -u +%Y-%m-%dT%H:%M:%SZ)
    tmp="$path.tmp.$$"
    jq -cn --argjson active "$active" --arg marker "$marker" --arg ts "$ts" \
        '{active: $active, marker: $marker, updated_at: $ts}' > "$tmp" 2>/dev/null \
        && mv "$tmp" "$path" || rm -f "$tmp"
    return 0
}

# auth_is_active <session_id> — код 0 + маркер на stdout, если авторизация действует.
auth_is_active() {
    local path
    path=$(auth_state_path "${1:-}")
    [ -f "$path" ] || return 1
    local marker
    marker=$(jq -r 'select(.active == true) | .marker' "$path" 2>/dev/null)
    [ -n "$marker" ] || return 1
    printf '%s\n' "$marker"
    return 0
}
