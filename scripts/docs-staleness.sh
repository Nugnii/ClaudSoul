#!/usr/bin/env bash
# docs-staleness.sh — документ, описывающий механизм, не старше последней правки поведения механизма.
#
# Результат: по индексу зависимостей названы пары «документ ← механизм», где механизм
#            менялся коммитом позже документа и решение по документу (`doc-state:` в
#            сообщении коммита либо сам документ в том коммите) не принималось
# Проверка результата: bash scripts/docs-staleness.sh даёт 0, когда таких пар нет
#
# Зачем (30 августа 2026). Владелец: «остальная документация — это не только README, но и
# файлы модулей, хуков, скриптов». Реестр утверждений (doc-claims) держит числа; описания
# поведения числом не выражаются, и единственный машинный признак их устаревания — ВОЗРАСТ:
# док, не тронутый с тех пор, как менялся описываемый им механизм. Решение «не задето»
# законно (D209), но обязано быть записано — `doc-state:` в сообщении коммита; пара без
# решения и есть находка. Индекс зависимостей уже знает, кто кого описывает
# (scripts/dep-index.py, .claude-docs/dep-index.tsv, колонка docs).
#
# ГДЕ СТОИТ. Гейт публикации (publish-public.sh, шаг 3d) и замер `docs-staleness` (7).
#
# НАЗВАННЫЙ ПРЕДЕЛ. Возраст — необходимое, не достаточное: коммит в механизм мог не менять
# поведения (комментарий), а решение `doc-state:` могло быть принято ошибочно — это
# отсеивает doc-impact-check на коммите, здесь считается только след решения. Документ,
# правленный ПОСЛЕ механизма, зелёный по построению, даже если правка не про этот механизм.
# Условие снятия: doc-impact-check начнёт писать решения в носитель, переживающий сессию
# (не state/doc-state-<SID>.jsonl), и сверка возьмёт их оттуда, а не из текста коммита.
# КОНТРПРИМЕР: механизм без описывающих документов пар не даёт — его ловит docs-inventory.
set -uo pipefail

REPO="${CLAUDSOUL_REPO:-$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")/.." 2>/dev/null && pwd -P)}"
INDEX="${DEP_INDEX_FILE:-$REPO/.claude-docs/dep-index.tsv}"
[ -f "$INDEX" ] || { echo "нет индекса $INDEX — python3 scripts/dep-index.py"; exit 0; }
git -C "$REPO" rev-parse --is-inside-work-tree >/dev/null 2>&1 || { echo "не git-репозиторий: сравнивать даты нечем"; exit 0; }

REPO_DIR="$REPO" INDEX_FILE="$INDEX" python3 - <<'PY'
import os, subprocess, sys, datetime
repo = os.environ["REPO_DIR"]; index = os.environ["INDEX_FILE"]
def git(*a):
    return subprocess.run(["git", "-C", repo, *a], capture_output=True, text=True).stdout.strip()
_last = {}
def last(path):   # (epoch, sha) последнего коммита, тронувшего путь; None — путь не в истории
    if path not in _last:
        out = git("log", "-1", "--format=%ct\t%h", "--", path)
        _last[path] = (int(out.split("\t")[0]), out.split("\t")[1]) if out else None
    return _last[path]
_files = {}
def files_of(sha):
    if sha not in _files:
        _files[sha] = set(git("show", "--name-only", "--format=", sha).splitlines())
    return _files[sha]
_decided = {}
def decided(sha):
    if sha not in _decided:
        _decided[sha] = "doc-state:" in git("log", "-1", "--format=%B", sha)
    return _decided[sha]
def day(ts): return datetime.date.fromtimestamp(ts).isoformat()

# Отсечка: решение doc-state могло быть записано только с появления doc-impact-check (D209,
# 30 августа 2026). Правки механизмов старше неё сверять по следу решения нельзя — след
# не мог существовать; их устаревшие описания — предмет разового аудита, не замера.
base = git("log", "-S", "doc-state:", "--format=%ct", "--", "hooks/doc-impact-check.sh").splitlines()   # первое появление требования решения
BASELINE = int(base[-1]) if base else 0
pairs = found = dec = before = 0; out = []
for line in open(index, encoding="utf-8"):
    if not line.strip() or line.startswith("#"): continue
    cols = line.rstrip("\n").split("\t")          # split не схлопывает пустые поля — в отличие от bash read
    while len(cols) < 6: cols.append("")
    path, sha, deps, docs, tests, names = cols[:6]
    if not docs or not os.path.isfile(os.path.join(repo, path)): continue
    m = last(path)
    if not m: continue
    m_ts, m_sha = m
    for d in docs.split(","):
        d = d.strip()
        if not d or not os.path.isfile(os.path.join(repo, d)): continue
        if d in files_of(m_sha): continue          # документ в том же коммите — решение принято самим коммитом
        dd = last(d)
        if not dd: continue
        pairs += 1
        if dd[0] >= m_ts: continue
        if m_ts < BASELINE: before += 1; continue
        if decided(m_sha): dec += 1; continue
        found += 1
        out.append(f"  · {d} ← {path} ({m_sha}, {day(m_ts)}) — док от {day(dd[0])}, решения нет")
print(f"Документы старше описываемых механизмов: пар проверено {pairs}, старше механизма до D209 (разовый аудит) {before}, старше с решением doc-state {dec}, старше БЕЗ решения {found}")
for o in out: print(o)
if found:
    print("[замер: находки, не сбой] по каждой паре: обновить документ либо записать решение «doc-state: не задето — <почему>» в коммит, меняющий механизм")
    sys.exit(1)
sys.exit(0)
PY
