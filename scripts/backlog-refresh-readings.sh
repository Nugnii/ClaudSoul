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
REPO="${CLAUDSOUL_REPO:-$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")/.." 2>/dev/null && pwd -P)}"
BACKLOG="${BACKLOG_FILE:-$REPO/BACKLOG.md}"
[ -f "$BACKLOG" ] || { echo "нет $BACKLOG" >&2; exit 0; }
command -v python3 >/dev/null 2>&1 || { echo "нужен python3" >&2; exit 0; }

BACKLOG_FILE="$BACKLOG" REPO_DIR="$REPO" MODE="$MODE" python3 - <<'PY'
import os, re, subprocess, sys, pathlib, datetime

path = pathlib.Path(os.environ["BACKLOG_FILE"])
repo = os.environ["REPO_DIR"]
mode = os.environ["MODE"]
text = path.read_text(errors="replace")

# Блок пункта: от заголовка до следующего заголовка пункта.
item_rx = re.compile(r'^(?:- |#{2,6} )[^\n|]*[☐◐☑⊘].*$', re.M)
starts = [m.start() for m in item_rx.finditer(text)]
starts.append(len(text))

# Строка показания: дата в скобках, затем значение. Значение берётся группой, а не
# «всё после последних **»: жадный `[^\n]*\*\*` резал бы строку по `**` внутри значения.
last_rx = re.compile(r'^\*\*Последнее показание[^*]*\*\*[ \t]*(.*)$', re.M)

changed, stale, stale_rows = 0, [], []

def ident_of(h):
    m = re.search(r'D\d+', h)
    return m.group(0) if m else '?'
out = text
for i in range(len(starts) - 1):
    block = text[starts[i]:starts[i + 1]]
    head = block.split("\n", 1)[0]
    # Закрытые не трогаем: их показание — свидетельство на момент закрытия.
    if "☑" in head or "⊘" in head:
        continue
    m = re.search(r'^\*\*Показание\.\*\*\s*`([^`]+)`', block, re.M)
    if not m:
        continue
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
                           text=True, timeout=120)
        value = (r.stdout or r.stderr).strip().split("\n")[-1][:200]
    except Exception as e:
        value = f"команда не выполнилась: {e}"
    stamp = datetime.date.today().isoformat()
    line = f"**Последнее показание ({stamp}).** {value}"

    old = last_rx.search(block)
    old_value = old.group(1).strip() if old else None
    if old_value == value.strip():
        continue
    stale.append(f"{ident}: в файле «{old_value if old_value is not None else '—'}», в мире «{value}»")
    stale_rows.append((ident, old_value if old_value is not None else "", value))
    if mode != "--check":
        new_block = (block[:old.start()] + line + block[old.end():]) if old \
                    else block.rstrip() + "\n" + line + "\n"
        out = out.replace(block, new_block, 1)
        changed += 1

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
    print("все показания открытых пунктов свежие")
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
