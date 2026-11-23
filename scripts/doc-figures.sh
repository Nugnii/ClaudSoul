#!/usr/bin/env bash
# doc-figures.sh — одна величина документации по ключу, из источника, а не из памяти.
#
# Результат: у каждого числа в документах состояния есть команда, которая его считает;
#            `bash scripts/doc-figures.sh <ключ>` печатает нынешнее значение либо `n/a`,
#            когда источника на этой машине нет (чужая машина, CI)
# Проверка результата: bash scripts/doc-figures.sh hooks_registered печатает число
#
# Зачем (30 августа 2026). README нёс 176 находок при 185 в журнале, 52 хука при 54, «пять
# хуков прерывают» при девяти, 30 стартовых знаний при 37 — все числа были верны 25 августа
# и устарели за пять дней, потому что жили прозой: стражи проверяли форму документа (версия
# есть, ссылки живы, автотаблицы свежие), а правду чисел не проверял никто — у них не было
# команды. Тот же класс, что показания бэклога (D210): число, вписанное рукой, устаревает в
# ту же секунду. Здесь — единственное место, где величины считаются; реестр
# scripts/doc-claims.tsv связывает ключ с местом в документе, docs-refresh-claims.sh
# подставляет и сверяет.
#
# КОНТРПРИМЕР: величина без источника на машине (база знаний, журналы состояния) даёт `n/a`,
# а не ноль — ноль был бы ложным показанием; сверка такие ключи пропускает и говорит об этом.
set -uo pipefail

KEY="${1:-}"
REPO="${CLAUDSOUL_REPO:-$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")/.." 2>/dev/null && pwd -P)}"
LESSONS="${LESSONS_DIR:-$HOME/.claude/global-lessons}"
STATE="${STATE_DIR:-$HOME/.claude/hooks/state}"
SESSIONS_REG="${SR_REGISTRY:-$HOME/.claude/sessions/registry.jsonl}"

stat_key() { bash "$REPO/scripts/count-stats.sh" 2>/dev/null | awk -F= -v k="$1" '$1==k {print $2}'; }
kb_count() { [ -d "$LESSONS" ] || { echo n/a; return; }; ls "$LESSONS"/"$1"-*.md 2>/dev/null | wc -l | tr -d ' '; }
need() { [ -f "$1" ] || { echo n/a; exit 0; }; }
# Строки семейства «за всё время» — архив уборки плюс живые журналы НАСТОЯЩИХ сессий (D1008): уборка переносит файлы
# вне окна в архив семейства, и счёт по одной маске живых файлов терял бы перенесённое. Строка — «имя файла ⇥ mtime ⇥
# строка». Журнал сессии — имя кончается UUID и, возможно, суффиксом актора (`hooks/lib/state_archive.py`, `member`;
# форма та же, что у `scripts/signal-precision.sh:78-85`, D1006): фикстуры прогонов (`blocker-fired-replay-…`) не в счёт.
SA_LIB="$REPO/hooks/lib/state_archive.py"
# Неполное чтение (файл или архив не прочитаны — код 2 у владельца) — `n/a`, а не число поменьше (род B). Строки
# берутся в переменную в главной оболочке: `exit` внутри конвейера ключ бы не остановил.
fam_read() { _fam_rows=$(python3 "$SA_LIB" lines "$STATE" "$1") || { echo n/a; exit 0; }; }
fam_out() { [ -z "$_fam_rows" ] || printf '%s\n' "$_fam_rows"; }
fam_has() { ls "$STATE"/"$1"-*.jsonl >/dev/null 2>&1 || [ -s "$STATE/archive/$1.tsv" ]; }
# Поле ШАПКИ знания — разбором, а не построчным чтением (род A). Границы фронтматтера
# держит тот же awk-приём, что у владельца счётчиков (`hooks/knowledge-counter-bump.sh:109-115`):
# без них `grep -m1 '^confirmed_count:'` взял бы первое совпадение где угодно в файле, включая
# провенанс и тело. Поймано прибором родов в час написания: до правки файл носителем не был.
fm_field() {   # fm_field <файл> <поле> → значение из первого YAML-блока; пусто, если нет
    [ -f "$1" ] || return 0
    awk -v f="^$2:" '
        /^---[[:space:]\r]*$/ { d++; if (d >= 2) exit; next }
        d == 1 && $0 ~ f { sub(/^[^:]*:[[:space:]]*/, ""); gsub(/[""]/, ""); print; exit }
    ' "$1"
}

