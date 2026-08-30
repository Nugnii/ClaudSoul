#!/usr/bin/env bash
# shared-language-lib.sh — мост L3↔L7: кандидаты в shared vocabulary из речи собеседника.
# en: bridge L3<->L7 — detect recurring interlocutor shorthand not yet in the vocabulary.
#
# Проект моста (пункт 2): на Stop выявлять shorthand — устойчивые термины собеседника,
# которых ещё нет в словаре проекта. Выявлять, НЕ записывать: словарь курируется
# осмысленно, детектор только предлагает (уровень 2, инжект-напоминание).
#
# Сигнал синтаксический, не частотно-языковой — урок v1.13.3 (придуманный словарь:
# 9 срабатываний за 214 сессий, ноль полезных). Кандидат — токен, который:
#   - состоит из латиницы/цифр/дефиса/подчёркивания/слэша (идентификаторы, команды,
#     составные вроде blocker-tier, /compile, co-cognition);
#   - длиной ≥ 4, содержит букву, не URL-обломок;
#   - употреблён СОБЕСЕДНИКОМ ≥ N раз за сессию (default 3, проект моста);
#   - отсутствует в shared-vocabulary.md проекта.
# ponytail: кириллические термины («растяжка», «гейт») этот уровень не ловит —
# граница слова в кириллице требует pad_words-подхода; расширять, когда данные
# покажут, что латинских кандидатов мало.
#
# Служебные «user»-сообщения (task-notification, загрузка скиллов, команды) — не речь
# собеседника и отбрасываются до токенизации, иначе детектор тонет в их латинице.

# shlang_vocab_path <cwd> — путь словаря проекта в памяти.
# Кодировка каталога памяти: '/' и пробел → '-' (как ~/.claude/projects/).
shlang_vocab_path() {
    local cwd="${1:-}"
    [ -n "$cwd" ] || return 0
    printf '%s/.claude/projects/%s/memory/shared-vocabulary.md\n' \
        "$HOME" "$(printf '%s' "$cwd" | tr '/ ' '--')"
}

# shlang_user_text <transcript.jsonl> — только живая речь собеседника, по строке
# на сообщение (внутренние переводы строк схлопнуты в пробел).
shlang_user_text() {
    local t="${1:-}"
    [ -f "$t" ] || return 0
    command -v jq >/dev/null 2>&1 || return 0
    jq -rR '
        fromjson? // empty
        | select((.message.role // .role // "") == "user")
        | (.message.content // .content // [])
        | if type == "array" then (map(select(.type == "text") | .text) | join(" "))
          elif type == "string" then .
          else "" end
        | gsub("[\\n\\t]"; " ")
        | select(length > 0)
    ' "$t" 2>/dev/null \
    | grep -v -e '<task-notification>' -e '<system-reminder>' -e '<command-name>' \
              -e '<local-command' -e 'Base directory for this skill' \
              -e '<ide_opened_file>' -e 'This session is being continued' || true
}

# shlang_candidates <transcript.jsonl> <vocab_file> [min_count] — до 5 кандидатов,
# строки вида «token ×N», по убыванию N. Пустой вывод = кандидатов нет.
shlang_candidates() {
    local t="${1:-}" vocab="${2:-}" min="${3:-3}"
    [ -f "$t" ] || return 0
    local vocab_lc=""
    if [ -n "$vocab" ] && [ -f "$vocab" ]; then
        vocab_lc=$(tr 'A-Z' 'a-z' < "$vocab")
    fi
    shlang_user_text "$t" \
    | sed 's|https\{0,1\}://[^ ]*| |g' \
    | tr -c 'A-Za-z0-9_/\-' ' ' \
    | tr ' ' '\n' \
    | tr 'A-Z' 'a-z' \
    | awk 'length($0) >= 4 && $0 ~ /[a-z]/ && $0 !~ /^[0-9\/_-]+$/' \
    | sort | uniq -c | sort -rn \
    | while read -r n tok; do
        [ "$n" -ge "$min" ] 2>/dev/null || break
        # расширения файлов — не термины (ограниченный список по правилу, не по вкусу:
        # это суффиксы путей, а не слова речи)
        case "$tok" in *.md|*.sh|*.py|*.json|*.txt|md|json|txt) continue ;; esac
        if [ -n "$vocab_lc" ] && grep -Fq -- "$tok" <<< "$vocab_lc"; then
            continue
        fi
        printf '%s ×%s\n' "$tok" "$n"
    done | head -5
}
