#!/usr/bin/env bash
# completion-gate.sh — Stop: пункт сверяется со СВОИМ критерием, а не с отчётом; пункт, заведённый в этой сессии, берётся сразу за текущей починкой.
# en: Stop hook — a backlog item is judged by its own check command, not by the report; an item opened in this session is taken right after the current fix.
#
# ДВА ПРЕДМЕТА, ПРОТИВОПОЛОЖНЫЕ ПО ЗНАКУ. У ☑ команда обязана быть ЗЕЛЁНОЙ: красная значит
# «закрытие разошлось с критерием». У ОТКРЫТОГО пункта (обе открытые метки легенды) она
# обязана быть КРАСНОЙ: зелёная значит ровно
# одно из двух, и оба — дефект (проблема уже решена и пункт пора закрывать с показанием,
# либо команда не о ней). Неисполнимая по оболочечному синтаксису — третий дефект: такая
# строка не проверяет ничего. Повод (D263, 2 сентября 2026): строку «Проверка» прогоняли
# ровно два механизма — этот гейт и `scripts/backlog-archive.sh`, — и ОБА только у
# закрытого пункта. Открытый мог пролежать месяцами с командой, которая не запускается,
# запускается не про то или зелена с рождения. Замер того дня: шесть «Проверок» из семи
# открытых не мерили того, что объявлено в их же «Результате».
#
# Инженерная эскалация pattern-completion-by-internal-proxy (confirmed 14 ≥ порога 12,
# заявка открыта 2026-08-16, исполнена 2026-08-31): «задача объявляется завершённой по
# внутреннему прокси (объём сделанного, факт артефакта, отчёт исполнителя), а не сверкой
# с внешним явным критерием». У пункта долга внешний критерий машинный — строка
# `**Проверка.** \`команда\` → 0` из контракта BACKLOG.md. Метку ☑ ставит исполнитель;
# этот страж прогоняет команду пункта и верит коду возврата.
#
# ДВА РУБЕЖА одного гейта. Здесь — обратная связь В ТОЙ ЖЕ СЕССИИ (инжект на Stop);
# неотвратимость — в `scripts/backlog-archive.sh`: ☑ с красной «Проверкой» в архив не
# переносится. Инжект, а не отказ (ADR-011): Stop нечего отказывать — действие уже
# совершено; последствие одно, но точка отказа — перенос, и она уже держится архиватором.
# У ОТКРЫТОГО пункта второго рубежа нет вовсе: архиватор его не касается по построению.
# Названо, а не умолчано.
#
# ПОЧЕМУ НЕ ОТКАЗ В МОМЕНТ ЗАПИСИ (D264). Признак «зелёная у открытого» к уровню 4 не готов: за
# 220 коммитов, трогавших BACKLOG.md, уникальных пар «открытый пункт, команда» — 28, и
# зелёных среди них НОЛЬ. Положительных срабатываний нет ни одного, значит точность отказа
# считать не на чем, а ADR-011 требует именно замеренной. Плюс на PreToolUse хук видит
# фрагмент правки, а не файл: метки пункта в нём может не быть, а закрывающая правка «в работе» → ☑
# обязана нести зелёную команду — отказ ударил бы ровно по правильному действию. Оба класса
# исчезают на границе хода, где файл окончателен. Условие снятия — в D264.
#
# НАЗВАННЫЙ ПРЕДЕЛ. Покрыт только пункт долга: у «скилл выполнен» и «задача сделана» нет
# машинного события завершения и машинного критерия — их слой держат skill-review-check
# (контракт DoD в файле скилла) и дисциплина; заявка эскалации закрыта в той части, где
# у завершения есть носитель. Пункты без D-номера и с номером < CG_MIN_ID (200, порог
# контракта) не проверяются — как в архиваторе, задним числом контракт не вменяется.
# Условие снятия: у «скилл выполнен» / «задача сделана» появится машинный носитель
# завершения с исполнимой проверкой (аналог строки «Проверка» у пункта долга) — тогда
# гейт расширяется на этот слой. Формулировка едина с модульным доком (single source).
#
# ДВА БЭКЛОГА, как у backlog-touch-check: долг ClaudSoul (абсолютный путь) + локальный
# долг проекта сессии (по cwd). Кэш по mtime: файл, чьи ☑ уже прошли зелёными и с тех
# пор не менялся, повторно не гоняется — Stop не платит за неизменное.
#
# Input  (stdin): {session_id, cwd, ...} (Stop JSON)
# Output (stdout): {systemMessage} либо пусто
# Exit:  always 0 — страж деградирует молча.
set -uo pipefail

# Вложенный прогон: этот гейт исполняет команды «Проверок», и команда может сама дойти
# до Stop-хука — по маркеру вложенный гейт молчит, суждение уже идёт уровнем выше
# (кольцо и шторм — см. дверь в scripts/backlog-archive.sh)
[ "${BACKLOG_CHECKS_NESTED:-0}" = "1" ] && exit 0

command -v jq >/dev/null 2>&1 || exit 0
command -v python3 >/dev/null 2>&1 || exit 0
INPUT=$(cat 2>/dev/null) || exit 0
[ -n "$INPUT" ] || exit 0

PATHS_LIB="${PATHS_LIB:-$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" 2>/dev/null && pwd)/paths-lib.sh}"
[ -f "$PATHS_LIB" ] || PATHS_LIB="$HOME/.claude/hooks/paths-lib.sh"
# shellcheck source=/dev/null
[ -f "$PATHS_LIB" ] && . "$PATHS_LIB"
# Общий замок (род H): журнал срабатываний #CG_OPEN один на все сессии, а разборщик
# ниже читает его целиком и кладёт обратно. Замер 4 сентября 2026 без замка: восемь
# одновременных границ хода оставляли 4-7 записей из 8, тридцать — 20 из 30.
STATE_LOCK_LIB="${STATE_LOCK_LIB:-$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" 2>/dev/null && pwd)/state-lock-lib.sh}"
[ -f "$STATE_LOCK_LIB" ] || STATE_LOCK_LIB="$HOME/.claude/hooks/state-lock-lib.sh"
# shellcheck source=/dev/null
if [ -f "$STATE_LOCK_LIB" ]; then . "$STATE_LOCK_LIB"; fi
# Ожидание щедрее умолчания: это Stop-хук, он и так исполняет команды «Проверки», а
# уступить замок здесь — значит снова потерять запись. Срыв брошенного замка (30 с)
# не даёт очереди застыть навсегда.
: "${CLAUDSOUL_LOCK_TRIES:=1500}"
PORTABLE_LIB="${PORTABLE_LIB:-$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" 2>/dev/null && pwd)/portable-lib.sh}"
[ -f "$PORTABLE_LIB" ] || PORTABLE_LIB="$HOME/.claude/hooks/portable-lib.sh"
# shellcheck source=/dev/null
[ -f "$PORTABLE_LIB" ] && . "$PORTABLE_LIB"

