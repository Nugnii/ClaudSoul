#!/usr/bin/env bash
# test_module_doc_registration_claims.sh — утверждение о регистрации сверяется с деревом.
#
# Результат: модульный док не называет событие, на котором хук не зарегистрирован.
# Проверка результата: bash hooks/tests/test_module_doc_registration_claims.sh даёт 0
#
# Зачем (D108). Числа в документах выводит генератор (`count-stats.sh`) и сверяет страж.
# Прочие утверждения о том же дереве — нет: «индекс лежит в репозитории», «регистрация
# PreToolUse[Bash]», «замер в реестре». Каждое выводимо механически и не выводилось ниоткуда.
#
# Повод, замеренный 28 августа 2026: модульный док пары «карта зависимостей + страж влияния»
# утверждал, что индекс лежит в репозитории, а индекс был под .gitignore — на чужой машине
# страж молчал бы всегда. Написано из замысла, а не из дерева. Не поймал никто: docs-inventory
# проверяет присутствие ИМЕНИ, а не верность сказанного.
#
# Здесь взят самый частый из проверяемых видов — событие регистрации хука (11 доков из 18).
# Источник истины — HOOKS_CONFIG в install.sh: это то, что реально раскладывается.
#
# КОНТРПРИМЕР: `hooks/lib/*.py` и упоминание события в прозе БЕЗ имени хука рядом не
# проверяются — у библиотеки регистрации нет, а прозе не на что опереться.
set -uo pipefail

REPO="$(cd "$(dirname "$0")/../.." && pwd)"
INSTALL="$REPO/install.sh"
DOCS="$REPO/.claude-docs/modules"
[ -f "$INSTALL" ] || { echo "FAIL: нет $INSTALL"; exit 1; }
[ -d "$DOCS" ] || { echo "SKIP: нет $DOCS"; exit 0; }
command -v python3 >/dev/null 2>&1 || { echo "SKIP: нет python3"; exit 0; }

python3 - "$INSTALL" "$DOCS" <<'PY'
import json, re, sys, pathlib

install = pathlib.Path(sys.argv[1]).read_text(errors="replace")
docs = sorted(pathlib.Path(sys.argv[2]).glob("*.md"))

m = re.search(r"HOOKS_CONFIG='(\{.*?\n\})'", install, re.S)
if not m:
    print("BROKEN: в install.sh не найден HOOKS_CONFIG — сверять не с чем")
    sys.exit(2)
cfg = json.loads(m.group(1))

# Что реально зарегистрировано: имя хука → множество (событие, matcher).
registered = {}
for event, groups in cfg.get("hooks", {}).items():
    for g in groups:
        matcher = g.get("matcher", "")
        for h in g.get("hooks", []):
            hm = re.search(r"hooks/([A-Za-z0-9._-]+\.sh)", h.get("command", ""))
            if hm:
                registered.setdefault(hm.group(1), set()).add((event, matcher))

def events_of(hook):
    return {e for e, _ in registered.get(hook, set())}

def matchers_of(hook, event):
    """Matcher'ы хука на событии. Пустой означает «все инструменты» и возвращается как
    None-маркер: любой заявленный matcher им накрыт, и требовать правки верного документа
    из-за самой широкой регистрации — ложная тревога."""
    ms = {m for e, m in registered.get(hook, set()) if e == event}
    return ms

def matcher_ok(claimed, real):
    if not claimed or not real:
        return True
    if "" in real:
        return True          # пустой matcher — все инструменты, включая заявленный
    want = {x for x in claimed.split("|") if x}
    # Заявленный набор истинен, если он ПОДМНОЖЕСТВО хотя бы одной регистрации: док вправе
    # назвать те инструменты, о которых говорит, не перечисляя весь matcher целиком.
    return any(want <= {y for y in r.split("|") if y} for r in real)

EVENTS = ("PreToolUse", "PostToolUse", "UserPromptSubmit", "Stop",
          "SessionStart", "PreCompact", "SessionEnd", "Notification")
HOOK = re.compile(r"`hooks/([A-Za-z0-9._-]+\.sh)`")
# Скобка принадлежит БЛИЖАЙШЕМУ предшествующему хуку — это правило, а не длина промежутка.
# Промежуток допускает обратные кавычки (между именем хука и его скобкой законно стоит
# упоминание библиотеки), но НЕ другое имя хука: иначе `(PostToolUse)` второго хука
# приписывалось первому, и страж требовал правки верного документа.
PAREN_OPEN = re.compile(r"\(([^)\n]*)\)")

def paren_claims(block):
    hooks = [(m.start(), m.group(1)) for m in HOOK.finditer(block)]
    for pm in PAREN_OPEN.finditer(block):
        prev = [(pos, name) for pos, name in hooks if pos < pm.start()]
        if not prev:
            continue
        pos, name = prev[-1]
        # Между хуком и его скобкой не должно быть переноса строки: список составом
        # переносит запись, и скобка следующей строки — уже про другое.
        if "\n" in block[pos:pm.start()]:
            continue
        yield name, pm.group(1)

