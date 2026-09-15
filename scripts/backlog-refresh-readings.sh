#!/usr/bin/env bash
# backlog-refresh-readings.sh — показание открытого пункта считается заново, а не помнится.
#
# Результат: у каждого открытого пункта, объявившего команду показания, строка
#            «Последнее показание» отражает НЫНЕШНЕЕ состояние мира, а не момент записи
# Проверка результата: bash scripts/backlog-refresh-readings.sh --check даёт 0, когда ни
#            одно показание не разошлось с выводом своей команды
#
# Зачем. Показание пункта было прозой: число вписывалось рукой в момент, когда пункт
# писали, и устаревало в ту же секунду. Замер 30 августа 2026, 00:23: D206 утверждал
# «накоплено 13 записей исходов», фактически их было 19 — расхождение прожило два часа и
# нашлось вопросом собеседника, а не механизмом. Условие возврата пункта при этом ссылается
# ИМЕННО на это число («открыт, пока нет ≥20»), то есть решение о закрытии принималось бы
# по устаревшей величине.
#
# ПОЧЕМУ НЕ «ОБНОВЛЯТЬ ВНИМАТЕЛЬНЕЕ». Это уровень 1 укоренённости, в проекте признанный
# описанием проблемы, а не решением: число, которое надо помнить обновить, не обновляют.
#
# КОГДА ПЕРЕСЧИТЫВАЕТСЯ (D210). Событие — не «файл изменён», а граница хода: показание
# утверждает о мире, который меняется независимо от файла (журнал исходов пополняется каждым
# ходом), и 30 августа 2026 в 01:14 показание устарело через 50 минут ПОСЛЕ введения
# пересчёта по правке — бэклог с тех пор не трогали. Теперь `hooks/session-collector.sh`
# зовёт `run` на каждом Stop, `hooks/backlog-reading-refresh.sh` — по правке файла и сверяет
# при чтении агентом. Команда показания исполняется на каждом Stop; предел — 120 с на
# команду, медленная команда задержит каждый ход.
#
# ОТКАЗ ВМЕСТО ПОРЧИ (D355, 13 сентября 2026). 7 сентября пересчёт съел хвост файла — целый
# пункт D354 — рядом с показанием-ошибкой у соседа; повод воспроизвести не удалось. Теперь запись
# собирается из блоков по смещениям (без `str.replace` по документу), а перед записью проверяется
# ПОСТУСЛОВИЕ: вне строк «Последнее показание» вывод совпадает со входом — иначе отказ кодом 2 с
# номером первой разницы, и файл не трогается. Отказавшая команда пишется маркером
# «НЕ ИЗМЕРЕНО: …» без текста исключения (скобки и кавычки в файл не попадают); срок команды —
# READING_TIMEOUT (по умолчанию 120 с).
#
# MTIME СОХРАНЯЕТСЯ. Сверщик исхода хода (`declared-problem-recorded.sh`) судит «агент
# записал что-то в носитель» по mtime BACKLOG.md; пересчёт — не запись агента, и bump mtime
# подделал бы `none` → `recorded` на каждом ходе, где показание сдвинулось. Ставится прежнее
# mtime с наносекундами (`os.utime(..., ns=...)`).
# НАЗВАННЫЙ ПРЕДЕЛ: git замечает такую правку по ctime — только при `core.trustctime=true`
# (умолчание) и когда ctime попал в другую секунду, чем запись в индексе; при
# `trustctime=false` `git add` молча пропустит файл. Инструмент Edit не увидит пересчёт
# между Read и Edit; запись по устаревшему содержимому лечится тем же хуком на Write/Edit.
# Условие снятия: сверщик исхода станет отличать запись агента от механической по
# СОДЕРЖИМОМУ носителя (снимок без строк показаний), а не по mtime, — тогда прятать mtime
# будет незачем, и предел уйдёт вместе с приёмом.
#
# ФОРМА. Пункт объявляет источник строкой
#     **Показание.** `команда`
# и получает строку `**Последнее показание (дата).**` — её и переписывает этот скрипт. Дата
# в строке означает, КОГДА ЗНАЧЕНИЕ ИЗМЕНИЛОСЬ: сравнивается значение, а не строка целиком,
# иначе переход через полночь делал бы каждое показание «устаревшим» и счётчик устаревших
# чтений (D210) врал бы каждым утром. Пункт без `**Показание.**` не трогается: у части
# пунктов показание есть суждение, а не число, и заставлять их выражаться командой значило
# бы врать точностью.
#
# КОНТРПРИМЕР: закрытые пункты (☑ ⊘) не обновляются — они уезжают в архив как свидетельство
# состояния НА МОМЕНТ закрытия; переписать их показание значило бы подделать свидетельство.
set -uo pipefail