# Признак пункта, идентификатор и строка «Проверка» — ТОЛЬКО из общей библиотеки (D305).
# Здесь стояли три свои копии: `item_re` не снимал забор кода (образец контракта внутри
# ``` читался пунктом), идентификатор брался по ВИДУ (`D(\d+)`, и на «- ☑ **X1** закрыт
# по образцу D284» гейт винил D284 — чужой живой открытый пункт), а строка «Проверка»
# извлекалась второй копией выражения. Способ передачи признака питоновскому читателю уже
# был применён у архиватора (`scripts/backlog-archive.sh:104-124`) — здесь он тот же.
BL_LIB="${BL_LIB:-$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" 2>/dev/null && pwd)/backlog-lib.sh}"
[ -f "$BL_LIB" ] || BL_LIB="$HOME/.claude/hooks/backlog-lib.sh"
# shellcheck source=/dev/null
{ [ -f "$BL_LIB" ] && . "$BL_LIB"; } || exit 0
command -v backlog_item_re >/dev/null 2>&1 || exit 0
command -v backlog_strip_fenced >/dev/null 2>&1 || exit 0
BACKLOG_ITEM_RE="$(backlog_item_re)"
BACKLOG_MARKS_ALT="$(backlog_marks_alt "${BACKLOG_DONE_MARKS}${BACKLOG_OPEN_MARKS}")"
for _need in BACKLOG_ID_TOKEN_RE BACKLOG_CHECK_RE BACKLOG_FORM_PROXY_RE BACKLOG_ID_NUM_RE BACKLOG_DONE_MARKS BACKLOG_OPEN_MARKS BACKLOG_MARK_WIP; do
    eval "[ -n \"\${$_need:-}\" ]" || exit 0
done
export BACKLOG_ITEM_RE BACKLOG_ID_TOKEN_RE BACKLOG_CHECK_RE BACKLOG_FORM_PROXY_RE BACKLOG_ID_NUM_RE BACKLOG_MARKS_ALT
export BACKLOG_DONE_MARKS BACKLOG_OPEN_MARKS

STATE="${STATE_DIR:-$HOME/.claude/hooks/state}"
mkdir -p "$STATE" 2>/dev/null || exit 0

BACKLOG="${CG_BACKLOG:-${CLAUDSOUL_ROOT:-$HOME/My Project/ClaudSoul}/BACKLOG.md}"
CWD=$(printf '%s' "$INPUT" | jq -r '.cwd // ""' 2>/dev/null)
LOCAL_BACKLOG="${CG_LOCAL_BACKLOG:-}"
# Доверие определяется ИСТОЧНИКОМ ПУТИ, а не местом файла (D244). Команда «Проверки»
# исполняется через `bash -c`, то есть строка из markdown становится вызовом. Путь,
# пришедший из `cwd` сессии, — вход извне: достаточно открыть чужой склонированный
# репозиторий с ☑-пунктом, чтобы на первом же Stop исполнилось что угодно. Воспроизведено
# 1 сентября 2026 в песочнице: команда из подложенного BACKLOG.md отработала.
# Путь, названный переменной окружения, — акт владельца (и тестов), он доверенный.
LOCAL_FROM_CWD=0
if [ -z "$LOCAL_BACKLOG" ] && [ -n "$CWD" ] && command -v find_project_root >/dev/null 2>&1; then
    _root=$(find_project_root "$CWD")
    if [ -n "$_root" ] && [ -f "$_root/BACKLOG.md" ]; then
        LOCAL_BACKLOG="$_root/BACKLOG.md"
        LOCAL_FROM_CWD=1
    fi
fi
[ "${LOCAL_BACKLOG:-}" = "$BACKLOG" ] && LOCAL_BACKLOG=""

