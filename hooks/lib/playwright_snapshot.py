#!/usr/bin/env python3
"""Снимок упавшей проверки Playwright, не прочитанный до правки её спеки.

Использование: playwright_snapshot.py <расшифровка> <путь правимой спеки>
Печатает пути снимков (`…/error-context.md`, как их напечатал прогон), по одному в строке: проверка этой спеки в
последнем отчёте Playwright расшифровки упала НА ЭЛЕМЕНТЕ СТРАНИЦЫ, а снимок с тех пор не прочитан. Строка
`?<TAB><путь>` — падение, чей род по выводу не виден, а снимка на диске нет: судить нечем, страж говорит подсказкой.
Пусто — правке мешать нечему. Код 0 — ответ дан (пусто или строки); 2 — не измерено (нет файла, сбой разбора). Иного
кода нет: любой сбой — 2, чтобы страж не прочитал его как «прочитано».

Результат: правка упавшей спеки вслепую видна в момент правки, а не после третьей попытки
Проверка результата: bash hooks/tests/fixtures/probe_D1356.sh даёт 0

Зачем (D1356, 22 ноября 2026, решение владельца «Оба»). Знание pattern-fixture-form-not-taken-from-the-world велит при
упавшем локаторе прочитать снимок прогона до второй попытки, и держалось оно текстом. Замер корпуса того же дня:
правок упавшей спеки при непрочитанном снимке 29, после 15 та же проверка упала снова.

Признак — последовательность событий, а не один вызов:
  1. ОТЧЁТ Playwright — результат ЛЮБОГО инструмента, в тексте которого «Running N tests using M workers», строка
     «N passed|failed|flaky» или «Error Context:». Отчёт узнаётся по ВЫВОДУ, а не по команде: прогон в фоне, вывод в
     файл, прочитанный потом `tail`/Read/BashOutput, — тот же отчёт (скептик M1: 43 из 298 выводов с «Error Context:»
     в корпусе пришли не командой прогона); команда, лишь упоминающая `playwright test` (`grep test:e2e package.json`,
     `--list`, сообщение коммита), картину не обнуляет (скептик L3). Каждый отчёт заменяет прежнюю картину.
  2. Блок падения — текст от предыдущего пути снимка до этого — говорит об элементе страницы: `Locator:`,
     `waiting for locator(`/`getBy…`, `TimeoutError: locator.`, ожидания `toBeVisible`/`toHaveText`/…. Строки
     фрагмента исходника (`  12 |   await …`, `>  12 | …`, `     |   ^`) из блока вырезаются до сверки: соседняя строка
     кода с `.toBeVisible(` при падении `toBe` делала элементным падение на значении (скептик H1: 27 из 149
     «элементных» блоков корпуса стали такими только через фрагмент кода). Падение на значении, журнале, геометрии,
     закрытом браузере признак не ловит.
     Рода в блоке нет вовсе (ни строки `…Error:`, ни исчерпанного срока) — вывод обрезан хвостом (`| tail -N`), и
     «нет признака элемента» значит «не видно», а не «не на элементе» (D1359: в корпусе ProjectA у 111 из 176 отчётов
     заголовок падения срезан). Такое падение судится по разделу «# Error details» самого снимка на диске — путь
     ищется от каталога спеки вверх; снимка нет — строка подсказки.
  3. Спека падения — из заголовка блока (`1) [chromium] › audit/x.spec.ts:10:5 › …`); правится ровно она (скептик M2:
     префикс имени каталога путал `login.spec.ts` с `login-admin`). Заголовка нет (вывод обрезан) — по строке
     «- Location:» снимка на диске (каталог снимка Playwright называет по ПУТИ спеки, `tests-lang-switcher-…`), снимка
     нет — по каталогу: его имя начинается с основы имени спеки и дефиса. Срезан и «Error Context:» — спека из сводки
     «N failed», её снимки — `test-results/*/error-context.md` ближайшей папки прогона с её «- Location:» (D1359, M1).
     Подъём от спеки к папке прогона кончается каталогом с `playwright.config.*` (L2).
  4. Снимок не прочитан: Read пути `…/<каталог>/error-context.md`; команда оболочки с `error-context` и именем каталога
     либо с маской/`find` (читает все); Grep с `error-context` в пути или маске; печать снимка в выводе отчёта
     («СНИМОК СТРАНИЦЫ», ProjectA B737). Чтение снимка без `error-context` (PNG того же каталога) — не чтение (скептик L2).
     Попытки одной проверки (`…-retry1`) — одна проверка: прочитана любая — прочитаны все (скептик L4).
     Мерить чтение оболочкой не случайно: в корпусе снимок читали ею 198 раз, Read — 0.

НАЗВАННЫЙ ПРЕДЕЛ: читается хвост расшифровки (`TAIL_BYTES`, 16 МБ). Отчёт раньше окна не виден, правка проходит —
безопасная сторона для отказа. Условие снятия: правка упавшей спеки после отчёта старше окна встретится в корпусе.
НАЗВАННЫЙ ПРЕДЕЛ: отчёт, не попавший в расшифровку (терминал владельца, CI), не виден. Условие снятия: Playwright
начнёт писать путь снимка в известный файл состояния.
НАЗВАННЫЙ ПРЕДЕЛ: снимки спеки, чей путь срезан, ищутся только в `test-results/` (каталог Playwright по умолчанию; так у
всех трёх проектов владельца). Иной `outputDir` — подсказка «снимок не найден». Условие снятия: такой проект появится.
НАЗВАННЫЙ ПРЕДЕЛ: судятся только `*.spec.*` — `*.test.*` Playwright тоже берёт по умолчанию, но в проектах владельца
это файлы vitest (скептик L7; в корпусе отчётов Playwright по `*.test.*` 0). Условие снятия: такой отчёт появится.
"""
import glob
import json
import os
import re
import sys

