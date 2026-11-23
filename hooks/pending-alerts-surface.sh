#!/usr/bin/env bash
# pending-alerts-surface.sh — UserPromptSubmit: поднимает отложенное видимым каналом.
# en: UserPromptSubmit: surfaces deferred alerts through a channel the UI reliably shows.
#
# Зачем: Stop→systemMessage не отображается в части UI (VS Code) — алерты
# session-collector (ошибки→/learn, висячие записи опровержения, долг тишины, нудж
# /compile) уходили в пустоту. Канал UserPromptSubmit→additionalContext виден
# надёжно (как knowledge-activator, intrusiveness). См. case-2026-06-14.
#
# Поднимаются четыре источника:
#   1) `pending-alerts.txt` — общая очередь: только сказанное обо всей системе (межсессионная);
#   2) `startup-signals-<sid>.txt` — сигналы старта текущей сессии (посессионные);
#   3) `stop-signals-<sid>.txt` — сказанное о сессии (`session_alert`): свой файл и файлы
#      закрытых сессий того же проекта (D1047);
#   4) `project-signals-<ключ>.txt` — сказанное о проекте (`project_alert`, D1304): каналы всех корней вверх от каталога.
#
# --- Почему сигналы старта попали сюда (D49, 2026-07-31) --------------------------
#
# У них был ЕДИНСТВЕННЫЙ канал доставки: `knowledge-activator.sh` на первом
# PreToolUse[Bash|Edit|Write]. Сессия, в которой не случилось ни одного такого вызова,
# сигналов не видела никогда, а файл оставался лежать навсегда. Замер на момент починки:
# **99 файлов, все непустые**, старейший от 24 апреля. Внутри — «в корне проекта нет
# CLAUDE.md», «база знаний обновилась», заявка на эскалацию, обратный дрейф установки.
#
# Второй канал именно здесь, а не в новом хуке: этот уже про «показать отложенное»,
# уже на UserPromptSubmit и уже гасит показанное. Сессия без единого инструмента, но с
# репликой собеседника, теперь сигналы получит. Кто первым дошёл — тот и показал:
# оба потребителя удаляют файл после чтения.
#
# Контракт:
#   stdin  = UserPromptSubmit payload
#   stdout = jq hookSpecificOutput.additionalContext (или пусто)
# Показ ровно один раз: источник очищается сразу после чтения.

set -uo pipefail

INPUT=$(cat 2>/dev/null || true)
: "${INPUT:=}"

STATE_DIR="${CLAUDSOUL_STATE_DIR:-${STATE_DIR:-$HOME/.claude/hooks/state}}"
QUEUE="$STATE_DIR/pending-alerts.txt"
# Общий замок и правка под ним (род H): очередь дописывает session-collector чужой сессии.
STATE_LOCK_LIB="${STATE_LOCK_LIB:-$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" 2>/dev/null && pwd)/state-lock-lib.sh}"
[ -f "$STATE_LOCK_LIB" ] || STATE_LOCK_LIB="$HOME/.claude/hooks/state-lock-lib.sh"
# shellcheck source=/dev/null
if [ -f "$STATE_LOCK_LIB" ]; then . "$STATE_LOCK_LIB"; fi

command -v jq >/dev/null 2>&1 || exit 0

SID=$(printf '%s' "$INPUT" | jq -r '.session_id // ""' 2>/dev/null || true)
# Библиотеки — ДО забора файлов (D1052): без HOME они умирают под `set -u`, и хук, уже забравший сигналы
# старта и очередь, терял их. Упасть здесь — значит ничего не тронуть: всё дойдёт следующей репликой.
_pas_dir="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" 2>/dev/null && pwd)"
for _pas_lib in paths-lib.sh session-registry-lib.sh; do
    for _pas_f in "$_pas_dir/$_pas_lib" "${HOME:-}/.claude/hooks/$_pas_lib"; do
        # shellcheck source=/dev/null
        [ -f "$_pas_f" ] && { . "$_pas_f" >/dev/null 2>&1; break; }
    done