MODE="${1:-run}"          # run — переписать; --check — только сказать, что разошлось

# Режим сверяется с перечнем: неизвестное значение НЕ означает умолчание. До 1 сентября
# 2026 `MODE="${1:-run}"` не различал «не указан» и «указан неверно», и любой аргумент
# мимо перечня выполнял разрушительную ветку. Замер на фикстуре: из пяти написаний
# (`check`, `--check`, `--bogus`, пусто, `run`) перенос выполняли ЧЕТЫРЕ — то есть просьба
# проверить меняла файл. Имена режима у соседей разошлись (`check` у архиватора и
# measurement-due, `--check` у пересчётчика показаний и сверки чисел), поэтому принимаются
# оба написания, а всё прочее отбивается кодом 2.
case "$MODE" in
    run|--run)     MODE=run ;;
    check|--check) MODE=--check ;;
    *) echo "применение: $(basename "$0") [run|check]" >&2; exit 2 ;;
esac

REPO="${CLAUDSOUL_REPO:-$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")/.." 2>/dev/null && pwd -P)}"
BACKLOG="${BACKLOG_FILE:-$REPO/BACKLOG.md}"
[ -f "$BACKLOG" ] || { echo "нет $BACKLOG" >&2; exit 0; }
command -v python3 >/dev/null 2>&1 || { echo "backlog-refresh-readings: нужен python3 — не измерено" >&2; exit 2; }

# Правка под замком (род H). BACKLOG.md пишут трое: этот скрипт, `scripts/backlog-archive.sh`
# и `hooks/completion-gate.sh`, и первые двое зовутся из `session-collector` на границе хода —
# то есть при параллельных сессиях сходятся во времени. Блок ниже читает файл целиком
# (`path.read_text`) и кладёт обратно целиком (`path.write_text`): окно read→write открыто, и
# при наложении часть пересчитанных показаний гибнет молча. Замок берётся на сам BACKLOG.md,
# а не на каталог: писателей у файла трое, у каталога — весь проект.
STATE_LOCK_LIB="${STATE_LOCK_LIB:-$REPO/hooks/state-lock-lib.sh}"
[ -f "$STATE_LOCK_LIB" ] || STATE_LOCK_LIB="$HOME/.claude/hooks/state-lock-lib.sh"
# shellcheck source=/dev/null
[ -f "$STATE_LOCK_LIB" ] && . "$STATE_LOCK_LIB"
# Библиотеки нет — работаем как прежде: замок улучшает, а его отсутствие не должно ронять.
command -v with_lock >/dev/null 2>&1 || with_lock() { shift; "$@"; }

# Признак пункта — из общей библиотеки (D305). Здесь стояла своя копия `item_rx`, и это
# ПИСАТЕЛЬ файла: у писателя ложное опознание пункта дороже, чем у читателя — он правит
# чужие строки. Забор кода снимается тем же механизмом, что у остальных; текст со снятым
# забором подаётся ОТДЕЛЬНЫМ файлом, потому что запись идёт по смещениям ОРИГИНАЛА.
BL_LIB="${BL_LIB:-$REPO/hooks/backlog-lib.sh}"
[ -f "$BL_LIB" ] || BL_LIB="$HOME/.claude/hooks/backlog-lib.sh"
# shellcheck source=/dev/null
{ [ -f "$BL_LIB" ] && . "$BL_LIB"; } || { echo "нет hooks/backlog-lib.sh — признак пункта брать неоткуда" >&2; exit 2; }
command -v backlog_item_re >/dev/null 2>&1 || { echo "библиотека без backlog_item_re" >&2; exit 2; }
BACKLOG_ITEM_RE="$(backlog_item_re)"
BACKLOG_MARKS_ALT="$(backlog_marks_alt "${BACKLOG_DONE_MARKS}${BACKLOG_OPEN_MARKS}")"
_BL_STRIPPED=$(mktemp) || exit 2
trap 'rm -f "$_BL_STRIPPED"' EXIT
backlog_strip_fenced < "$BACKLOG" > "$_BL_STRIPPED" 2>/dev/null || cp -f "$BACKLOG" "$_BL_STRIPPED"
export BACKLOG_ITEM_RE BACKLOG_ID_TOKEN_RE BACKLOG_MARKS_ALT BACKLOG_DONE_MARKS

with_lock "$BACKLOG" env BACKLOG_FILE="$BACKLOG" REPO_DIR="$REPO" MODE="$MODE" \
    BACKLOG_STRIPPED="$_BL_STRIPPED" python3 - <<'PY'
import os, re, subprocess, sys, pathlib, datetime