TAIL_BYTES = int(os.environ.get('PLAYWRIGHT_SNAPSHOT_TAIL', str(16 * 1024 * 1024)))
REPORT = re.compile(r'Running \d+ tests? using \d+ workers?|^\s*\d+ (passed|failed|flaky)\b|Error Context:', re.M)
EC = re.compile(r'[^\s\'"`()<>]*error-context\.md')
ANSI = re.compile(r'\x1b\[[0-9;]*[A-Za-z]')
CODEFRAME = re.compile(r'^\s*>?\s*\d+\s*\|')
CARET = re.compile(r'^\s*\|\s*\^')
SPECREF = re.compile(r'([\w.@-]+\.spec\.[cm]?[jt]sx?):\d+')
RETRY = re.compile(r'-retry\d+$')
ELEMENT = re.compile(r'(^|\s)Locator:\s|waiting for (locator|getBy)|TimeoutError: locator\.|'
                     r'\.(toBeVisible|toBeHidden|toHaveText|toContainText|toBeEnabled|toBeDisabled|toHaveValue|'
                     r'toHaveCount|toBeChecked|toHaveAttribute|toHaveClass|toBeFocused|toBeEditable)\(')
# Род падения виден в выводе: строка ошибки (`Error:`, `TimeoutError:`, …) либо исчерпанный срок проверки. Нет её —
# вывод обрезан (`| tail -N` оставляет стек и «Error Context:»), и «не на элементе» по выводу не сказано (D1359).
KIND = re.compile(r'^\s*(?:[A-Za-z]*Error:|Test timeout of \d+ms exceeded)', re.M)  # не «Error Context:»
DETAILS = re.compile(r'^# Error details[ \t]*$(.*?)(?=^# |\Z)', re.M | re.S)
PRINTED = 'СНИМОК СТРАНИЦЫ'


def text_of(c):
    if isinstance(c, str):
        return c
    if isinstance(c, list):
        return '\n'.join(x.get('text', '') for x in c if isinstance(x, dict) and isinstance(x.get('text'), str))
    return ''


def records(path):
    size = os.path.getsize(path)
    with open(path, 'rb') as f:
        if size > TAIL_BYTES:
            f.seek(size - TAIL_BYTES)
            f.readline()  # обрезанная строка начала окна
        for raw in f:
            try:
                d = json.loads(raw)
            except ValueError:
                continue
            if isinstance(d, dict):
                yield d


def key_of(path):
    return RETRY.sub('', os.path.basename(os.path.dirname(path)))


LABELED = re.compile(r'Error Context:\s*([^\'"`<>\n]*?error-context\.md)')


def failures(out):
    """{проверка: (путь как напечатан, падение на элементе?, спека из заголовка или '', род виден?)} по тексту отчёта.

    Падения — пути после метки «Error Context:»; голые пути снимков берутся, только когда меток в отчёте нет вовсе
    (иной формат). Иначе строки `▶ …/error-context.md` печати B737 читались новыми падениями, и спека первого из них
    бралась из итоговой сводки Playwright — порядок блока печати (по коду символа) с порядком прогона не совпадает
    (скептик D1358, M1)."""
    out = ANSI.sub('', out)
    hits = [(m.start(1), m.end(1), m.group(1)) for m in LABELED.finditer(out)] \
        or [(m.start(), m.end(), m.group(0)) for m in EC.finditer(out)]
    res, start = {}, 0
    for s, e, path in hits:
        k = key_of(path)
        if k:
            block = '\n'.join(l for l in out[start:s].splitlines()
                              if not CODEFRAME.match(l) and not CARET.match(l))
            ref = SPECREF.search(block)
            prev = res.get(k)
            res[k] = (prev[0] if prev else path,
                      bool(ELEMENT.search(block)) or (prev[1] if prev else False),
                      os.path.basename(ref.group(1)) if ref else (prev[2] if prev else ''),
                      bool(KIND.search(block)) or (prev[3] if prev else False))
        start = e
    return res