RED=""
OPENBAD=""
FORMBAD=""
BROKEN=""
# Носитель срабатываний канала #CG_OPEN (D264) — журнал общий на все файлы; пишет и
# проставляет исход разборщик ниже, по ключу (файл, пункт, команда). Координата файла
# в ключе — не украшение: бэклогов в цикле два, и оба бывают доверенными.
CG_FIRED_LOG="${CG_FIRED_LOG:-$STATE/cg-open-fired.jsonl}"
_cg_sid=$(printf '%s' "$INPUT" | jq -r '.session_id // "unknown"' 2>/dev/null || echo unknown)
# Оба пути В КАВЫЧКАХ: незакавыченный $LOCAL_BACKLOG дробился по пробелу пути
# («My Project/…»), и локальный бэклог таких проектов молча выпадал из проверки
# (прожарка 31.08, атака adv5 spaced_local_backlog). Пустой LOCAL отсекает -n.
for f in "$BACKLOG" "$LOCAL_BACKLOG"; do
    [ -n "$f" ] && [ -f "$f" ] || continue
    _mt=""
    command -v file_mtime >/dev/null 2>&1 && _mt=$(file_mtime "$f" 2>/dev/null)
    _key=$(printf '%s' "$f" | cksum 2>/dev/null | awk '{print $1}')
    OKF="$STATE/completion-gate-${_key:-0}.ok"
    if [ -n "$_mt" ] && [ -f "$OKF" ] && [ "$(cat "$OKF" 2>/dev/null)" = "$_mt" ]; then
        continue
    fi
    # Замер цены отказа перед правкой: локальных бэклогов в дереве владельца два,
    # ☑-пунктов в них 34, строк «Проверка» — НОЛЬ. Исполнять там было нечего ни разу,
    # то есть отказ от исполнения не отнимает работающего поведения.
    _trusted=1
    [ "$f" = "$LOCAL_BACKLOG" ] && [ "$LOCAL_FROM_CWD" = "1" ] && _trusted=0
    # Забор кода снимается ДО разбора и тем же механизмом, что у остальных читателей:
    # строка внутри ``` — образец разметки, а не пункт (роль задана окружением, и признак
    # одной строки её различить не может по построению). Оригинальный путь подаётся
    # отдельно: он ключ журнала срабатываний и каталог исполнения команд.
    _txt="$STATE/cg-stripped-$$.md"
    backlog_strip_fenced < "$f" > "$_txt" 2>/dev/null || cp -f "$f" "$_txt" 2>/dev/null
    _arc="${f%/*}/BACKLOG-archive.md"
    _atxt=""
    if [ -f "$_arc" ]; then
        _atxt="$STATE/cg-stripped-arc-$$.md"
        backlog_strip_fenced < "$_arc" > "$_atxt" 2>/dev/null || _atxt=""
    fi
    _out=$(with_lock "$CG_FIRED_LOG" env CG_FILE="$f" CG_TRUSTED="$_trusted" \
        CG_TEXT="$_txt" CG_ARCHIVE_TEXT="$_atxt" \
        CG_FIRED_LOG="$CG_FIRED_LOG" CG_SID="$_cg_sid" python3 - <<'PY' 2>/dev/null
import json, os, re, subprocess, time

path = os.environ["CG_FILE"]
min_id = int(os.environ.get("CG_MIN_ID", "200"))
max_runs = int(os.environ.get("CG_MAX", "3"))
timeout = int(os.environ.get("CG_TIMEOUT", "60"))
# Открытых пунктов больше, чем закрытых, и лимит у них свой: CG_MAX=3 рассчитан на редкие
# ☑ и закреплён тестом (test_adv4_cg_maxruns_false_green), трогать его нельзя. У открытых
# цену Stop ограничивает ВРЕМЯ, и только оно.
#
# СЧЁТНОГО ПРЕДЕЛА ЗДЕСЬ БОЛЬШЕ НЕТ. `CG_MAX_OPEN`=16 при 26 открытых пунктах означал, что
# последние десять — D303, D304, D305, D306, D307, D308, D310, D309, D313, D314, то есть
# ровно все пункты-роды — не проверялись НИ РАЗУ, а наружу уходил один лишь «#CG_STATUS
# partial», который читает bash-сторона для решения о кэше. Имён пропущенных не получал
# никто, хотя строкой ниже этот же файл держит обратный принцип: «Не исполняем и НЕ
# молчим». Счётчик прогонов был предметом не тем: он режет по произвольному ЧИСЛУ раньше,
# чем кончается время, и первым отсекает конец файла — куда попадают самые свежие пункты.
# Замер 6 сентября 2026 на живом файле: 26 команд суммарно 22,34 с, из них четыре прогона
# реестра родов — 13,6 с. Бюджет 60 с — запас против роста ЧИСЛА пунктов, а не их цены.
deadline = time.monotonic() + float(os.environ.get("CG_BUDGET_OPEN", "60"))
# errors="replace": один битый байт в markdown не имеет права онеметь стража —
# прожарка 31.08 показала: краш до первого print читался бashем как «чисто» и
# ОТРАВЛЯЛ кэш зелёным (атака cg_nonutf8_false_green).
text = open(os.environ.get("CG_TEXT") or path, encoding="utf-8", errors="replace").read()

# Предмет пункта — правило backlog-lib.sh (обе вёрстки: список и заголовок);
# метки альтернативой литералов, не классом — тот же байтовый капкан mawk/C-локали.
# Квантор ЛЕНИВЫЙ: метка пункта — ПЕРВЫЙ глиф строки, как у архиватора и backlog-lib.
# Жадный [^|\n]* откатывался к ПОСЛЕДНЕЙ метке, и «### D200 ☑ … (было в работе)» читался
# открытым — два парсера одного контракта расходились (атака cg_mark_backtrack_blind).
item_re = re.compile(os.environ["BACKLOG_ITEM_RE"])
mark_re = re.compile(os.environ["BACKLOG_MARKS_ALT"])
id_token_re = re.compile(os.environ["BACKLOG_ID_TOKEN_RE"])
done_marks = os.environ["BACKLOG_DONE_MARKS"]
open_marks = os.environ["BACKLOG_OPEN_MARKS"]
# Статусная метка — ПЕРВАЯ в строке, тем же правилом, что `backlog_status_is`:
# заголовочная вёрстка законно несёт вторую метку в скобках («… (было в работе)»).
def _mark_of(line):
    m = mark_re.search(line)
    return m.group(0) if m else None
# Идентификатор — первый токен «буквы + номер» ЦЕЛИКОМ, разметка снята: то же правило,
# что у `backlog_id_stream` и у архиватора.
def _id_of(line):
    m = id_token_re.search(line.replace("*", ""))
    return m.group(0) if m else None

items, cur = [], None
for ln in text.splitlines(True):
    m = item_re.match(ln)
    if m:
        if cur: items.append(cur)
        cur = [_mark_of(ln), ln, []]
    elif re.match(r'^#{2,6} ', ln):
        if cur: items.append(cur)
        cur = None
    elif cur:
        cur[2].append(ln)
if cur: items.append(cur)

# РАЗБОР, НЕ УВИДЕВШИЙ НИ ОДНОГО ПУНКТА, — НЕ «ЧИСТО» (13 сентября 2026, прожарка).
# Незакрытый забор кода гасит ВЕСЬ остаток файла: `backlog_strip_fenced` опустошает строки
# до конца, `items` выходит пустым, и гейт молчит — красное ☑ под забором не называется
# никем. Молчание тут неотличимо от «проверено, чисто», то есть ровно род B реестра.
# Признак точный, а не эвристика: пункты есть в СЫРОМ тексте и исчезли в очищенном —
# значит их съел разбор, а не их отсутствие. Пустой бэклог (пунктов нет ни там, ни там)
# законен и молчит по-прежнему.
if not items:
    _raw = open(path, encoding="utf-8", errors="replace").read()
    _raw_items = sum(1 for ln in _raw.splitlines(True) if item_re.match(ln))
    if _raw_items:
        print(f"#CG_BROKEN {_raw_items}")

runs = 0
runs_open = 0
unchecked = []
partial = False
untrusted = 0
trusted = os.environ.get("CG_TRUSTED", "1") == "1"
CHECK_RE = re.compile(os.environ["BACKLOG_CHECK_RE"], re.M)
FORM_PROXY_RE = re.compile(os.environ["BACKLOG_FORM_PROXY_RE"], re.M)
# Закрытия с меткой «судит по форме»: команда дала 0, но смотрела на ИМЯ файла либо СЛОВО в
# тексте, а не на результат работы. Канал ОТДЕЛЬНЫЙ от #CG_OPEN и от красного ☑ — там
# «команда дала не-0» и «у открытого прибор не о том», здесь третье утверждение, и лечатся
# они разным. Неотвратимость держит архиватор (закрытый пункт с меткой не переносит); здесь
# напоминание в ТОЙ ЖЕ сессии закрытия, потому что архиватор ходит раз в семь дней.
# Множество нужно ещё и резолверу исходов ниже: закрытие, объявленное слепым, не вправе
# подтверждать точность признака #CG_OPEN.
form_ids = set()
norm = lambda c: " ".join(c.split())
by_id = {}        # D-номер → (метка, [команды «Проверки» как есть в файле сейчас])
ambiguous_ids = set()  # номера, встреченные в файле дважды: исход по ним не проставляется
verified = set()  # (D-номер, команда) закрытого пункта, давшая 0 В ЭТОМ прогоне
fired = []        # (D-номер, род, команда) — срабатывания канала #CG_OPEN этого прогона
for mk, head, body_lines in items:
    _iid = _id_of(head)
    if not _iid:
        continue
    # ПОРОГ действует только там, где есть чем доказать возраст: `D` + число ниже
    # MIN_ID. Идентификатор вне D-нумерации (`X1`, `TASK-003a`) возраста не сообщает и
    # порогом не отсекается. Шаблон — из библиотеки (`BACKLOG_ID_NUM_RE`): до 13 сентября
    # 2026 правило звалось единым, а держалось двумя копиями, и они разошлись на `D42a`.
    _dnum = re.match(os.environ["BACKLOG_ID_NUM_RE"], _iid)
    if _dnum and int(_dnum.group(1)) < min_id:
        continue
    body = "".join(body_lines)
    # Один номер у двух блоков файла — неоднозначность, а не «побеждает последний». До
    # 3 сентября 2026 запись просто перетиралась, и метка ВТОРОГО блока решала исход
    # ПЕРВОГО: строка, повторяющая форму заголовка внутри цитаты (а такие в этом файле
    # законны — пункты цитируют контракт), ставила настоящему открытому пункту
    # необратимый `confirmed`. Воспроизведено прожаркой 3 сентября и подтверждено моим
    # прогоном: D260 остался открытым и получил confirmed. Дубль номера ловит отдельный страж
    # (backlog-vanish-check), здесь его достаточно НЕ ИСПОЛЬЗОВАТЬ для необратимой записи.
    if _iid in by_id:
        ambiguous_ids.add(_iid)
    by_id[_iid] = (mk, [norm(c.group(1)) for c in CHECK_RE.finditer(body)])
    # ⊘ несёт «Вердикт», а не команду — проверять там нечего по устройству. Набор
    # «сделано» — из библиотеки: ☑ судится по зелени, ⊘ пропускается.
    # МЕТКА СУДИТСЯ ДО ОТСЕЧКИ ⊘ (прожарка 13 сентября 2026): отказ от работы с ослепшим
    # критерием — то же непроверенное утверждение, что и слепое ☑, а прежняя редакция
    # отсекала ⊘ строкой ниже и молчала о нём. Набор закрывающих меток — из библиотеки.
    if mk in done_marks and trusted and FORM_PROXY_RE.search(body):
        print(f"#CG_FORM {_iid}")
        form_ids.add(_iid)
    if not mk or mk not in (done_marks + open_marks) or mk == done_marks[1:2]:
        continue
    closed = mk == done_marks[0:1]
    # ВСЕ строки «Проверки», не первая: пункт с двумя строками судится всеми — иначе
    # красная вторая молча проезжала за зелёной первой (прожарка 31.08, атака adv6).
    # Якорь на НАЧАЛО СТРОКИ обязателен. 1 сентября 2026 архиватор отказался
    # переносить D244, предъявив командой строку `. Источников два: канонический (`:
    # в абзаце «Дефект» того же пункта стоял литерал `**Проверка.**` в обратных
    # кавычках — описание механизма, — и разбор взял СЛЕДУЮЩУЮ пару кавычек за команду.
    # Тот же регексп стоял в hooks/completion-gate.sh, то есть эта строка шла в `bash -c`
    # на каждом Stop. Корень: парсер контракта читал ДАННЫЕ как разметку. Контрактная
    # строка начинает строку файла (после отступа); то же сочетание в середине
    # предложения — цитата, и последствие у неё ровно одно: командой она не является.
    checks = list(CHECK_RE.finditer(body))
    if not checks:
        # У ☑ отсутствие строки — предмет архиватора (`backlog-archive.sh:265`
        # не переносит закрытый пункт без «Проверки»). У ОТКРЫТОГО второго рубежа нет:
        # архиватор открытых пунктов не касается по построению (`backlog-archive.sh:49`),
        # и требование контракта «у открытого обязана быть названная Проверка» оставалось без
        # исполнителя — пункт проходил молча (D291). Молчание здесь неотличимо от
        # «проверено, чисто» — тот же корень, что у #CG_UNCHECKED.
        # Недоверенный файл НЕ называется: его текст пришёл из cwd сессии, и печатать
        # чужие пункты значило бы пускать чужой markdown в своё сообщение (D244).
        if not closed and trusted:
            print(f"#CG_OPEN {_iid} (нет строки «Проверка»)")
            fired.append((_iid, "missing", ""))
        continue
    if not trusted:
        # Не исполняем и НЕ молчим: молчаливый пропуск неотличим от «проверено, чисто».
        untrusted += len(checks)
        continue
    for cm in checks:
        if closed and runs >= max_runs:
            partial = True   # подлежало проверке и не проверено — покрытие частичное
            break
        if not closed and time.monotonic() > deadline:
            partial = True
            # Пропуск НАЗЫВАЕТСЯ: молчаливый неотличим от «проверено, чисто».
            _uid = _iid
            if _uid not in unchecked:
                unchecked.append(_uid)
            break
        # Команда исполняется КАК ЕСТЬ: прежний " ".join(split()) склеивал многострочную
        # команду в другую (перенос — не пробел: `a=ok<NL>[ "$a" = ok ]` превращался в
        # env-присваивание для `[`) — bash переносы штатны, нормализация только в показе.
        cmd = cm.group(1).strip()
        # Неисполнимость отделяется ДО запуска и только у открытого пункта: у «не
        # запускается» и «запустилось и вернуло не 0» последствия разные, а коды
        # одинаковые, и у открытого пункта красное — норма, значит различить их иначе нечем.
        # `bash -n` не исполняет ничего. НАЗВАННЫЙ ПРЕДЕЛ: синтаксис ВНУТРИ `python3 -c`
        # он не видит, оттуда придёт rc=1, неотличимый от честной красной; и
        # отсутствующий файл/интерпретатор он тоже не ловит — это rc=127, который у
        # открытого пункта законен (команда про ещё не написанный скрипт).
        if not closed and subprocess.run(["bash", "-n", "-c", cmd],
                                         capture_output=True).returncode != 0:
            print(f"#CG_OPEN {_iid} (синтаксис): `{' '.join(cmd.split())[:110]}`")
            fired.append((_iid, "syntax", norm(cmd)))
            continue
        if closed:
            runs += 1
        else:
            runs_open += 1
        try:
            # маркер вложенности: команда «Проверки» может дойти до Stop-хука и его
            # исполнителей Проверок (архиватор, этот же гейт) — по маркеру они выходят
            # сразу, кольцо «гейт/архиватор → тест пункта → session-collector → …»
            # ограничено глубиной 1 (шторм 2026-09-01: 2225 процессов, load 16.5)
            rc = subprocess.run(["bash", "-c", cmd], capture_output=True,
                                cwd=os.path.dirname(os.path.abspath(path)) or ".",
                                env=dict(os.environ, BACKLOG_CHECKS_NESTED="1"),
                                timeout=timeout).returncode
        except Exception:
            rc = 125
        disp = " ".join(cmd.split())
        if closed and rc != 0:
            print(f"{_iid} (rc={rc}): `{disp[:110]}`")
        elif closed:
            verified.add((_iid, disp))
        elif not closed and rc == 0:
            print(f"#CG_OPEN {_iid} (зелёная у открытого): `{disp[:110]}`")
            fired.append((_iid, "green", disp))

# ── Носитель срабатываний канала #CG_OPEN и ИСХОД срабатывания (D264) ──────────────
# До 2 сентября 2026 канал выносил вердикт и не оставлял следа; носитель появился, но
# `outcome` писался `pending` навсегда — журнал знал, ЧТО сработало, и не знал, чем
# кончилось, и точность признака (то, чего ADR-011 требует ПЕРЕД отказом уровня 4) по
# нему не считалась. Исход проставляется здесь же, МЕХАНИЗМОМ, а не рукой, по ключу
# (файл, пункт, команда):
#   · пункт ☑ и его «Проверка» дала 0 в этом прогоне либо пункт уже унесён в
#     BACKLOG-archive.md (архиватор не переносит ☑ с красной) → confirmed: канал сказал
#     «мир починен, метка отстала», закрытие это подтвердило; команда при закрытии
#     переписана — тоже confirmed, с пометкой cmd_changed (D268: закрыт с новой командой);
#   · пункт открыт, а команды среди его строк «Проверки» больше нет → прибор переписали,
#     не мир: для рода «зелёная» это rewritten — ОТДЕЛЬНАЯ корзина, а не false. Сообщение
#     этого же канала (ниже) предписывает «перепиши её под сам дефект»; называть ложным
#     срабатыванием исполнение собственного предписания нельзя. Для рода «синтаксис» —
#     confirmed (строка не проверяла ничего, и её починили);
#   · пункт ⊘ → waived: в долю точности не входит;
#   · иначе — pending, до следующей правки файла.
# КООРДИНАТА ФАЙЛА в ключе обязательна: гейт разбирает ДВА бэклога (цикл выше), и оба
# бывают доверенными — второй приходит через CG_LOCAL_BACKLOG, то есть актом владельца.
# Без неё резолвер локального файла судил записи ГЛАВНОГО по своему тексту: проба
# 3 сентября 2026 — один D-номер в двух файлах, и записи главного получали исход ни за
# что (2 из 2 в фикстуре T6). Форма ключа взята у брата-здоровяка того же устройства:
# `hooks/backlog-touch-check.sh:130` несёт `_key="${_id}|${FILE}"` и симптома не имеет.
# Единица счёта — тройка (файл, пункт, команда), не Stop: файл перечитывается каждой
# границей хода, и в ветке #CG_OPEN кэш не пишется по построению; повторное срабатывание
# той же тройки записи не множит, а увеличивает `seen`. Один писатель на журнал (этот
# гейт), запись целиком через временный файл — архиватор журнала не касается.
# НАЗВАННЫЙ ПРЕДЕЛ: у признака нет носителя ЛОЖНОГО срабатывания. «Пункт открыт законно,
# а строка зелена по делу» механически неотличимо от «до закрытия ещё не дошли руки» —
# обе пары остаются pending, и видны они только числом `seen`. Значит доля по журналу
# считается по одной стороне, и называть её точностью пока нельзя. Условие снятия: у
# ложного появится носитель — вердикт владельца рядом со строкой либо
# `bash scripts/outcome.sh disproved` с ключом пары; тогда в словаре исходов оживёт
# `false`, который замер `open-check-precision` уже принимает, и знаменатель перестанет
# быть односторонним.
# Только ДОВЕРЕННЫЙ файл (D244): недоверенный не исполняется, значит и записать в журнал
# нечего, а сверять исходы с чужим файлом значило бы отдать чужому тексту право ставить
# confirmed/waived — подмена телеметрии. При ключе с координатой файла это ВТОРОЙ рубеж:
# чужой файл с тем же D-номером отсекается уже ключом, и прямая проба разницы не видит.
fired_log = os.environ.get("CG_FIRED_LOG", "")
if fired_log and trusted and (fired or os.path.exists(fired_log)):
    recs = []
    if os.path.exists(fired_log):
        # Строка без полей ключа не переживает перезапись файла. Прежняя форма писателя
        # (`{ts, session, fired, outcome}`) их не несла, то есть смена формы записи —
        # потеря старых строк. Она бесплатна ровно потому, что журнал на 3 сентября 2026
        # пуст: `ls ~/.claude/hooks/state | grep -c cg-open` → 0. Мигрировать нечего.
        for ln in open(fired_log, encoding="utf-8", errors="replace"):
            try:
                r = json.loads(ln)
                if isinstance(r, dict) and "item" in r and "cmd" in r:
                    recs.append(r)
            except Exception:
                pass
    apath = os.path.abspath(path)
    bykey = {(r.get("file"), r["item"], r["cmd"]): r for r in recs}
    ts = time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime())
    sid = os.environ.get("CG_SID", "unknown")
    changed = False
    for iid, kind, c in fired:
        prev = bykey.get((apath, iid, c))
        if prev is None:
            r = {"ts": ts, "session": sid, "file": apath, "item": iid, "kind": kind,
                 "cmd": c, "outcome": "pending", "seen": 1}
            recs.append(r)
            bykey[(apath, iid, c)] = r
            changed = True
        elif prev.get("outcome") == "pending":
            # Повтор той же тройки — не новая запись, а счёт: «висит и не двигается»
            # обязано быть видно числом, иначе pending неотличим от однократного.
            prev["seen"] = int(prev.get("seen", 1)) + 1
            changed = True
    archive = None   # читается лениво и один раз: пункт, которого в файле нет, ищется в архиве
    def in_archive(iid):
        global archive
        if archive is None:
            archive = {}
            ap = os.environ.get("CG_ARCHIVE_TEXT") or os.path.join(
                os.path.dirname(os.path.abspath(path)), "BACKLOG-archive.md")
            if ap and os.path.exists(ap):
                cur = None
                for ln in open(ap, encoding="utf-8", errors="replace"):
                    m = item_re.match(ln)
                    if m:
                        im = _id_of(ln)
                        cur = [_mark_of(ln), []] if im else None
                        if im:
                            archive[im] = cur   # последнее вхождение побеждает
                    elif re.match(r'^#{2,6} ', ln):
                        cur = None
                    elif cur is not None:
                        cur[1].append(ln)
            for k, v in archive.items():
                archive[k] = (v[0], [norm(c.group(1)) for c in CHECK_RE.finditer("".join(v[1]))])
        return archive.get(iid)
    for r in recs:
        if r.get("outcome") != "pending":
            continue
        # Резолвер судит ТОЛЬКО записи своего файла: см. «КООРДИНАТА ФАЙЛА» выше.
        if r.get("file") != apath:
            continue
        iid, c, kind = r["item"], r["cmd"], r.get("kind", "green")
        if iid in ambiguous_ids:
            continue   # номер у двух блоков: чья метка — неизвестно, необратимую запись не делаем
        # ЗАКРЫТИЕ, ОБЪЯВЛЕННОЕ СЛЕПЫМ, НЕ ПОДТВЕРЖДАЕТ НИЧЕГО (прожарка 13 сентября 2026).
        # В одном прогоне гейт клал в очередь «закрыт пункт, чья «Проверка» судит по форме»
        # и тут же ставил этому пункту `outcome=confirmed` — телеметрия точности признака
        # получала подтверждение от закрытия, которое сам гейт объявил несостоявшимся.
        # Это дословный повтор дефекта, чиненного здесь же 3 сентября 2026 (врезка ниже про
        # all_green): тогда подтверждение приходило от пункта с красной второй «Проверкой».
        # Исход остаётся pending до починки либо до честного закрытия прибором.
        if iid in form_ids:
            continue
        found = by_id.get(iid)
        if found is None:
            found = in_archive(iid)
            if found is None:
                continue
            mk, cmds = found
            if mk == done_marks[0:1]:
                r["outcome"] = "confirmed"; r["cmd_changed"] = c not in cmds
            elif mk == done_marks[1:2]:
                r["outcome"] = "waived"
            else:
                continue
        else:
            mk, cmds = found
            if mk == done_marks[0:1]:
                # ВСЕ команды пункта, а не своя. Пункт бывает многосоставным, и до
                # 3 сентября 2026 достаточно было зелени ОДНОЙ: гейт в том же прогоне
                # печатал «закрытие расходится со своим же критерием» и тут же ставил
                # `confirmed`. Телеметрия точности признака (ради неё D264 и строится)
                # получала подтверждение от закрытия, которое сама же объявила
                # несостоявшимся. Пустой список команд подтверждением не считается.
                all_green = bool(cmds) and all((iid, x) in verified for x in cmds)
                if not all_green:
                    continue   # закрыт, но зелены не все — дождёмся архива либо починки
                if c in cmds:
                    r["outcome"] = "confirmed"; r["cmd_changed"] = False
                else:
                    r["outcome"] = "confirmed"; r["cmd_changed"] = True
            elif mk == done_marks[1:2]:
                r["outcome"] = "waived"
            elif c in cmds:
                continue   # открыт, команда та же — исход ещё не наступил
            elif kind == "missing" and not cmds:
                continue   # строки как не было, так и нет — исход не наступил
            else:
                # Слово `rewritten` живёт ровно в одной роли — значением исхода; пометку
                # у ☑ с переписанной командой зовут `cmd_changed`, иначе читателю замера
                # пришлось бы различать `.rewritten == true` и `.outcome == "rewritten"`.
                r["outcome"] = "rewritten" if kind == "green" else "confirmed"
                r["cmd_changed"] = True
        r["resolved_ts"] = ts
        changed = True
    if changed:
        try:
            tmp = fired_log + ".tmp"
            with open(tmp, "w", encoding="utf-8") as fh:
                for r in recs:
                    fh.write(json.dumps(r, ensure_ascii=False) + "\n")
            os.replace(tmp, fired_log)
        except Exception:
            pass