done
SIGNALS=""
if [ -n "$SID" ]; then
    SIGNALS_FILE="$STATE_DIR/startup-signals-${SID}.txt"
    SIGNALS=$(drain_file "$SIGNALS_FILE" 2>/dev/null || true)
fi

# Забор очереди — переименованием, а не «прочитать и обрезать»: строка, дописанная
# соседней сессией между чтением и обрезкой, при обрезке пропадала (род H).
ALERTS=$(drain_file "$QUEUE" 2>/dev/null || true)

# Напоминания прошлого хода (D1047) — `stop-signals-<sid>.txt` пишет сверщик исхода на Stop, рядом
# `.project` с корнем проекта. Свой файл отдаётся своей сессии; чужой — сессии того же проекта, когда
# его сессия кончилась: вкладку закрыли, /clear, новое окно — SessionEnd кладёт пометку `.ended` (D1049).
# Без пометки — только после суток молчания и если `sr_record_alive` (реестр сессий) не видит жизни:
# параллельной живой или молчащей открытой сессии чужое напоминание не показывается.
# Отдельный файл, а не `startup-signals`: тот обнуляет старт сессии, и compact стирал напоминание.
STOPS=""
if [ -n "$SID" ]; then
    STOPS=$(drain_file "$STATE_DIR/stop-signals-${SID}.txt" 2>/dev/null || true)
    # Своя реплика снимает и свою пометку конца (D1055): сессия, вернувшаяся через resume с тем же sid, иначе
    # числилась бы кончившейся, и её следующую находку забрала бы параллельная.
    rm -f "$STATE_DIR/stop-signals-${SID}.project" "$STATE_DIR/stop-signals-${SID}.ended" 2>/dev/null || true