# Путь в строке `▶` — до первого `error-context.md`, с пробелами и NBSP внутри (скептик D1358, L2: `\S*` их не брал,
# и неразобранная разметка падала в запасное правило «прочитаны все»).
SHOWN = re.compile(r'^▶\s*(.+?error-context\.md)(.*)$', re.M)
# Обрезка — ПОСЛЕДНЯЯ непустая строка блока, а не любое место снимка (L3: текст страницы «… ещё 3 строки»).
CUT = re.compile(r'^\s*…\s*ещё \d+ строк')
# Снимка в файле нет — печать говорит это строкой под `▶` (L1): снимка в выводе нет, прочитанным он не считается.
NOSNAP = 'снимка страницы в файле нет'


def printed(out, keys):
    """Проверки, чей снимок напечатан в отчёте ЦЕЛИКОМ (печать ProjectA B737, D1358).

    Заголовок «СНИМОК СТРАНИЦЫ» один на отчёт, а состояние у каждой проверки своё: печать B737 показывает снимок
    первых трёх падений, остальные — строкой `▶ <путь> — снимок в файле`, а снимок длиннее 150 строк режет строкой
    `… ещё N строк — в файле`. Прочитан печатью снимок той проверки, чья строка `▶ …/error-context.md` стоит без хвоста
    «в файле» и без строки обрезки до следующей `▶`. Печать без построчной разметки `▶` — прежнее правило: все.
    """
    if PRINTED not in out:
        return set()
    marks = list(SHOWN.finditer(ANSI.sub('', out)))
    if not marks:
        return set(keys)
    body = ANSI.sub('', out)
    shown = set()
    for i, m in enumerate(marks):
        end = marks[i + 1].start() if i + 1 < len(marks) else len(body)
        lines = [l for l in body[m.end():end].splitlines() if l.strip()]
        if 'в файле' in m.group(2) or (lines and CUT.match(lines[-1])) or any(NOSNAP in l for l in lines[:2]):
            continue
        shown.add(key_of(m.group(1)))
    return shown


def belongs(k, specref, spec):
    base = os.path.basename(spec)
    if specref:
        return specref == base
    stem = base.split('.spec.')[0]
    return bool(stem) and k.startswith(stem + '-')


def read_keys(name, inp, keys):
    """Какие из ожидающих проверок прочитаны этим вызовом."""
    if name == 'Read':
        fp = inp.get('file_path', '') or ''
        return {k for k in keys if fp.endswith('error-context.md') and k in fp}
    if name == 'Bash':
        cmd = inp.get('command', '') or ''
        if 'error-context' not in cmd:
            return set()
        if re.search(r'\*[^\s]*error-context|\bfind\b', cmd):
            return set(keys)
        return {k for k in keys if k in cmd}
    if name == 'Grep':
        blob = ' '.join(str(inp.get(f, '')) for f in ('path', 'glob'))
        if 'error-context' not in blob:
            return set()
        return {k for k in keys if k in blob} or (set(keys) if '*' in blob else set())
    return set()


def unread(transcript, spec):
    uses, pending = {}, {}
    for d in records(transcript):
        m = d.get('message')
        if not isinstance(m, dict) or not isinstance(m.get('content'), list):
            continue
        for b in m['content']:
            if not isinstance(b, dict):
                continue
            t = b.get('type')
            if t == 'tool_use':
                name, inp = b.get('name'), b.get('input')
                inp = inp if isinstance(inp, dict) else {}
                uses[b.get('id')] = name
                for k in read_keys(name, inp, pending):
                    pending.pop(k, None)
            elif t == 'tool_result':
                out = text_of(b.get('content'))
                if not REPORT.search(out):
                    continue
                fails = failures(out)
                # Спека названа в сводке «N failed», а её падения в отчёте нет — хвост срезал и «Error Context:»
                # (скептик D1359, M1: у 450 из 753 падений корпуса пути снимка в выводе нет). Её снимки — с диска.
                base = os.path.basename(spec)
                if base in summary_specs(out) and not any(belongs(k, ref, spec) for k, (p, el, ref, kind) in fails.items()):
                    snaps = disk_snapshots(spec)
                    for f in snaps:
                        fails.setdefault(key_of(f), (f, False, base, False))
                    if not snaps:
                        fails['\0' + base] = ('', False, base, False)
                shown = printed(out, fails)
                pending = {k: v for k, v in fails.items() if k not in shown}
    deny, hint = [], []
    base = os.path.basename(spec)
    for k, (p, el, ref, kind) in pending.items():
        f = on_disk(p, spec) if p else ''
        loc = location_of(f) if f else ''
        # Чья проверка: спека из вывода отчёта, иначе «- Location:» снимка, иначе имя каталога снимка.
        if ref:
            if ref != base:
                continue
            if loc and not same_spec(loc, spec):
                f = ''  # одноимённый снимок чужой спеки
        elif loc:
            if not same_spec(loc, spec):
                continue
        elif not belongs(k, ref, spec):
            continue
        # Снимок на диске судит первым (скептик D1359, L1: `expect.soft` — видна последняя ошибка, на значении).
        if el or (f and details_on_element(f)):
            deny.append(p)
        elif not f and not kind:
            hint.append(p or base)
    return deny, hint


