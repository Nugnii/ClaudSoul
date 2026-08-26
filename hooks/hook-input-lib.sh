#!/usr/bin/env bash
# hook-input-lib.sh — единый источник разбора ввода UserPromptSubmit-хуков.
#
# Назначение: один авторитетный список того, какие turn'ы НЕ являются речью
# собеседника (системные/инструментальные — task-notification, эхо slash-команды,
# tool-result). Хуки детекции языковых маркеров (reformulation-tracker,
# itr-event-detector) должны скопить детекцию к словам юзера: маркер коррекции
# («не совсем» и пр.) в теле tool_result — НЕ коррекция пользователя
# (pattern-guard-scope-blindness; case-2026-06-21 «детектор скан не той области»).
#
# Единый источник, а не копия в каждом хуке: список тегов эволюционирует
# (появится новый тип системного turn — обе детекции узнают из одного места),
# дрейф двух копий = ровно тот класс бага (principle-single-source-of-truth).

# is_non_user_turn "<prompt>"
#   return 0 — turn системный/инструментальный (не речь юзера) → детекцию пропустить
#   return 1 — обычная пользовательская реплика
is_non_user_turn() {
    case "$1" in
        *"<task-notification"*|*"<local-command-stdout"*|*"<command-name>"*|*"<bash-stdout"*|*"<tool-use-error"*)
            return 0 ;;
        *)
            return 1 ;;
    esac
}
