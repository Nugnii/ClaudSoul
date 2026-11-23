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
# Производный документ, отставший от источника, по возрасту не судится (14 сентября 2026):
# он отстаёт по замыслу и пересобирается перед публикацией; число пропущенных называется.
STALE_DERIVED=""
[ -f "$REPO/scripts/docs-derived-check.sh" ] && STALE_DERIVED=$(bash "$REPO/scripts/docs-derived-check.sh" stale 2>/dev/null | tr '\n' ' ')

REPO_DIR="$REPO" INDEX_FILE="$INDEX" STALE_DERIVED="$STALE_DERIVED" python3 - <<'PY'
import os, re, subprocess, sys, datetime
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
# ПРЕДМЕТ ДОКУМЕНТА ОТДЕЛЁН ОТ УПОМИНАНИЯ (15 сентября 2026). Индекс выводит «описывает» из
# УПОМИНАНИЯ, и это верно для его первого потребителя — doc-impact-check называет документы к
# просмотру, там ссылка полезна. Здесь же последствие иное: пара блокирует НЕОБРАТИМУЮ
# публикацию. Замер того дня: из 78 пар документ описывал механизм в ЧЕТЫРЁХ, остальные 74
# задеты ссылкой — «регистрация в `install.sh`», строка «Зависимости», сравнение с соседом.
# Один `install.sh` тянул 20 пар.
# ВОЗРАСТ — КОСВЕННЫЙ ПРИЗНАК, и это тоже измерено: на трёх парах-упоминаниях утверждения
# документов проверены содержанием и ВСЕ ТРИ оказались верны (CLAUDE.md про отказ
# absent-tool-guard, мост про живой authorization-lib, guard-event-coverage про диспетчер).
# Поэтому упоминания печатаются СОВЕТОМ и числом, а код возврата держат только предметы.
# НАЗВАННЫЙ ПРЕДЕЛ: предмет опознаётся по форме — механизм назван ПЕРВЫМ путём в строке
# «Файлы» либо его имя стоит в заголовке. Документ без строки «Файлы» и без имени в заголовке
# предметом не признаётся никогда, даже если описывает механизм по существу.
# Условие снятия: у документов появится объявленное поле предмета (frontmatter `describes:`),
# и форма уступит месту объявлению.
def subject_of(doc_path):
    try:
        t = open(os.path.join(repo, doc_path), encoding="utf-8").read()
    except Exception:
        return "", ""
    head = t.split("\n", 1)[0]
    first = ""
    for l in t.split("\n"):
        if l.startswith("**Файлы.**"):
            mm = re.search(r"`([^`]+)`", l)
            if mm: first = mm.group(1)
            break
    return head, first

def is_subject(doc_path, mech_path):
    head, first = subject_of(doc_path)
    mb = os.path.basename(mech_path)
    return os.path.basename(first) == mb or mb.rsplit(".", 1)[0] in head

pairs = found = dec = before = 0; out = []; mentions = []
stale_derived = set(os.environ.get("STALE_DERIVED", "").split()); derived_skipped = 0
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
        if d in stale_derived: derived_skipped += 1; continue
        if d in files_of(m_sha): continue          # документ в том же коммите — решение принято самим коммитом
        dd = last(d)
        if not dd: continue
        pairs += 1
        if dd[0] >= m_ts: continue
        if m_ts < BASELINE: before += 1; continue
        if decided(m_sha): dec += 1; continue
        line_txt = f"  · {d} ← {path} ({m_sha}, {day(m_ts)}) — док от {day(dd[0])}, решения нет"
        if is_subject(d, path):
            found += 1; out.append(line_txt)
        else:
            mentions.append(line_txt)
print(f"Документы старше описываемых механизмов: пар проверено {pairs}, старше механизма до D209 (разовый аудит) {before}, старше с решением doc-state {dec}, старше БЕЗ решения {found} (по ПРЕДМЕТУ документа; задетых ссылкой — {len(mentions)}, они совет)" + (f", пар с отставшим производным пропущено {derived_skipped}" if derived_skipped else ""))
for o in out: print(o)
if mentions:
    # СОВЕТ, А НЕ НАХОДКА: документ назвал механизм ссылкой (регистрация, строка зависимостей,
    # сравнение с соседом). Печатается числом и первыми тремя адресами — молчать нельзя, но и
    # держать на этом необратимую публикацию значит судить не тот предмет.
    print(f"[совет] задето ссылкой: {len(mentions)} пар — на код возврата не влияют")
    for o in mentions[:3]: print(o.replace("  · ", "    · "))
    if len(mentions) > 3: print(f"    · … и ещё {len(mentions) - 3}")
if found:
    print("[замер: находки, не сбой] по каждой паре: обновить документ либо записать решение «doc-state: не задето — <почему>» в коммит, меняющий механизм")
    sys.exit(1)
sys.exit(0)
PY