SUMMARY_END = re.compile(r'^\s*\d+ (passed|flaky|skipped|did not run|interrupted)\b')


def summary_specs(out):
    """Спеки из сводки Playwright после строки «N failed» (до следующего счётчика): «[chromium] › tests/x.spec.ts:2:5 › …»."""
    res, on = set(), False
    for line in ANSI.sub('', out).splitlines():
        if re.match(r'^\s*\d+ failed\b', line):
            on = True
        elif on and SUMMARY_END.match(line):
            on = False
        elif on:
            res.update(os.path.basename(m) for m in SPECREF.findall(line))
    return res


def ancestors(spec):
    """Каталог спеки и выше — до папки прогона: каталога с `playwright.config.*` (скептик D1359, L2: подъём без границы
    брал одноимённый снимок чужого прогона), без него — до корня."""
    d = os.path.dirname(os.path.abspath(spec))
    while True:
        yield d
        if glob.glob(os.path.join(glob.escape(d), 'playwright.config.*')):
            return
        up = os.path.dirname(d)
        if up == d:
            return
        d = up


def on_disk(printed_path, spec):
    """Снимок на диске. Путь напечатан относительно папки прогона, а она — выше спеки: идём от каталога спеки вверх,
    пока путь не найдётся (D1359). Абсолютный путь — как есть. Не нашёлся — ''."""
    if os.path.isabs(printed_path):
        return printed_path if os.path.isfile(printed_path) else ''
    for d in ancestors(spec):
        p = os.path.join(d, printed_path)
        if os.path.isfile(p):
            return p
    return ''


LOCATION = re.compile(r'^- Location:\s*(\S+?):\d+:\d+\s*$', re.M)


def location_of(path):
    """Путь спеки из «# Test info» снимка (`- Location: tests/lang/switcher.spec.ts:164:7`), '' — строки нет.
    Каталог снимка Playwright называет по ПУТИ спеки (`tests-lang-switcher-…`), а не по основе её имени."""
    with open(path, encoding='utf-8', errors='replace') as f:
        m = LOCATION.search(f.read())
    return m.group(1) if m else ''


def same_spec(loc, spec):
    return ('/' + os.path.abspath(spec).replace(os.sep, '/')).endswith('/' + loc.lstrip('./'))


def disk_snapshots(spec):
    """Снимки этой спеки на диске: `test-results/*/error-context.md` в ближайшей к спеке папке прогона, чья строка
    «- Location:» называет эту спеку."""
    for d in ancestors(spec):
        found = [f for f in sorted(glob.glob(os.path.join(glob.escape(d), 'test-results', '*', 'error-context.md')))
                 if same_spec(location_of(f), spec)]
        if found:
            return found
    return []


def details_on_element(path):
    """Падение на элементе по разделу «# Error details» снимка — только по нему: в «# Page snapshot» и «# Test source»
    слова элемента стоят и при падении на значении."""
    with open(path, encoding='utf-8', errors='replace') as f:
        m = DETAILS.search(f.read())
    if not m:
        return False
    text = '\n'.join(l for l in m.group(1).splitlines() if not CODEFRAME.match(l) and not CARET.match(l))
    return bool(ELEMENT.search(text))


def main(argv):
    if len(argv) != 3:
        print(__doc__.split('\n')[2], file=sys.stderr)
        return 2
    tr, spec = argv[1], argv[2]
    if not os.path.isfile(tr):
        return 2
    try:
        deny, hint = unread(tr, spec)
    except Exception as e:  # любой сбой — «не измерено», а не «прочитано» (скептик L5)
        print('playwright_snapshot: %s: %s' % (type(e).__name__, e), file=sys.stderr)
        return 2
    for p in deny:
        print(p)
    for p in hint:
        print('?\t' + p)
    return 0


if __name__ == '__main__':
    sys.exit(main(sys.argv))
