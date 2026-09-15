#!/usr/bin/env python3
# docs-address-drift.py — адрес «файл:строка» в документе указывает туда же, куда указывал,
#                         когда его писали.
#
# Результат: у каждого адреса живого документа проверено СОДЕРЖИМОЕ, а не только непустота
# Проверка результата: python3 scripts/docs-address-drift.py --check даёт 0, когда уплывших нет
#            `--fix` переписывает однозначно уплывшие номера; «содержимое исчезло» — руками
#
# Зачем (D409, 13-14 сентября 2026). Ссылок вида `файл:строка` в документах дерева 757.
# Страж `scripts/docs-inventory.sh:255-271` судит их непустоту: адрес, уплывший на ДРУГУЮ
# непустую строку, не ловится вовсе — предел назван в нём самом (`:225`). Цена измерена в
# один день дважды: `docs/decisions.md:320` указывал на `install.sh:883` при настоящей 992
# (уплыл на 109 строк и жил так давно), `.claude-docs/modules/security-family.md:5` — на 961
# при 964. Оба поймались лишь потому, что СЛУЧАЙНО попали в пустую строку.
#
# ЧЕМ РЕШАЛОСЬ РАНЬШЕ. `docs-inventory.sh` проверяет непустоту — остаётся, здесь он не
# дублируется: предмет иной (содержимое против непустоты). `scripts/doc-claims.tsv` —
# рабочий образец устройства «объявленное ожидание + команда»: там числа документов сверяются
# с миром. Разница в том, что реестра на 757 адресов заводить не нужно — ОЖИДАНИЕ УЖЕ ЕСТЬ
# В ИСТОРИИ: строка, на которую ссылались, лежит в том состоянии файла, каким он был в момент
# последней правки документа.
#
# УСТРОЙСТВО. Для каждого адреса: (1) коммит, которым документ правлен последний раз; (2) файл
# в том коммите, строка N — её текст и есть объявленное ожидание; (3) тот же текст ищется в
# нынешнем файле. Совпал на N — адрес цел; нашёлся на M — адрес УПЛЫЛ, и починка называется
# числом; не нашёлся — содержимое исчезло, адрес判 «содержимого нет».
#
# НАСЕЛЕНИЕ. Живые документы: всё, кроме хроники. CHANGELOG, BACKLOG-archive и файлы сессий
# ИСКЛЮЧЕНЫ намеренно и с доводом: там номер был верен в момент записи, это свидетельство
# прошлого, и переписывать его значит править историю. Живой BACKLOG.md включён — по его
# адресам ходят сейчас. Замер 14 сентября 2026: видимо сломанных адресов 27 из 668, и все
# 27 лежат в исключаемой хронике (архив 22, CHANGELOG 4, BACKLOG 1).
#
# НАЗВАННЫЙ ПРЕДЕЛ: адрес, написанный ОДНОВРЕМЕННО с правкой файла (один коммит), сверяется
# сам с собой и всегда цел. Условие снятия: сверять не с последним коммитом документа, а с
# коммитом, которым эта СТРОКА документа появилась (git blame построчно) — дороже, и цена
# пока не оправдана: таких адресов в дереве 0 по замеру ниже.
import os, re, subprocess, sys, collections, pathlib

# ОБЩИЙ ЗАМОК (род H). `--fix` переписывает документы, которые правят и другие механизмы
# (генераторы авто-таблиц, сверщик чисел, рука). Окно read→write открыто по построению,
# поэтому берётся тот же протокол, что у прочих общих файлов дерева.
_LIB = pathlib.Path(__file__).resolve().parent.parent / "hooks" / "lib"
if not (_LIB / "state_lock.py").exists():
    _LIB = pathlib.Path.home() / ".claude/hooks/lib"
sys.path.insert(0, str(_LIB))
try:
    from state_lock import with_lock
except ImportError:  # библиотеки нет — работаем как прежде: замок улучшает, а не требуется
    from contextlib import contextmanager

    @contextmanager
    def with_lock(_path):
        yield False