path = pathlib.Path(os.environ["BACKLOG_FILE"])
repo = os.environ["REPO_DIR"]
mode = os.environ["MODE"]
text = path.read_text(errors="replace")

# Блок пункта: от заголовка до следующего заголовка пункта. Признак — из библиотеки, и
# строки внутри забора кода пунктом не считаются: их снял `backlog_strip_fenced`.
# Начала блоков ищутся в тексте БЕЗ забора, а смещения берутся в ОРИГИНАЛЕ: снятие
# забора сохраняет число строк (строка внутри становится пустой), но не длины, а запись
# идёт по оригиналу.
item_rx = re.compile(os.environ["BACKLOG_ITEM_RE"])
mark_rx = re.compile(os.environ["BACKLOG_MARKS_ALT"])
id_rx = re.compile(os.environ["BACKLOG_ID_TOKEN_RE"])
done_marks = os.environ["BACKLOG_DONE_MARKS"]
_stripped = pathlib.Path(os.environ["BACKLOG_STRIPPED"]).read_text(errors="replace") \
    if os.environ.get("BACKLOG_STRIPPED") else text
_orig_lines = text.splitlines(True)
_offsets, _pos = [], 0
for _ln in _orig_lines:
    _offsets.append(_pos); _pos += len(_ln)
starts = [_offsets[i] for i, _ln in enumerate(_stripped.splitlines(True))
          if i < len(_offsets) and item_rx.match(_ln)]
starts.append(len(text))

# Строка показания: дата в скобках, затем значение. Значение берётся группой, а не
# «всё после последних **»: жадный `[^\n]*\*\*` резал бы строку по `**` внутри значения.
last_rx = re.compile(r'^[ \t]*\*\*Последнее показание[^*]*\*\*[ \t]*(.*)$', re.M)

changed, stale, stale_rows = 0, [], []
seen, open_items = 0, 0

def ident_of(h):
    # Идентификатор — первый токен «буквы + номер» ЦЕЛИКОМ, разметка снята: правило
    # `backlog_id_stream`, а не «первый D-номер строки» (тот брал чужой номер из ссылки).
    m = id_rx.search(h.replace("*", ""))
    return m.group(0) if m else '?'
TO = int(os.environ.get("READING_TIMEOUT", "120") or 120)

def _clean(t):  # текст ошибки в файл — без разметки и кавычек, одной строкой
    return " ".join(t.replace("`", "").replace("*", "").replace('"', "").replace("'", "").split())