# Статус-строка — второй сигнал канала. Без неё пустой stdout значил РАЗНОЕ:
# «проверено, чисто», «питон упал», «не дошли до пункта за лимитом» — и всё это
# кэшировалось зелёным (корень трёх атак прожарки 31.08). Кэшировать можно только
# явное «ok»; отсутствие статуса = сбой разбора, «partial» = не всё проверено.
if untrusted:
    print(f"#CG_UNTRUSTED {untrusted}")
if unchecked:
    # Канал отдельный от #CG_UNTRUSTED: там «не исполняли, потому что чужой файл»,
    # здесь «не успели». Причины разные, и лечатся они разным.
    print(f"#CG_UNCHECKED {' '.join(unchecked)}")
print("#CG_STATUS partial" if partial else "#CG_STATUS ok")
PY
)
    _st=$(printf '%s\n' "$_out" | grep '^#CG_STATUS ' | tail -1 | awk '{print $2}')
    _un=$(printf '%s\n' "$_out" | grep '^#CG_UNTRUSTED ' | tail -1 | awk '{print $2}')
    [ -n "${_un:-}" ] && SKIPPED="${SKIPPED:-0}" && SKIPPED=$((SKIPPED + _un)) && SKIPPED_FILE="$f"
    # Не успели — называем поимённо. Прежде это состояние знал только кэш.
    _unch=$(printf '%s\n' "$_out" | grep '^#CG_UNCHECKED ' | tail -1 | cut -d' ' -f2-)
    [ -n "${_unch:-}" ] && UNCHECKED="${UNCHECKED:+$UNCHECKED }$_unch" && UNCHECKED_FILE="$f"
    # Открытый пункт с не-красной проверкой — ОТДЕЛЬНЫЙ канал: «закрытие расходится с
    # критерием» и «у открытого прибор не о том» суть разные утверждения, и смешать их
    # значило бы обвинить пункт в том, чего страж не проверял.
    _open=$(printf '%s\n' "$_out" | grep '^#CG_OPEN ' | sed 's/^#CG_OPEN //' || true)
    _form=$(printf '%s\n' "$_out" | grep '^#CG_FORM ' | sed 's/^#CG_FORM //' | tr '\n' ' ' || true)
    _broken=$(printf '%s\n' "$_out" | grep '^#CG_BROKEN ' | tail -1 | awk '{print $2}' || true)
    # Служебные строки опознаются ПРЕФИКСОМ, а не перечнем имён (11 сентября 2026). Каналов
    # четыре, а вырезались три: `#CG_UNCHECKED` заведён позже и в список не попал — строка
    # протокола уходила владельцу как находка, в канал «закрытие расходится со своим же
    # критерием», и обвиняла пункты, которых страж НЕ ПРОВЕРЯЛ. Воспроизведено фикстурой из
    # двух ОТКРЫТЫХ пунктов: текст говорил про метку ☑, которой у них нет. Каждый канал уже
    # извлечён в свою переменную строками выше (`_st`, `_un`, `_unch`, `_open`), поэтому
    # правило по префиксу ничего не отнимает — и новый канал впредь не протечёт сам собой.
    _out=$(printf '%s\n' "$_out" | grep -v '^#CG_' | grep -v '^$' || true)
    [ -n "$_open" ] && OPENBAD="${OPENBAD}${OPENBAD:+
}$_open"
    [ -n "$_form" ] && FORMBAD="${FORMBAD:+$FORMBAD }$_form"
    [ -n "${_broken:-}" ] && BROKEN="${_broken}" && BROKEN_FILE="$f"
    if [ -n "$_out" ]; then
        RED="${RED}${RED:+
}$_out"
    elif [ "$_st" = "ok" ] && [ -n "$_mt" ] && [ -z "$_open" ]; then
        # Зелёный кэш пишется ТОЛЬКО на явном «ok»: сбой питона (нет статуса) и
        # частичное покрытие («partial», ☑-пунктов с командой больше CG_MAX) кэша
        # не получают — файл перечитается следующим Stop, а неотвратимость держит
        # архиватор, у которого лимита нет.
        # `-z "$_open"` обязателен: канал #CG_OPEN вырезан из $_out строкой выше, и без
        # этого условия файл, чья единственная беда — зелёная у открытого, получал бы
        # зелёный кэш и предупреждение звучало бы РОВНО ОДИН раз. Это тот самый класс
        # ложного зелёного кэша, что закрывали 31.08 тремя атаками прожарки. У открытого
        # пункта архиватор второго рубежа не даёт — напоминание каждый Stop и есть
        # единственная неотвратимость.
        printf '%s\n' "$_mt" > "$OKF" 2>/dev/null || true
    fi