fi
ORPHANS=""
PAYLOAD_CWD=$(printf '%s' "$INPUT" | jq -r '.cwd // ""' 2>/dev/null || true)
if [ -n "$PAYLOAD_CWD" ] && command -v sr_record_alive >/dev/null 2>&1; then
    _pas_proj=""
    command -v find_project_root >/dev/null 2>&1 && _pas_proj=$(find_project_root "$PAYLOAD_CWD")
    _pas_proj="${_pas_proj:-$PAYLOAD_CWD}"
    # Корень сравнивается и строкой, и физическим путём (D1052): `/tmp/x` и `/private/tmp/x`, путь через ссылку.
    _pas_projp=$(cd "$_pas_proj" 2>/dev/null && pwd -P) || _pas_projp="$_pas_proj"
    for _pas_pf in "$STATE_DIR"/stop-signals-*.project; do
        [ -f "$_pas_pf" ] || continue
        _pas_sid="${_pas_pf##*/stop-signals-}"; _pas_sid="${_pas_sid%.project}"
        [ "$_pas_sid" = "$SID" ] && continue
        _pas_pr=$(head -1 "$_pas_pf" 2>/dev/null)
        # Корень — только абсолютный путь (D1055): `cd ""` и `cd .` остаются в каталоге процесса хука.
        case "$_pas_pr" in /*) ;; *) continue ;; esac
        if [ "$_pas_pr" != "$_pas_proj" ]; then
            _pas_pr=$(cd "$_pas_pr" 2>/dev/null && pwd -P) || continue
            [ "$_pas_pr" = "$_pas_projp" ] || continue
        fi
        # Отдаётся только после КОНЦА сессии (D1049, корень R6): пометка `.ended` от SessionEnd либо сутки
        # молчания (сбой, конец без SessionEnd). Устаревшая метка живости концом не считается: открытая, но
        # молчащая вкладка через SR_LIVE_TTL_MIN минут для `sr_record_alive` уже не жива, а уборка реестра
        # её метку сносит.
        _pas_how="закрытой сессии"
        # Живость спрашивается только у сессии БЕЗ пометки конца (D1060): пометку снимают старт той же сессии
        # (resume, `session-start.sh`) и её реплика, а метку живости после конца освежает и чужой для неё писатель
        # (первый заход `knowledge-activator` со старым sid) — спрошенная первой, она задерживала напоминание
        # закрытой сессии на срок живости.
        # НАЗВАННЫЕ ПРЕДЕЛЫ (финальный скептик D1055): перевод строки в пути проекта рвёт `.project` (`head -1`) — файл
        # лежит до уборки; корень — `find_project_root`, и вложенный CLAUDE.md (`rules/`) делит проект надвое; реплика,
        # за которой сразу конец, отдаёт напоминание в несостоявшийся ход; Stop после SessionEnd пометки не кладёт —
        # передача через сутки; без jq или с битым JSON у `session-end.sh` нет sid, и пометки нет.
        # Двузначные по R6 (финальный скептик D1060, D1063): вернувшаяся через resume сессия, упавшая без реплики и без
        # второго SessionEnd, отдаётся через сутки молчания, а не через срок живости, — старт снял её пометку конца;
        # две вкладки на одном sid (копия через resume жива, старая закрылась после неё) — пометка старой вкладки при
        # свежей метке копии читается концом, и находки живой копии уходят параллельной. `CLAUDSOUL_STATE_DIR`,
        # отличный от `STATE_DIR`, глушит канал: писатель (`declared-problem-recorded.sh`) берёт только `STATE_DIR`;
        # в установке переменная не задана.
        if [ ! -e "$STATE_DIR/stop-signals-${_pas_sid}.ended" ]; then
            sr_record_alive "$_pas_sid" && continue
            [ -n "$(find "$STATE_DIR/stop-signals-${_pas_sid}.txt" -mmin +"${STOP_SIGNALS_ORPHAN_MIN:-1440}" 2>/dev/null)" ] || continue
            _pas_how="сессии, молчащей больше суток,"
        fi
        _pas_body=$(drain_file "$STATE_DIR/stop-signals-${_pas_sid}.txt" 2>/dev/null || true)
        rm -f "$_pas_pf" "$STATE_DIR/stop-signals-${_pas_sid}.ended" 2>/dev/null || true
        [ -n "$_pas_body" ] && ORPHANS="${ORPHANS:+$ORPHANS

}📌 Из ${_pas_how} ${_pas_sid:0:8} того же проекта (её итог вы уже не увидите — исход дайте здесь):
${_pas_body}"
    done
fi

# Сообщения о ПРОЕКТЕ (D1304) — `project-signals-<cksum физического корня>.txt` пишет `project_alert` (`paths-lib.sh`):
# архиватор долга, сверка архива после коммита, страж закрытия о главном бэклоге. Снимает ближайшая реплика любой сессии
# этого проекта, своей или параллельной: адресат — проект, а не сессия, чей сборщик это сделал. Прежде такие слова шли в
# общую очередь, и 42 из 156 показов «закрытые пункты проекта X» за 14 дней достались сессии другого проекта.
# Корни — ВСЕ вверх от каталога сессии, а не ближайший (скептик opus по 9310f120, H1): у ProjectA `web/` со своим CLAUDE.md,
# и сессия из `web` не получала слово о бэклоге корня (13 показов в 9 сессиях за 14 дней). Каталог сессии снимается
# всегда — писатель без признака корня кладёт ключом сам каталог.
PROJS=""
if [ -n "$PAYLOAD_CWD" ]; then
    _pas_d=$(cd "$PAYLOAD_CWD" 2>/dev/null && pwd -P) || _pas_d=""
    _pas_first=1
    while [ -n "$_pas_d" ]; do
        if [ -n "$_pas_first" ] || [ -e "$_pas_d/.git" ] || [ -f "$_pas_d/CLAUDE.md" ]; then
            _pas_one=$(drain_file "$STATE_DIR/project-signals-$(printf '%s' "$_pas_d" | cksum | awk '{print $1}').txt" \
                2>/dev/null || true)
            [ -n "$_pas_one" ] && PROJS="${PROJS:+$PROJS
}$_pas_one"
        fi
        _pas_first=""
        [ "$_pas_d" = / ] && break
        _pas_d="${_pas_d%/*}"; _pas_d="${_pas_d:-/}"
    done
fi
# ОДНА СТРОКА О ПРОЕКТЕ — ОДИН РАЗ (D1344, корень R1). Очередь проекта общая, а дроссель у её писателей — по сессии:
# каждая сессия проекта говорит «залежавшийся пункт ждёт очереди» сама, и одно сообщение несло строку до 15 раз (79
# показов с повтором на 188 в 419 расшифровках, 54 594 лишних знака). Строка — факт о проекте, а не о сессии, которая
# её сказала; склеивает показ — единственный читатель очереди. Порядок первого появления и пустые строки целы.
# То же у соседних разделов (скептик D1344, M1): общую очередь и сигналы старта пишут сборщики нескольких сессий, и
# одинаковая строка стояла в «Отложенных уведомлениях» 234 показов из 1 783. Раздел закрытых сессий не склеивается: у
# него свой заголовок на каждую сессию, и строка под вторым заголовком — её слово. ponytail: склейка по строкам, а не
# по сообщениям, — у второго многострочного сообщения с тем же пояснением остаётся первая строка (75 сообщений в 6
# расшифровках, номер пункта в ней цел); делить на сообщения — когда встретится общий заголовок с разным списком.
_pas_uniq() { awk 'NF == 0 || !seen[$0]++'; }
[ -z "$PROJS" ] || PROJS=$(printf '%s\n' "$PROJS" | _pas_uniq)
[ -z "$SIGNALS" ] || SIGNALS=$(printf '%s\n' "$SIGNALS" | _pas_uniq)
[ -z "$STOPS" ] || STOPS=$(printf '%s\n' "$STOPS" | _pas_uniq)
[ -z "$ALERTS" ] || ALERTS=$(printf '%s\n' "$ALERTS" | _pas_uniq)

# Уборка недоставленных сигналов от сессий, которые уже не вернутся. Без неё файлы
# копятся годами: до этой правки их накопилось 99, старейшему было три месяца.
find "$STATE_DIR" -maxdepth 1 \( -name 'startup-signals-*.txt' -o -name 'stop-signals-*' -o -name 'project-signals-*' \) \
    -mtime "+${STARTUP_SIGNALS_TTL_DAYS:-14}" -delete 2>/dev/null || true

[ -n "$SIGNALS" ] || [ -n "$ALERTS" ] || [ -n "$STOPS" ] || [ -n "$ORPHANS" ] || [ -n "$PROJS" ] || exit 0

BODY=""
[ -n "$SIGNALS" ] && BODY="📣 Сигналы старта сессии:
${SIGNALS}"
for _pas_part in "$STOPS" "$ORPHANS"; do
    [ -n "$_pas_part" ] || continue
    [ -n "$BODY" ] && BODY="${BODY}

"
    BODY="${BODY}${_pas_part}"
done
if [ -n "$PROJS" ]; then
    [ -n "$BODY" ] && BODY="${BODY}

"
    BODY="${BODY}📁 О проекте этой сессии (сказано сессией любого проекта о его файлах):
${PROJS}"
fi
if [ -n "$ALERTS" ]; then
    [ -n "$BODY" ] && BODY="${BODY}

"
    BODY="${BODY}🔔 Отложенные уведомления системы (с прошлых сессий — канал session-collector):
${ALERTS}"
fi

printf '%s' "$BODY" | jq -Rs '{
      hookSpecificOutput: {
        hookEventName: "UserPromptSubmit",
        additionalContext: .
      }
    }'
exit 0