pieces = []
for i in range(len(starts) - 1):
    block = text[starts[i]:starts[i + 1]]
    pieces.append(block)
    head = block.split("\n", 1)[0]
    # Закрытые не трогаем: их показание — свидетельство на момент закрытия. Статусная
    # метка — ПЕРВАЯ в строке (правило `backlog_status_is`), а не «встретилась где-то»:
    # заголовок законно несёт вторую метку в скобках.
    _mk = mark_rx.search(head)
    if _mk and _mk.group(0) in done_marks:
        continue
    open_items += 1
    m = re.search(r'^[ \t]*\*\*Показание\.\*\*\s*`([^`]+)`', block, re.M)
    if not m:
        continue
    seen += 1
    cmd = m.group(1)
    ident = ident_of(head)
    # САМОПРИМЕНЕНИЕ ЗАПРЕЩЕНО. Команда показания, вызывающая этот же пересчётчик,
    # получает в вывод строку про свой собственный пункт — и показание заполняется
    # рекурсивным мусором. Поймано на себе 30 августа 2026 в первую же минуту после
    # введения формы: показание D210 стало «· D210: · D210: · D210: …». Показание обязано
    # быть ЧИСТЫМ наблюдением мира, а не отражением работы того, кто его записывает.
    if "backlog-refresh-readings" in cmd:
        stale.append(f"{ident}: команда показания вызывает сам пересчётчик — "
                     f"самоприменение, показание пропущено")
        continue
    try:
        r = subprocess.run(["bash", "-c", cmd], cwd=repo, capture_output=True,
                           text=True, timeout=TO)
        # Строки склеиваются, а не берётся последняя. `[-1]` стоял здесь с первого
        # коммита механизма (2171fef): все показания той поры были однострочными
        # (`wc -l`, `grep -c`), и выбор не был решением о многострочном выводе.
        # Замер 1 сентября 2026: показание D247 — `jq … | sort | uniq -c`, четыре строки;
        # `[-1]` записал бы в файл «1 outdated_knowledge», выдав ХВОСТ распределения за
        # всё распределение. Обрыв опаснее ошибки: строка выглядит настоящим показанием.
        # `r.stderr` берётся только когда stdout ПУСТ, и тогда это не показание, а текст
        # ошибки — выдавать его за значение нельзя: строка «Последнее показание» получила бы
        # вид настоящего замера. Ненулевой код сам по себе поводом не является: команда
        # показания законно возвращает 1, когда находит (`injection-outcome.sh` при доле выше
        # порога), — поэтому признак составной: код ненулевой И stdout пуст.
        _out = (r.stdout or "").strip()
        if not _out and r.returncode != 0:
            value = f"НЕ ИЗМЕРЕНО: команда упала (rc={r.returncode}): " + _clean(r.stderr or "")[:120]
        else:
            value = " · ".join(x.strip() for x in (_out or (r.stderr or "")).strip().split("\n")
                               if x.strip())[:200]
    except subprocess.TimeoutExpired:
        value = f"НЕ ИЗМЕРЕНО: команда не уложилась в срок {TO} с"
    except Exception as e:
        value = f"НЕ ИЗМЕРЕНО: команда не выполнилась ({type(e).__name__})"
    stamp = datetime.date.today().isoformat()
    # Отступ наследуется от строки «Показание.» того же пункта. Пункт — элемент списка,
    # и строка в колонке 0 из него выпадает: замер 1 сентября 2026 — вставка встала между
    # пунктами как самостоятельный абзац.
    indent = re.match(r'[ \t]*', m.group(0)).group(0)
    line = f"{indent}**Последнее показание ({stamp}).** {value}"

    old = last_rx.search(block)
    old_value = old.group(1).strip() if old else None
    if old_value == value.strip():
        continue
    stale.append(f"{ident}: в файле «{old_value if old_value is not None else '—'}», в мире «{value}»")
    stale_rows.append((ident, old_value if old_value is not None else "", value))
    if mode != "--check":
        # Хвост блока сохраняется: `rstrip()` съедал пустую строку-разделитель перед
        # следующим пунктом, и два пункта слипались в один абзац.
        tail = block[len(block.rstrip()):] or "\n"
        new_block = (block[:old.start()] + line + block[old.end():]) if old \
                    else block.rstrip() + "\n" + line + tail
        pieces[-1] = new_block
        changed += 1

out = text[:starts[0]] + "".join(pieces)
# ПОСТУСЛОВИЕ (D355): пересчёт меняет только строки «Последнее показание». Любая другая разница —
# отказ без записи: так съеденный хвост становится громким событием с адресом, а не пропажей.
def _keep(t):
    return [l for l in t.split("\n") if not re.match(r'[ \t]*\*\*Последнее показание', l)]
_a, _b = _keep(text), _keep(out)
if _a != _b:
    _k = next((j for j in range(min(len(_a), len(_b))) if _a[j] != _b[j]), min(len(_a), len(_b)))
    print(f"ОТКАЗ: пересчёт изменил бы строки вне показаний (вне показаний было {len(_a)} строк, "
          f"стало {len(_b)}; первая разница у строки {_k + 1}: «{(_a[_k] if _k < len(_a) else '—')[:80]}») "
          f"— файл не записан", file=sys.stderr)
    sys.exit(2)

if mode == "--check":
    if stale:
        print("показания разошлись с миром:")
        for s in stale:
            print(f"  · {s}")
        # Журнал устаревших ЧТЕНИЙ (D210): хук на чтении передаёт путь через STALE_JOURNAL,
        # и каждое расхождение ложится строкой — величина «сколько раз показание прочитано
        # устаревшим» считается здесь, где известны и файл, и мир, а не разбором текста.
        journal = os.environ.get("STALE_JOURNAL")
        if journal:
            import json
            ts = datetime.datetime.utcnow().strftime("%Y-%m-%dT%H:%M:%SZ")
            with open(journal, "a") as jf:
                for ident, old_value, value in stale_rows:
                    jf.write(json.dumps({"ts": ts, "item": ident, "file": old_value,
                                         "world": value, "path": str(path)},
                                        ensure_ascii=False) + "\n")
        sys.exit(1)
    print(f"все показания открытых пунктов свежие (осмотрено {seen} из {open_items} открытых)")
    sys.exit(0)

if changed:
    st = path.stat()
    path.write_text(out)
    # Пересчёт — не запись агента: mtime возвращается, чтобы сверщик исхода хода не счёл
    # его «носитель изменился» (см. шапку). ctime при этом меняется — git правку видит.
    os.utime(path, ns=(st.st_atime_ns, st.st_mtime_ns))
    print(f"показаний обновлено: {changed}")
    for s in stale:
        print(f"  · {s}")
else:
    print("обновлять нечего: показания свежие либо команд показания нет")
PY