done

# ── Свежий ☐ ждёт взятия (12 сентября 2026, план разгребания долга) ──────────────────
# Правило «находка по ходу заводится отдельным пунктом» имело пару только на словах: пункт
# заводился, а брать его никто не был обязан, и долг рос по пункту на починку (43 открытых
# к 12 сентября). Механизм: пункт, ЗАВЕДЁННЫЙ В ЭТОЙ СЕССИИ — его нет в снимке старта
# (`backlog_snapshot`, пишет session-start) — и всё ещё ☐, при том что взятых В ЭТОЙ ЖЕ
# сессии ◐ не осталось (текущая починка закрыта), называется в очередь: по правилу он
# берётся сейчас. Пока взятый в сессии ◐ жив — молчание. Ожидание (команда возврата) свежим
# не считается: его закрывает событие, а не руки.
# Замер ДО кода опроверг первую редакцию «нет ни одного ◐»: на всех 60 последних коммитах
# бэклога ◐ ровно два (D264, D282 — десять дней), страж родился бы мёртвым. Поэтому
# сравниваются ◐ ТЕКУЩЕЙ сессии: ◐ сейчас минус ◐ в снимке.
# ДВА НАЗВАННЫХ ПРЕДЕЛА. (1) Работа над ◐, взятым до старта сессии, невидима — текст просит
# поставить ◐ текущей работе; условие снятия — поле «взят когда» у ◐. (2) Пункт соседней
# сессии, заведённый после моего старта, выглядит моим; сужение через rc_outcome_observed
# (запись в бэклог в действиях ЭТОГО хода) — отдельным пунктом долга.
# Ключ дросселя — состав «свежие|закрытые с начала сессии»: закрытие ещё одного пункта при
# лежащем свежем — новое состояние мира, и оно звучит заново; повтор состава молчит.
# Снимка нет (первый Stop до старта с новой библиотекой) — он создаётся здесь, и этот ход
# молчит: судить «свежесть» без точки отсчёта нельзя.
_cg_fresh=""; _cg_wips=""; _cg_closed=""
if command -v backlog_snapshot >/dev/null 2>&1 && command -v backlog_open_items >/dev/null 2>&1; then
    for _ff in "$BACKLOG" "$LOCAL_BACKLOG"; do
        [ -n "$_ff" ] && [ -f "$_ff" ] || continue
        _snap=$(backlog_snapshot "$STATE" "${_cg_sid:-unknown}" "$_ff" 2>/dev/null); _src=$?
        [ "$_src" -eq 0 ] && [ -n "$_snap" ] || continue
        _todo=$(backlog_ids "$_ff" "$BACKLOG_MARK_TODO")
        _wip=$(backlog_ids "$_ff" "$BACKLOG_MARK_WIP")
        _seen=$(awk 'NF { print $1 }' "$_snap" | sort -u)
        _open0=$(awk -v t="$BACKLOG_MARK_TODO" -v w="$BACKLOG_MARK_WIP" '$2 == t || $2 == w { print $1 }' "$_snap" | sort -u)
        _wip0=$(awk -v w="$BACKLOG_MARK_WIP" '$2 == w { print $1 }' "$_snap" | sort -u)
        _wait=$(backlog_open_items "$_ff" 2>/dev/null | awk -F'\t' '$3 == "cmd" { print $1 }' | sort -u)
        _cg_fresh="$_cg_fresh $(comm -23 <(printf '%s\n' "$_todo" | grep -v '^$' | sort -u) <(printf '%s\n%s\n' "$_seen" "$_wait" | grep -v '^$' | sort -u) | tr '\n' ' ')"
        _cg_wips="$_cg_wips $(comm -23 <(printf '%s\n' "$_wip" | grep -v '^$' | sort -u) <(printf '%s\n' "$_wip0" | grep -v '^$' | sort -u) | tr '\n' ' ')"
        _cg_closed="$_cg_closed $(comm -23 <(printf '%s\n' "$_open0" | grep -v '^$' | sort -u) <(printf '%s\n%s\n' "$_todo" "$_wip" | grep -v '^$' | sort -u) | tr '\n' ' ')"
    done