REPO = os.environ.get('CLAUDSOUL_REPO') or subprocess.run(
    ['git', 'rev-parse', '--show-toplevel'], capture_output=True, text=True).stdout.strip()
if not REPO:
    print('docs-address-drift: корень не найден — задай CLAUDSOUL_REPO либо зови из репозитория',
          file=sys.stderr)
    sys.exit(2)

# Хроника: номер был верен, когда писался. Исключается с доводом, а не умолчанием.
CHRONICLE = re.compile(r'(^|/)(CHANGELOG|CHANGELOG-archive|SESSION|BACKLOG-archive)\.md$'
                       r'|-20\d\d-\d\d-\d\d\.md$|/_drafts/|/sessions/')
ADDR = re.compile(r'([A-Za-z0-9_][A-Za-z0-9_/.-]*\.(?:sh|py)):(\d+)')


def git(*args):
    return subprocess.run(['git', '-C', REPO] + list(args), capture_output=True, text=True).stdout


def tracked():
    return [f for f in git('ls-files', '-z').split('\0') if f]


def main():
    files = tracked()
    by_base = collections.defaultdict(list)
    for f in files:
        by_base[os.path.basename(f)].append(f)
    docs = [f for f in files if f.endswith('.md') and not CHRONICLE.search(f)]

    FIX = '--fix' in sys.argv
    dirty = {x for x in git('diff', '--name-only', 'HEAD').split('\n') if x}
    skipped_dirty = 0
    repairs = {}
    doc_commit = {}
    snapshot = {}          # (commit, path) → строки файла в том коммите
    checked = drifted = gone = unresolved = same_commit = indistinct = 0
    findings = []
    # НЕ СУДИЛОСЬ — отдельная копилка с ИМЕНАМИ (D414, 14 сентября 2026). До этого дня
    # «уплывших: 0» читалось как «адреса целы», а означало «целы СРЕДИ судимых»: четыре
    # уплывших адреса прошли мимо потому, что их документы правились в тот час и молча
    # выпали из суда. Воспроизведено точным совпадением чисел — 85 сверено, 0 уплывших,
    # 8 неразличимо, — и это ровно та строка, на которую сослались как на «чисто».
    unjudged = []

    for d in docs:
        try:
            text = open(os.path.join(REPO, d), errors='replace').read()
        except OSError:
            continue
        # ДОКУМЕНТ, КОТОРЫЙ ПРАВЯТ СЕЙЧАС, НЕ СУДИТСЯ. Ожидание берётся из файла на момент
        # ПОСЛЕДНЕГО КОММИТА документа; пока правка не закоммичена, пара «документ — снимок»
        # разъехалась, и честно починенный адрес читался бы как новый дрейф (наблюдалось на
        # первом же прогоне `--fix`: 18 починенных дали 11 «новых» уплывших).
        if d in dirty:
            skipped_dirty += 1
            unjudged.append(f'  · {d} — правится сейчас, ожидание из истории несравнимо')
            continue
        if d not in doc_commit:
            doc_commit[d] = git('log', '-1', '--format=%H', '--', d).strip()
        c = doc_commit[d]
        if not c:
            unjudged.append(f'  · {d} — коммита документа нет, ожидание взять неоткуда')
            continue
        for m in ADDR.finditer(text):
            name, num = m.group(1), int(m.group(2))
            cands = by_base.get(os.path.basename(name), [])
            exact = [x for x in cands if x.endswith('/' + name) or x == name]
            cands = exact or cands
            if os.path.exists(os.path.join(REPO, name)):
                target = name
            elif len(cands) == 1:
                target = cands[0]
            else:
                unresolved += 1
                unjudged.append(f'  · {d} → {name}:{num} — имя не разрешилось в путь дерева')
                continue
            key = (c, target)
            if key not in snapshot:
                blob = git('show', f'{c}:{target}')
                snapshot[key] = blob.split('\n') if blob else None
            old = snapshot[key]
            if old is None:
                unresolved += 1
                unjudged.append(f'  · {d} → {name}:{num} — файла не было в коммите документа')
                continue
            if num > len(old) or not old[num - 1].strip():
                # В момент написания документа адрес уже указывал в пустоту — это дефект
                # ТОГО коммита, а не дрейф; про него говорит docs-inventory. Но МОЛЧАТЬ
                # здесь нельзя: адрес не судился, и его надо назвать.
                unresolved += 1
                unjudged.append(f'  · {d} → {name}:{num} — при написании указывал в пустую строку')
                continue
            expected = old[num - 1].strip()
            # ОЖИДАНИЕ ДОЛЖНО БЫТЬ РАЗЛИЧИМЫМ. Строка вроде `#`, `fi` или `done` встречается
            # в файле десятками — по ней нельзя сказать ни «цел», ни «уплыл». Такой адрес
            # честно зовётся НЕРАЗЛИЧИМЫМ и в счёт уплывших не входит: иначе прибор выдал бы
            # 41 «находку» на одной общей строке (замер 14 сентября 2026 — так и вышло).
            if len(expected) < 12:
                indistinct += 1
                unjudged.append(f'  · {d} → {name}:{num} — ожидание неразличимо: {expected!r}')
                continue
            try:
                now = open(os.path.join(REPO, target), errors='replace').read().split('\n')
            except OSError:
                unresolved += 1
                unjudged.append(f'  · {d} → {name}:{num} — файл не прочитан')
                continue
            checked += 1
            if num <= len(now) and now[num - 1].strip() == expected:
                continue
            where = [i + 1 for i, l in enumerate(now) if l.strip() == expected]
            if len(where) == 1:
                drifted += 1
                findings.append(f'  · {d} → {name}:{num} — строка уехала на {where[0]}: {expected[:60]}')
                repairs.setdefault(d, []).append((f'{name}:{num}', f'{name}:{where[0]}'))
            elif not where:
                gone += 1
                findings.append(f'  · {d} → {name}:{num} — содержимого больше нет: {expected[:60]}')
            else:
                # Ожидание нашлось в нескольких местах — сказать, уплыл ли адрес, нечем.
                indistinct += 1
                unjudged.append(f'  · {d} → {name}:{num} — ожидание найдено в {len(where)} местах')

    if FIX and repairs:
        # ЧИНИТСЯ ТОЛЬКО ОДНОЗНАЧНОЕ: адрес, чьё ожидание нашлось ровно в одном месте.
        # «Содержимое исчезло» и «неразличимо» руками — машине там решать нечем.
        for doc, edits in repairs.items():
            path = os.path.join(REPO, doc)
            with with_lock(path):
                body = open(path, errors='replace').read()
                for old_s, new_s in edits:
                    body = body.replace(old_s, new_s)
                open(path, 'w').write(body)
        print(f'починено адресов: {sum(len(v) for v in repairs.values())} '
              f'в {len(repairs)} документ(ах)')

    print(f'адресов сверено по содержимому: {checked}; уплывших: {drifted}; '
          f'содержимое исчезло: {gone}; ожидание неразличимо: {indistinct}; '
          f'неразрешимых имён: {unresolved}; правятся сейчас (не судятся): {skipped_dirty}; '
          f'документов живых: {len(docs)}')
    for f in findings[:40]:
        print(f)
    if len(findings) > 40:
        print(f'  · и ещё {len(findings) - 40}')
    # «Проверено и цело» отделено от «не судилось»: ноль уплывших среди судимых ничего не
    # говорит о тех, кого не судили, и читать одно как другое — два состояния на одном канале.
    if unjudged:
        print(f'НЕ СУДИЛОСЬ поимённо: {len(unjudged)} адрес(ов) и документ(ов) — '
              f'«уплывших: {drifted}» сказано ТОЛЬКО о проверенных {checked}')
        for u in unjudged[:40]:
            print(u)
        if len(unjudged) > 40:
            print(f'  · и ещё {len(unjudged) - 40}')
    if FIX:
        return 1 if gone else 0
    return 1 if (drifted or gone) else 0


if __name__ == '__main__':
    sys.exit(main())