case "$KEY" in
    hooks|hooks_registered|hooks_deny|hooks_ask|hooks_deny_list|hooks_ask_list|skills|bridges|domains|libs|hook_test_files|mcp_test_files)
        stat_key "$KEY" ;;
    hooks_interrupt)   # спрашивают + отказывают
        echo $(( $(stat_key hooks_ask) + $(stat_key hooks_deny) )) ;;
    drift_check_pairs) # пар «репозиторий ↔ установленное», которые сверяет drift-check
        # Утверждение «drift-check по N парам» жило в CLAUDE.md §5 без единого сверщика и
        # разошлось с миром вдвое незаметно: 7 при девяти (D269). Считается по самому
        # прогону, а не по коду стража: он печатает строку на пару.
        # Тот же маркер вложенности, что у ключей tests_*: drift-check — тоже прогон.
        [ "${BACKLOG_CHECKS_NESTED:-0}" = "1" ] && { echo n/a; exit 0; }
        need "$REPO/hooks/tests/drift-check.sh"
        bash "$REPO/hooks/tests/drift-check.sh" 2>/dev/null | grep -cE '^(OK|DRIFT)\|' ;;
    bridges_done|bridges_formalized|bridges_implicit|bridges_designed)
        # Разбивка мостов по статусам. ЧИСЛО БЕРЁТСЯ У ВЛАДЕЛЬЦА — bridges/_index.md
        # §Статистика, — а не пересчитывается здесь по файлам: файл есть у всех 16, статус
        # ведётся только в индексе. Здесь же был предмет D384: architecture.md объявляет
        # «таблица ниже пересобирается из него», а исполнителя у объявления не было, и
        # соседний абзац разошёлся с таблицей на слове «формализован» (16 против 1).
        need "$REPO/bridges/_index.md"
        case "$KEY" in
            bridges_done)       _w='Реализовано' ;;
            bridges_formalized) _w='Формализован' ;;
            bridges_implicit)   _w='Неявно работают' ;;
            bridges_designed)   _w='Спроектировано' ;;
        esac
        sed -n "s/^- ${_w}: \*\*\([0-9][0-9]*\)\*\*.*/\1/p" "$REPO/bridges/_index.md" | head -1 ;;
    root_carriers_R[0-9]*)   # носителей корня Rn по объявленной дроби карты (D397)
        # Владелец числа — root-map.py, режим --declared: знаменатель дроби из карты без
        # исполнения проб; верность самого объявления сверяет `--check` по расписанию.
        need "$REPO/scripts/root-map.py"
        python3 "$REPO/scripts/root-map.py" --declared "${KEY#root_carriers_}" 2>/dev/null ;;
    genus_count)       # родов дефекта в реестре scripts/defect-class-carriers.py
        # Повод 14 сентября 2026: при заведении рода M число «двенадцать родов, буквы A–L» в
        # CLAUDE.md разошлось с миром, а сверщика у него не было — поймано чтением. Тот же
        # класс, что дал повод ключу roots_count четырьмя днями раньше, и лечится так же.
        # ЧИСЛО БЕРЁТСЯ У ВЛАДЕЛЬЦА: `--count` отдаёт длину перечня GENERA, объявленного
        # в самом реестре одним литералом. Считать здесь `grep -c 'РОД '` значило бы завести
        # ВТОРОГО владельца факта (корень R1) — ошибка, уже сделанная и исправленная у корней.
        need "$REPO/scripts/defect-class-carriers.py"
        python3 "$REPO/scripts/defect-class-carriers.py" --count 2>/dev/null ;;
    roots_count)       # корней в карте леса ROOTS.md
        # Повод 10 сентября 2026: CLAUDE.md утверждал «Нынешний лес — три корня», а корней
        # стало четыре (R4 утром), затем пять (R5 днём). Утверждение отстало ДВАЖДЫ за сутки
        # и не покраснело нигде: в реестре `doc-claims.tsv` не было ни одной записи о числе
        # корней, а замер полноты реестра искал только ЦИФРЫ и только девять слов, среди
        # которых «корней» не значилось. Нашёл расхождение владелец чтением, а не механизм.
        #
        # ЧИСЛО БЕРЁТСЯ У ВЛАДЕЛЬЦА, А НЕ СЧИТАЕТСЯ ЗДЕСЬ ЗАНОВО. Первая редакция ставила тут
        # `grep -c '^## R' ROOTS.md` — своя реализация того же знания, то есть второй владелец
        # факта «сколько корней» (корень R1). Поймала это поправка владельца в тот же час:
        # «при создании механизмов нужно смотреть, чем раньше вопрос решался и не задевает ли
        # что-то». Вопрос уже решал `root-map.py` — он разбирает карту ради дробей и знает
        # число, — ему и добавлен режим `--count`.
        need "$REPO/scripts/root-map.py"
        python3 "$REPO/scripts/root-map.py" --count 2>/dev/null ;;
    seed_items)        # знания в seed: всё в knowledge/, кроме META.md и source-tiers.md
        ls "$REPO"/knowledge/*.md 2>/dev/null | grep -v -e '/META\.md$' -e '/source-tiers\.md$' | wc -l | tr -d ' ' ;;
    kb_cases)      kb_count case ;;
    kb_patterns)   kb_count pattern ;;
    kb_principles) kb_count principle ;;
    kb_items)      # операционные + энциклопедические, без META.md и source-tiers.md
        [ -d "$LESSONS" ] || { echo n/a; exit 0; }
        ls "$LESSONS"/*.md 2>/dev/null | grep -v -e '/META\.md$' -e '/source-tiers\.md$' | wc -l | tr -d ' ' ;;
    kb_items_operational)
        # Знаменатель для утверждений о ПОЛЯХ ОПЕРАЦИОННОЙ СХЕМЫ (confirmed_count,
        # contradicted_count, outcome и прочих 39). У entity/fact/relation этих полей нет
        # по построению, и включать их в знаменатель значит занижать долю на 22%: до
        # 7 сентября 2026 в README стояло «1 из 459» вместо «1 из 362».
        # kb_items остаётся как есть: для утверждения «записей в базе» он верен.
        [ -d "$LESSONS" ] || { echo n/a; exit 0; }
        ls "$LESSONS"/case-*.md "$LESSONS"/pattern-*.md "$LESSONS"/principle-*.md 2>/dev/null \
            | wc -l | tr -d ' ' ;;
    kb_cases_error)
        [ -d "$LESSONS" ] || { echo n/a; exit 0; }
        grep -l '^outcome: *error' "$LESSONS"/case-*.md 2>/dev/null | wc -l | tr -d ' ' ;;
    kb_cases_success)
        [ -d "$LESSONS" ] || { echo n/a; exit 0; }
        grep -l '^outcome: *success' "$LESSONS"/case-*.md 2>/dev/null | wc -l | tr -d ' ' ;;
    kb_co_cognition)
        [ -d "$LESSONS" ] || { echo n/a; exit 0; }
        grep -lE '^origin: *"?co-cognition' "$LESSONS"/*.md 2>/dev/null | wc -l | tr -d ' ' ;;
    kb_contradicted_nonzero)
        [ -d "$LESSONS" ] || { echo n/a; exit 0; }
        grep -lE '^contradicted_count: *[1-9]' "$LESSONS"/*.md 2>/dev/null | wc -l | tr -d ' ' ;;
    findings_total)    # находки output-language-check за всё время (surfaced + pending)
        fam_has output-violations || { echo n/a; exit 0; }
        fam_read output-violations; fam_out | wc -l | tr -d ' ' ;;
    findings_[0-9][0-9][0-9][0-9]-[0-9][0-9])
        fam_has output-violations || { echo n/a; exit 0; }
        fam_read output-violations; fam_out | cut -f3- | jq -r --arg m "${KEY#findings_}" 'select((.ts // "")[0:7] == $m) | 1' | wc -l | tr -d ' ' ;;
    sessions_[0-9][0-9][0-9][0-9]-[0-9][0-9])
        # уникальная сессия — по месяцу своей ПЕРВОЙ записи в телеметрии слоя 6
        need "$STATE/intrusiveness-history.jsonl"
        jq -r '[.session_id, (.date // "")] | @tsv' "$STATE/intrusiveness-history.jsonl" \
        | awk -F'\t' -v m="${KEY#sessions_}" '$1!="" && $2!="" { if(!($1 in f) || $2<f[$1]) f[$1]=$2 } END{for(s in f) if(substr(f[s],1,7)==m) c++; print c+0}' ;;
    per_session_[0-9][0-9][0-9][0-9]-[0-9][0-9])
        m="${KEY#per_session_}"; f=$(bash "$0" "findings_$m"); s=$(bash "$0" "sessions_$m")
        case "$f$s" in *n/a*) echo n/a; exit 0 ;; esac
        [ "$s" -gt 0 ] && awk -v f="$f" -v s="$s" 'BEGIN{printf "%.2f", f/s}' || echo n/a ;;
    sessions_unique)   # уникальных сессий в телеметрии слоя 6 за всё время
        need "$STATE/intrusiveness-history.jsonl"
        jq -r '.session_id' "$STATE/intrusiveness-history.jsonl" | sort -u | wc -l | tr -d ' ' ;;
    ablation_registered|ablation_classified|ablation_eligible|ablation_completed)
        # Воронка §4 — из журнала напрямую. НЕ через `journal.sh funnel`: тот на каждом
        # запуске делает mkdir+touch, и сверка чисел трогала бы mtime append-only
        # prereg-журнала при каждом бампе версии, публикации и прогоне тестов.
        AJ="${ABLATION_DIR:-$HOME/.claude/ablation}/journal.jsonl"
        need "$AJ"
        case "$KEY" in
            ablation_registered) _E='.e=="register"' ;;
            ablation_classified) _E='.e=="classify"' ;;
            ablation_eligible)   _E='.e=="classify" and .class=="eligible"' ;;
            ablation_completed)  _E='.e=="pair_done"' ;;
        esac
        jq -s "[.[] | select($_E)] | length" "$AJ" ;;
    registry_sessions_since_2026-04-24)
        need "$SESSIONS_REG"
        jq -r 'select((.started_at // "") >= "2026-04-24") | .session_id' "$SESSIONS_REG" | sort -u | wc -l | tr -d ' ' ;;
    blocker_markers)   # пометок blocker-tier за всё время — в журналах настоящих сессий
        fam_has blocker-fired || { echo n/a; exit 0; }
        fam_read blocker-fired; fam_out | wc -l | tr -d ' ' ;;
    blocker_sessions)  # СЕССИЙ, а не файлов: прежде считались журналы, и README завышал число в ~5 раз
        fam_has blocker-fired || { echo n/a; exit 0; }
        fam_read blocker-fired; fam_out | cut -f1 | sed -E 's|^blocker-fired-||; s/\.agent-[A-Za-z0-9_-]+//; s/\.jsonl$//' \
          | sort -u | wc -l | tr -d ' ' ;;
    trust_guard_firings)   # срабатывание — разобранная запись; битые строки журнала (D383: 131 из 329) срабатываниями не являются
        fam_has trust-guard-fired || { echo n/a; exit 0; }
        fam_read trust-guard-fired; fam_out | cut -f3- | jq -rRc 'fromjson? // empty' 2>/dev/null | awk 'END { print NR }' ;;
    injections_total)  # из сводки метрик — единственный носитель, переживающий ротацию журнала
        need "$STATE/metrics.md"
        grep -oE 'Инжекций \(из лога\): [0-9]+' "$STATE/metrics.md" | grep -oE '[0-9]+$' | head -1 ;;
    disagreement_rate|disagreement_total)
        need "$STATE/metrics.md"
        v=$(grep -oE 'disagreement_resolution_rate *\| *[0-9]+% \([0-9]+/[0-9]+\)' "$STATE/metrics.md" | head -1)
        [ -n "$v" ] || { echo n/a; exit 0; }
        if [ "$KEY" = disagreement_rate ]; then printf '%s' "$v" | grep -oE '[0-9]+%' | tr -d '%'
        else printf '%s' "$v" | grep -oE '/[0-9]+' | tr -d '/'; fi ;;
    kb_generalisations)   # паттерны + принципы
        [ -d "$LESSONS" ] || { echo n/a; exit 0; }
        echo $(( $(kb_count pattern) + $(kb_count principle) )) ;;
    kb_lineage)           # из них — с непустым source_cases (родословная записана)
        [ -d "$LESSONS" ] || { echo n/a; exit 0; }
        grep -LE '^source_cases: *\[\] *$' "$LESSONS"/pattern-*.md "$LESSONS"/principle-*.md 2>/dev/null | wc -l | tr -d ' ' ;;
    ki_stored|ki_reached|ki_reached_pct|ki_acts)   # уровни знания из последнего отчёта замера knowledge-instrument
        need "$STATE/knowledge-instrument.md"
        case "$KEY" in
            ki_stored)      grep -E '^\| хранится' "$STATE/knowledge-instrument.md" | head -1 | awk -F'|' '{gsub(/[^0-9]/,"",$3); print $3}' ;;
            ki_reached)     grep -E '^\| \*{0,2}доходил(о|а)? до контекста' "$STATE/knowledge-instrument.md" | head -1 | awk -F'|' '{gsub(/[^0-9]/,"",$3); print $3}' ;;
            ki_reached_pct) grep -E '^\| \*{0,2}доходил(о|а)? до контекста' "$STATE/knowledge-instrument.md" | head -1 | awk -F'|' '{gsub(/[^0-9.]/,"",$4); print $4}' ;;
            ki_acts)        grep -E '^\| \*{0,2}действует' "$STATE/knowledge-instrument.md" | head -1 | awk -F'|' '{gsub(/[^0-9]/,"",$3); print $3}' ;;
        esac ;;
    ki_date)              # дата последнего отчёта замера
        need "$STATE/knowledge-instrument.md"
        python3 -c "import os,sys,datetime; print(datetime.date.fromtimestamp(os.stat(sys.argv[1]).st_mtime))" "$STATE/knowledge-instrument.md" ;;
    mcp_tests)            # проверок в наборе сервера (не файлов — их даёт mcp_test_files)
        # Считается СТАТИЧЕСКИ, а не прогоном pytest: ключ обязан отвечать дёшево и без
        # виртуальной среды, иначе сверка чисел документов станет зависеть от установки.
        # Сверено 4 сентября 2026: статический счёт 124 = pytest 124, параметризованных
        # тестов в наборе 0. НАЗВАННЫЙ ПРЕДЕЛ: появится `parametrize` — числа разойдутся,
        # и тогда ключ обязан считать прогоном. Условие снятия наблюдаемо:
        # `grep -rc parametrize mcp-server/tests` перестанет быть нулём.
        [ -d "$REPO/mcp-server/tests" ] || { echo n/a; exit 0; }
        grep -rhc '^def test_\|^    def test_' "$REPO"/mcp-server/tests/*.py 2>/dev/null \
            | paste -sd+ - | bc ;;
    cocog_impact_co|cocog_impact_solo)   # средний impact co-cognition против solo — блок моста L2↔L7
        # Повод (4 сентября 2026): правила утверждали «4.1 против 3.2» при мире 4.4 против 3.5.
        # Направление держалось, числа уплыли — потому что жили прозой без команды.
        need "$STATE/metrics.md"
        _ci=$(grep -m1 'Средний impact' "$STATE/metrics.md" 2>/dev/null) || true
        [ -n "${_ci:-}" ] || { echo n/a; exit 0; }
        case "$KEY" in
            cocog_impact_co)   printf '%s\n' "$_ci" | sed -n 's/.*co-cognition \([0-9][0-9.]*\).*/\1/p' ;;
            cocog_impact_solo) printf '%s\n' "$_ci" | sed -n 's/.*solo \([0-9][0-9.]*\).*/\1/p' ;;
        esac ;;
    kb_seed_principles) ls "$REPO"/knowledge/principle-*.md 2>/dev/null | wc -l | tr -d ' ' ;;
    kb_seed_patterns)   ls "$REPO"/knowledge/pattern-*.md 2>/dev/null | wc -l | tr -d ' ' ;;
    tests_*)              # число проверок теста: запускает hooks/tests/<имя>.sh и читает его итог
        # Ключ ЗАПУСКАЕТ прогон, поэтому уважает маркер вложенности `BACKLOG_CHECKS_NESTED`
        # — тот же, которым `completion-gate.sh:329` ограничивает кольцо «гейт → тест пункта
        # → Stop-хук → гейт» (шторм 1 сентября 2026: 2225 процессов, load 16,5). Без него
        # «Проверка» пункта, зовущая сверщик чисел, разворачивалась в прогон всего набора:
        # 11 сентября 2026 шесть тестов разом ушли в таймаут 120 с, будучи зелёными на HEAD.
        # Внутри вложенного вызова число не добывается — это «источник здесь недоступен»
        # (n/a), а не ноль: сверщик такое пропускает и НАЗЫВАЕТ, а нулём бы соврал.
        # Дверь читается как у архиватора и гейта — `= "1"`, не `-n` (D1179, L1: `=0` здесь значил «внутри»).
        [ "${BACKLOG_CHECKS_NESTED:-0}" = "1" ] && { echo n/a; exit 0; }
        _t="$REPO/hooks/tests/${KEY#tests_}.sh"; [ -f "$_t" ] || { echo n/a; exit 0; }
        _out=$(bash "$_t" 2>&1); _rc=$?
        _out=$(printf '%s\n' "$_out" | tail -3)
        # Число берётся ТОЛЬКО из зелёного прогона. Красный даёт МЕНЬШЕЕ «N passed», и без
        # этой проверки оно молча становилось характеристикой теста в документе. Случай
        # 1 сентября 2026: `test_backlog_item_shape` читает боевой BACKLOG.md (его строка 75
        # сверяет трёх читателей), архиватор в тот момент переписывал файл, тест напечатал
        # «8 passed, 1 failed» — и `.claude-docs/modules/backlog-item-shape.md` получил
        # «8 проверок» вместо девяти. Падение при этом не отразилось нигде.
        # Смотрим и код возврата, и напечатанный счётчик падений: тест может вернуть 0 и
        # всё же сообщить о провалах, и наоборот.
        _fail=$(printf '%s\n' "$_out" | grep -oE '([0-9]+) failed|FAIL: *([0-9]+)' | grep -oE '[0-9]+' | head -1)
        if [ "$_rc" -ne 0 ] || [ "${_fail:-0}" -gt 0 ] 2>/dev/null; then echo err; exit 0; fi
        # Формы итога в тестах проекта: «N passed, M failed» · «PASS: N  FAIL: M» · «N/M passed»
        _n=$(printf '%s\n' "$_out" | grep -oE '([0-9]+) passed|PASS: *([0-9]+)|([0-9]+)/[0-9]+ passed' | tail -1 | grep -oE '[0-9]+' | head -1)
        # Тест есть, а числа нет — «err» (сверка называет), а не «n/a» (сверка молча пропускает).
        [ -n "$_n" ] && echo "$_n" || echo err ;;
    # --- величины входного текста (14 сентября 2026) ---------------------------------
    # Возраст проекта в МЕСЯЦАХ от первого коммита. Число устаревает само, по календарю, и
    # именно поэтому у него обязан быть источник: прежняя редакция входного текста несла
    # выдуманные «полгода» и «год», пойманные внешней рецензией, а не механизмом.
    project_age_months)
        _first=$(git -C "$REPO" log --reverse --format=%ct 2>/dev/null | head -1)
        [ -n "$_first" ] || { echo n/a; exit 0; }
        _now=$(date +%s)
        echo $(( (_now - _first) / 2629746 )) ;;
    # Подтверждений у образца «форма входа проверки взята не из мира» — живой счётчик базы.
    kb_fixture_confirmed)
        _f="$LESSONS/pattern-fixture-form-not-taken-from-the-world.md"
        [ -f "$_f" ] || { echo n/a; exit 0; }
        fm_field "$_f" confirmed_count | grep -oE '^[0-9]+' ;;
    # Ранг того же образца среди всех pattern-* по confirmed_count: «шестой по частоте».
    # Растёт и падает сам — потому и считается, а не пишется прозой.
    kb_fixture_rank)
        [ -d "$LESSONS" ] || { echo n/a; exit 0; }
        _self=$(fm_field "$LESSONS/pattern-fixture-form-not-taken-from-the-world.md" confirmed_count | grep -oE '^[0-9]+')
        [ -n "$_self" ] || { echo n/a; exit 0; }
        _above=$(for _p in "$LESSONS"/pattern-*.md; do
                     _n=$(fm_field "$_p" confirmed_count | grep -oE '^[0-9]+')
                     [ -n "$_n" ] && [ "$_n" -gt "$_self" ] && echo x
                 done | wc -l | tr -d ' ')
        echo $(( _above + 1 )) ;;
    # Максимум подтверждений среди образцов — «впереди, например, … с пятьюдесятью тремя».
    kb_pattern_top)
        [ -d "$LESSONS" ] || { echo n/a; exit 0; }
        for _p in "$LESSONS"/pattern-*.md; do grep -m1 '^confirmed_count:' "$_p" 2>/dev/null | grep -oE '[0-9]+'; done \
            | sort -rn | head -1 ;;
    # Инвариантов в документе-экспорте: нумерованный список раздела 2.5, считается по нему же.
    export_invariants)
        _d="$REPO/docs/mechanism-errors-and-backlog.ru.md"
        [ -f "$_d" ] || { echo n/a; exit 0; }
        awk '/^## 2\.5/{f=1} /^## 2\.6/{f=0} f && /^[0-9]+\. /{n++} END{print n+0}' "$_d" ;;
    today) date +%Y-%m-%d ;;
    "") echo "применение: bash scripts/doc-figures.sh <ключ>" >&2; exit 2 ;;
    *) echo "неизвестный ключ: $KEY" >&2; exit 2 ;;
esac