fi
_cg_fresh=$(printf '%s' "$_cg_fresh" | tr -s ' ' | sed 's/^ //; s/ $//')
_cg_closed=$(printf '%s' "$_cg_closed" | tr -s ' ' | sed 's/^ //; s/ $//')
if [ -n "$_cg_fresh" ] && [ -z "$(printf '%s' "$_cg_wips" | tr -d ' ')" ]; then
    for _cg_thr in "$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" 2>/dev/null && pwd)/throttle-lib.sh" \
                   "$HOME/.claude/hooks/throttle-lib.sh"; do
        # shellcheck source=/dev/null
        [ -f "$_cg_thr" ] && { . "$_cg_thr"; break; }
    done
    _fk="fresh:$(printf '%s' "$_cg_fresh" | tr ' ' ',')|closed:$(printf '%s' "$_cg_closed" | tr ' ' ',')"
    _fresh_go=1
    if command -v throttle_file >/dev/null 2>&1; then
        _ft=$(throttle_file "$STATE" backlog-fresh "${_cg_sid:-unknown}")
        throttle_seen "$_ft" "$_fk" && _fresh_go=0
        [ "$_fresh_go" -eq 1 ] && throttle_mark "$_ft" "$_fk"
    fi
    if [ "$_fresh_go" -eq 1 ]; then
        printf '📋 Заведённые в этой сессии пункты ждут взятия: %s. Взятых в этой сессии %s нет%s. По правилу находка по ходу берётся СРАЗУ за текущей починкой: переведи в %s, назови Результат и Проверку, почини, закрой %s с показанием. Если текущая работа ещё идёт и она пункт долга — поставь ей %s, напоминание умолкнет до её закрытия. Пункт-ожидание (Проверка возврата командой) сюда не входит.\n' \
            "$_cg_fresh" "$BACKLOG_MARK_WIP" "${_cg_closed:+; закрыты с начала сессии: $_cg_closed}" "$BACKLOG_MARK_WIP" "$BACKLOG_MARK_DONE" "$BACKLOG_MARK_WIP" \
            >> "$STATE/pending-alerts.txt" 2>/dev/null || true
    fi