def events_in(blob):
    """Событие и, если названо, его matcher: `PreToolUse[Bash]`."""
    out = set()
    for e in EVENTS:
        for m in re.finditer(rf"\b{e}\b(?:\[([^\]]*)\])?", blob):
            out.add((e, m.group(1) or ""))
    return out

def doc_hook(text):
    """Хук, о котором документ. Берётся из ИМЕНИ файла — модульный док описывает один
    модуль, и его хук зовётся так же. Если такого хука нет в регистрации, адресата
    определяем по блоку."""
    cand = globals().get("_doc_stem", "") + ".sh"
    return cand if cand in registered else ""

def blocks(text):
    """ВСЕ блоки «Файлы», а не первый.

    Блок кончается следующим жирным маркером или заголовком, а не первой пустой
    строкой: состав, свёрстанный списком с новой строки, при обрыве по пустой строке
    вырождался в саму строку маркера, и утверждений извлекалось ноль — молча.
    """
    for m in re.finditer(r"\*\*Файлы\.\*\*", text):
        rest = text[m.start():]
        stop = len(rest)
        # Точка после маркера не обязательна: в дереве есть жирные заголовки без неё, и
        # требование точки не отсекало соседний раздел — блок глотал его целиком.
        for pat in (r"\n\*\*[^*\n]+\*\*", r"\n#{1,6} "):
            mm = re.search(pat, rest[2:])
            if mm:
                stop = min(stop, mm.start() + 2)
        yield rest[:stop]

def heading_claims(text):
    """Утверждения из ЗАГОЛОВКОВ: имя хука и событие в одной строке заголовка."""
    for line in text.splitlines():
        if not line.lstrip().startswith("#"):
            continue
        hooks = HOOK.findall(line)
        ev = events_in(line)
        if len(hooks) == 1 and ev:
            yield hooks[0], ev

def claims(text):
    """Утверждения о регистрации — из блоков «Файлы».

    Событие приписывается хуку ТОЛЬКО двумя способами: оно в его собственных скобках,
    либо оно во фразе «Регистрация:» — и тогда адресат берётся из имени документа, а не
    «первый хук блока». Прежнее правило вешало на первый хук любое событие из блока,
    включая упомянутое в ОТРИЦАНИИ («ни один из них на PreToolUse не висит»), и требовало
    исправить верный документ.
    """
    own = doc_hook(text)
    for block in blocks(text):
        claimed = set()
        for hook, blob in paren_claims(block):
            ev = events_in(blob)
            if ev:
                claimed.add(hook)
                yield hook, ev
        # До конца строки, а не до первой точки: точка есть в каждом имени файла (`.sh`),
        # и захват обрывался на ней, теряя утверждение.
        m = re.search(r"[Рр]егистрация:\s*([^\n]*)", block)
        if m:
            ev = events_in(m.group(1))
            # Адресат фразы «Регистрация:» — хук, ОДНОИМЁННЫЙ документу: модульный док
            # описывает один модуль. Запасной путь «первый хук блока» страж объявил
            # отвергнутым и всё же исполнял, когда одноимённого хука в регистрации нет, —
            # и требовал править верный документ про два хука. Нет одноимённого — фраза
            # адресата не имеет, и утверждением она не считается: молчание честнее ложной
            # тревоги, а щель названа здесь.
            if ev and own and own not in claimed:
                yield own, ev

bad, checked = [], 0
for d in docs:
    text = d.read_text(errors="replace")
    globals()["_doc_stem"] = d.stem
    _all = list(claims(text)) + list(heading_claims(text))
    for hook, claimed in _all:
        # Библиотека регистрации не имеет по построению: её подключают через `source`, а
        # не вешают на событие. Событие рядом с её именем относится к тому, кто её зовёт.
        if hook.endswith("-lib.sh"):
            continue
        actual_events = events_of(hook)
        for ev, matcher in sorted(claimed):
            checked += 1
            if ev not in actual_events:
                bad.append((d.name, hook, f"событие {ev}",
                            ", ".join(sorted(actual_events)) or "не зарегистрирован"))
                continue
            # Matcher сверяется, а не пропускается молча: `PreToolUse[Read]` у хука,
            # стоящего на `PreToolUse` с matcher `Bash`, означает «не срабатывает никогда».
            real = matchers_of(hook, ev)
            if not matcher_ok(matcher, real):
                bad.append((d.name, hook, f"matcher {ev}[{matcher}]",
                            ", ".join(f"{ev}[{r}]" for r in sorted(real))))

print(f"утверждений о регистрации проверено: {checked}, расходятся с install.sh: {len(bad)}")
for doc, hook, claim, actual in bad:
    print(f"  · {doc}: `{hook}` — заявлено {claim}; в install.sh — {actual}")
if bad:
    print("  Утверждение о дереве пишется ИЗ дерева. Поправь док либо регистрацию.")
sys.exit(1 if bad else 0)
PY
