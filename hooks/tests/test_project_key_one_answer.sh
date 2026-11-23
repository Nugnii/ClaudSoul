#!/usr/bin/env bash
# СУДИТ: hooks/root-cause-lib.sh
# test_project_key_one_answer.sh — у «проекта события» ОДИН ответ, кто бы ни спросил.
#
# Результат: ключ, под которым событие записано, совпадает с ключом, под которым его ищут.
# Проверка результата: bash hooks/tests/test_project_key_one_answer.sh даёт 0
#
# Повод, 10 сентября 2026, прожарка. `rc_project_of` отвечала по-разному в зависимости от
# того, загрузил ли ВЫЗЫВАЮЩИЙ библиотеку путей: с `find_project_root` подъём идёт к
# ближайшему `.git` ИЛИ `CLAUDE.md`, без неё — только к git-корню. Способов получалось три:
#   · `five-whys-gate.sh:93`      — payload.cwd + find_project_root (paths-lib загружена);
#   · `hooks/revert-signal.sh:72` — каталог ПРОЦЕССА + find_project_root (payload не читался);
#   · `scripts/ci-status.sh:86`, `scripts/backlog-recheck.sh:209` — каталог процесса + git.
# В монорепо с каталожным CLAUDE.md писатель кладёт событие под один ключ, читатель ищет под
# другим, и сигнал `event` умирает МОЛЧА — без ошибки, без пустого вывода, без следа.
#
# Почему тест отдельный от `test_event_project_scope`. Тот передаёт `RC_EVENT_PROJECT`
# явно (`/proj/A`), а МИР его не передаёт никогда: форма входа взята не у мира, и мутация
# «функция всегда возвращает константу» проходила все 411 тестов набора зелёной
# (`pattern-fixture-form-not-taken-from-the-world`). Здесь каталоги настоящие, а писатель
# зовётся так, как зовут его продюсеры — без переменной.
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
LIB="$ROOT/hooks/root-cause-lib.sh"
[ -f "$LIB" ] || { echo "FAIL: нет $LIB"; exit 1; }

TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
PASS=0; FAIL=0
ck() { if [ "$2" = "$3" ]; then PASS=$((PASS+1)); printf '  ✅ %s\n' "$1"
       else FAIL=$((FAIL+1)); printf '  ❌ %s\n     ожидалось: [%s]\n     получено:  [%s]\n' "$1" "$2" "$3"; fi; }
ne() { if [ "$2" != "$3" ]; then PASS=$((PASS+1)); printf '  ✅ %s\n' "$1"
       else FAIL=$((FAIL+1)); printf '  ❌ %s — оба ответа [%s], функция не различает проекты\n' "$1" "$2"; fi; }

# --- два настоящих проекта и монорепо с каталожным договором ---
A="$TMP/projA"; B="$TMP/projB"; M="$TMP/mono"
for d in "$A" "$B" "$M"; do mkdir -p "$d" && { git -C "$d" init -q 2>/dev/null || { echo "подготовка мира не удалась: hooks/tests/test_project_key_one_answer.sh:$LINENO" >&2; exit 1; }; }; done
mkdir -p "$M/apps/web" && printf '# web\n' > "$M/apps/web/CLAUDE.md"

# Ответ функции в двух режимах: с предзагруженной paths-lib и БЕЗ неё.
ask_with_paths() {  # $1 — каталог
    bash -c '. "$1/hooks/paths-lib.sh" 2>/dev/null; . "$1/hooks/root-cause-lib.sh"; rc_project_of "$2"' _ "$ROOT" "$1" || { echo "подготовка мира не удалась: hooks/tests/test_project_key_one_answer.sh:$LINENO" >&2; exit 1; }
}
ask_bare() {
    bash -c '. "$1/hooks/root-cause-lib.sh"; rc_project_of "$2"' _ "$ROOT" "$1"
}

echo "── функция различает проекты (ловит подмену константой) ──"
ne "два разных проекта — разные ответы" "$(ask_bare "$A")" "$(ask_bare "$B")"

echo "── ответ не зависит от того, кто спросил ──"
ck "обычный проект"        "$(ask_with_paths "$A")"          "$(ask_bare "$A")"
ck "монорепо, подкаталог с CLAUDE.md" "$(ask_with_paths "$M/apps/web")" "$(ask_bare "$M/apps/web")"

echo "── сквозной путь: форма вызова взята у продюсеров ──"
# Писатель НЕ передаёт RC_EVENT_PROJECT — ровно как ci-status.sh и backlog-recheck.sh.
#
# `env -u`: `rc_env_is_real` намеренно глушит запись, когда выставлены CLAUDSOUL_REPO,
# CLAUDE_HOME или BACKLOG_FILE, — предохранитель «не писать боевое состояние из теста».
# Набор выставляет CLAUDSOUL_REPO, и без снятия эта нога краснела ТОЛЬКО внутри набора,
# оставаясь зелёной одиночным прогоном (поймано полным прогоном 10 сентября 2026).
# Снятие законно: писать тест будет в свой `$TMP/state`, который сам и передаёт, боевых
# путей здесь нет ни одного. Ниже — положительный контроль: если запись всё же не
# состоялась, нога скажет об этом, а не спишет пустоту на «чужой проект не видит».
( cd "$A" && env -u CLAUDSOUL_REPO -u CLAUDE_HOME -u BACKLOG_FILE \
    bash -c '. "$1/hooks/root-cause-lib.sh"; rc_note_event "$2" "ci-red" "прогон 1 для abc: failure"' \
    _ "$ROOT" "$TMP/state" ) >/dev/null 2>&1
if [ ! -s "$TMP/state/pending-events.jsonl" ]; then
    FAIL=$((FAIL+1)); echo "  ❌ ПРИБОР СЛОМАН: писатель не создал журнал — сквозные ноги ничего не значат"
fi
# shellcheck source=/dev/null
. "$ROOT/hooks/paths-lib.sh" 2>/dev/null || true
. "$LIB"
ck "читатель своего проекта видит событие" \
   "ci-red: прогон 1 для abc: failure" \
   "$(rc_open_events "$TMP/state" "$(rc_project_of "$A")")"
ck "читатель ЧУЖОГО проекта не видит" "" \
   "$(rc_open_events "$TMP/state" "$(rc_project_of "$B")")"

echo
echo "Прошло: $PASS, провалено: $FAIL"
exit $(( FAIL != 0 ))