fi

MSG=""
_join() { [ -n "$MSG" ] && MSG="${MSG}

"; MSG="${MSG}$1"; }

if [ -n "$RED" ]; then
    _join "⚠️ completion-gate: закрытие расходится со своим же критерием:
$RED
Метку ☑ держит команда пункта, а не отчёт. Исполнимо без разрешения: почини мир до зелёной команды либо верни метке ${BACKLOG_MARK_WIP} — красное ☑ архиватор не унесёт."
fi

if [ -n "$BROKEN" ]; then
    _join "⚠️ completion-gate: разбор не увидел НИ ОДНОГО пункта, хотя в файле их ${BROKEN} (файл $BROKEN_FILE).
Это не «проверено, чисто» — это «посмотреть не удалось». Обычная причина одна: незакрытый
забор кода (\`\`\`) гасит весь остаток файла, и ни одно закрытие под ним не судится ничем.
Исполнимо без разрешения: закрой забор либо найди, где разметка съедает пункты."
fi

if [ -n "$FORMBAD" ]; then
    _join "⚠️ completion-gate: закрыт пункт, чья «Проверка» судит по форме: ${FORMBAD}
Его же «Зелёная сторона» помечена «судит по форме»: команда зеленеет от ИМЕНИ файла или
СЛОВА в тексте, а не от результата работы. Зелёный код тут доказывает, что кто-то написал
имя, — не что мир стал таким, как объявлено. Закрыть такой пункт вправе только прибор.
Исполнимо без разрешения: замени команду «Проверки» на ту, что меряет результат, и сними
метку; либо верни метке пункта ${BACKLOG_MARK_WIP}. Помеченное ☑ архиватор не унесёт."
fi

if [ -n "$OPENBAD" ]; then
    _join "⚠️ completion-gate: «Проверка» ОТКРЫТОГО пункта не красная:
$OPENBAD
У открытого пункта проверка обязана быть исполнимой и КРАСНОЙ. Зелёная значит одно из двух,
и оба дефект: проблема уже решена — закрой пункт с показанием; либо команда не о ней —
перепиши её под сам дефект и назови рядом, почему прибор менялся. «Синтаксис» значит, что
строка не проверяет ничего. «Нет строки «Проверка»» значит, что машинного критерия у
пункта нет вовсе: напиши строку, красную сегодня, — у открытого пункта архиватор второго
рубежа не даёт. Пункт бывает многосоставным: зелень ОДНОЙ из двух строк
«Проверка» готовности не доказывает. Исполнимо без разрешения."
fi

# Не успели в бюджет — тоже отдельный канал. Молчание здесь неотличимо от «чисто»,
# а именно на этом молчании десять пунктов-родов не проверялись ни разу (6 сентября 2026).
if [ -n "${UNCHECKED:-}" ]; then
    _join "ℹ️ completion-gate: «Проверка» не проверена, не хватило бюджета: ${UNCHECKED} (файл $UNCHECKED_FILE).
Это НЕ «проверено, чисто» — это «не смотрели». Исполнимо без разрешения: подними
CG_BUDGET_OPEN либо разберись, почему команда пункта стала дорогой."
fi

# Пропуск по недоверию — отдельный канал: это не «закрытие разошлось с критерием»,
# а «критерий не исполнялся, и вот почему». Смешать их значило бы обвинить пункт в том,
# чего страж не проверял.
if [ -n "${SKIPPED:-}" ] && [ "${SKIPPED:-0}" -gt 0 ]; then
    _join "ℹ️ completion-gate: «Проверок» не исполнено: ${SKIPPED} (файл $SKIPPED_FILE).
Путь бэклога пришёл из cwd сессии, а команда «Проверки» исполняется через bash. Чужой
репозиторий с ☑-пунктом исполнил бы свою строку на первом Stop (D244). Исполнимо без
разрешения: если бэклог свой — назови его явно, CG_LOCAL_BACKLOG=<путь>."
fi

[ -n "$MSG" ] || exit 0

# Канал доставки. `systemMessage` на Stop до хода не доходит — измерено внутри системы
# (`hooks/error-tracker.sh:44-47`: 15 срабатываний, ход не отреагировал ни на одно), а в
# VSCode-расширении он не рендерится вовсе. Прямой `additionalContext` здесь незаконен:
# непустой контекст на Stop перезапускает ход. Поэтому — общая очередь, которую показывает
# `pending-alerts-surface.sh` на следующем UserPromptSubmit, и дроссель по СОСТАВУ
# расхождения (какие пункты и какого знака), а не по телу сообщения: «красных стало 4
# вместо 3» звучать не должно, «покраснел пункт, который был зелёным» — обязано.
# systemMessage снят 12 сентября 2026 по той же причине, что у свода и канарейки: в
# мобильном клиенте канал рендерится построчно, и перечень пунктов разворачивался в простыню.
# Доставка остаётся одна — очередь ниже, её показывает pending-alerts-surface.
for _cg_thr in "$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" 2>/dev/null && pwd)/throttle-lib.sh" \
               "$HOME/.claude/hooks/throttle-lib.sh"; do
    # shellcheck source=/dev/null
    [ -f "$_cg_thr" ] && { . "$_cg_thr"; break; }
done
# Состав: перечень задетых пунктов из самого сообщения. Их номера и есть состояние мира;
# текст вокруг них меняется от прогона к прогону и ключом быть не может.
# Состав — пункты И КАНАЛ, которым они названы. До 13 сентября 2026 ключ нёс только номера,
# при том что комментарий выше требовал «какие пункты и какого ЗНАКА». Прожарка того дня
# показала цену на двух естественных ходах: (1) открытый пункт с зелёной «Проверкой» назван
# на первом Stop, на втором он же закрыт слепой командой — состав мира изменился, ключ нет,
# и про слепое закрытие не сказано НИЧЕГО; (2) красная «Проверка» починена, метка оставлена —
# оставшаяся находка не доставлена. Знак берётся из значков самих каналов в сообщении.
_cg_ids() { printf '%s' "${1:-}" | grep -oE '\bD[0-9]+\b' 2>/dev/null | sort -u | tr '\n' ','; }
_cg_compose=$( { [ -n "$RED" ]     && printf 'closed-red:%s;'  "$(_cg_ids "$RED")"
                 [ -n "$OPENBAD" ] && printf 'open-not-red:%s;' "$(_cg_ids "$OPENBAD")"
                 [ -n "$FORMBAD" ] && printf 'closed-form:%s;'  "$(_cg_ids "$FORMBAD")"
                 # Каналы «не проверено» и «не исполнено» — тоже состав расхождения: их
                 # пункты входили в прежний ключ через общий грep по сообщению, и без них
                 # состав схлопывается (поймано ногой T6a в тот же час: сообщение с красным
                 # ☑ и пропуском получало тот же ключ, что одно красное ☑, и гасло).
                 [ -n "${UNCHECKED:-}" ] && printf 'unchecked:%s;' "$(_cg_ids "$UNCHECKED")"
                 [ -n "${SKIPPED:-}" ] && [ "${SKIPPED:-0}" -gt 0 ] && printf 'skipped:%s;' "$SKIPPED"
                 [ -n "$BROKEN" ] && printf 'broken:%s;' "$BROKEN"
                 :; } )
[ -n "$_cg_compose" ] || _cg_compose=$(printf '%s' "$MSG" | cksum 2>/dev/null | awk '{print $1}')
if command -v throttle_file >/dev/null 2>&1; then
    _cg_tf=$(throttle_file "$STATE" completion-gate "${_cg_sid:-unknown}")
    throttle_seen "$_cg_tf" "$_cg_compose" && exit 0
    throttle_mark "$_cg_tf" "$_cg_compose"
fi
printf '%s\n' "$MSG" >> "$STATE/pending-alerts.txt" 2>/dev/null || true
exit 0
