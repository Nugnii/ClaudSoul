#!/usr/bin/env bash
# docs-refresh-claims.sh — числа в документах состояния считаются реестром, а не помнятся.
#
# Результат: каждое число документа состояния, записанное в scripts/doc-claims.tsv, равно
#            нынешнему значению своей команды (scripts/doc-figures.sh <ключ>)
# Проверка результата: bash scripts/docs-refresh-claims.sh --check даёт 0, когда ни одно
#            утверждение с доступным источником не разошлось с миром
#
# Зачем (30 августа 2026). Перед релизом v1.31.0 стояли шесть стражей документации, и все
# проверяли ФОРМУ: версия в семье документов, автотаблицы, одна сгенерированная строка,
# живые ссылки, дубли, индекс зависимостей. Правду чисел в прозе не проверял никто — у них
# не было команды. README ушёл наружу со 176 находками при 185, 52 хуками при 54, «пять
# хуков прерывают» при девяти. Владелец: «какого хера перед пушем не проверяется актуальность
# документации?». Тот же класс, что показания бэклога (D210): вписанное рукой устаревает в
# ту же секунду; ответ тот же — число объявляет команду, механизм подставляет и сверяет.
#
# ФОРМА. Строка реестра: файл, регулярное выражение с одной группой, ключ величины, формат,
# описание. `run` подставляет значение в группу первого совпадения; `--check` только
# сравнивает и называет расхождения (код 1; устаревший реестр — 3; сломанный прибор — 2). Ключ с источником, недоступным на этой машине
# (`n/a` — чужая машина, CI без базы знаний), пропускается и называется: это не расхождение.
#
# ГДЕ СТОИТ. `--check` зовут страж бампа версии (hooks/docs-family-check.sh, путь A) и гейт
# публикации (scripts/publish-public.sh, шаг 3c) — документ с устаревшим числом ни в релиз,
# ни наружу не уходит. Реестр замеров: `doc-claims` (7).
#
# НАЗВАННЫЙ ПРЕДЕЛ. Реестр держит числа и даты, а не смысл фраз: утверждение «blocker не
# останавливает вызов» без числа реестром не ловится — его ловит только сверка описания с
# кодом (аудит доков модулей и шапок). Условие снятия: у утверждений о поведении появится
# машинный носитель (например, тест, названный в строке реестра как источник истины).
# КОНТРПРИМЕР: регулярное выражение, не нашедшее совпадения, — не тишина, а находка
# («утверждение исчезло из документа»): реестр без своего места в тексте есть мёртвая строка.
set -uo pipefail

MODE="${1:-run}"

# Режим сверяется с перечнем: неизвестное значение НЕ означает умолчание. До 1 сентября
# 2026 `MODE="${1:-run}"` не различал «не указан» и «указан неверно», и любой аргумент
# мимо перечня выполнял разрушительную ветку. Замер на фикстуре: из пяти написаний
# (`check`, `--check`, `--bogus`, пусто, `run`) перенос выполняли ЧЕТЫРЕ — то есть просьба
# проверить меняла файл. Имена режима у соседей разошлись (`check` у архиватора и
# measurement-due, `--check` у пересчётчика показаний и сверки чисел), поэтому принимаются
# оба написания, а всё прочее отбивается кодом 2.
# Третий режим — `places` (10 сентября 2026). Отвечает на ОДИН вопрос: у каждого ли ключа
# реестра выражение находит место в тексте документа. Источники при этом НЕ ИСПОЛНЯЮТСЯ.
# Повод: показание пункта долга звало `--check` ради этого одного числа, а `--check`
# исполняет 173 команды-источника — 29,5 секунды. Показание пересчитывается на границе хода,
# и та стоила 39 секунд из-за одного этого вызова.
case "$MODE" in
    run|--run)         MODE=run ;;
    check|--check)     MODE=--check ;;
    places|--places)   MODE=--places ;;
    *) echo "применение: $(basename "$0") [run|check|places] [--keys k1,k2]" >&2; exit 2 ;;
esac
# --keys a,b,c — сверять только строки с этими ключами (13 сентября 2026, D377). У теста
# производных чисел был СВОЙ перечень признаков, разошедшийся с реестром (английская форма
# README жила в реестре и отсутствовала в тесте); теперь узкая поверхность теста — строки
# реестра с коммит-обусловленными ключами, и источник признаков один.
KEYS=""
# @commit — ИМЯ перечня коммит-обусловленных ключей, а не сам перечень у потребителя. Числа
# этих ключей двигает коммит (состав дерева), прочие растит работа системы (D268) либо их
# источник живёт вне репозитория. Потребителей у имени двое — свидетель производных чисел и
# гейт публикации, правящий числа по снимку, — и перечень обязан быть у них один: ровно на
# этом месте уже расходились тест и реестр (D377).
# В перечне — КАЖДЫЙ ключ, чьё значение `scripts/doc-figures.sh` берёт из дерева (D1336, корень R3): прежде их было
# семь из семнадцати, и число «вмешиваются» (сумма «спрашивают» и «отказывают»), мосты, домены и перечни стражей гейт
# публикации по снимку не правил — в README трёх редакций «вмешиваются» расходилось со своей суммой. Сверку перечня с
# ветвями источника держит нога свидетеля `hooks/tests/test_docs_refresh_claims.sh`.
KEYS_COMMIT="hooks,hooks_registered,hooks_deny,hooks_ask,hooks_deny_list,hooks_ask_list,hooks_interrupt,libs,skills,hook_test_files,mcp_test_files,bridges,bridges_done,bridges_formalized,bridges_implicit,bridges_designed,domains"
shift 2>/dev/null || true
while [ $# -gt 0 ]; do
    case "$1" in
        --keys)   KEYS="${2:-}"; shift 2 ;;
        --keys=*) KEYS="${1#--keys=}"; shift ;;
        *) echo "применение: $(basename "$0") [run|check|places] [--keys k1,k2]" >&2; exit 2 ;;
    esac
done
[ "$KEYS" = "@commit" ] && KEYS="$KEYS_COMMIT"

REPO="${CLAUDSOUL_REPO:-$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")/.." 2>/dev/null && pwd -P)}"
CLAIMS="${DOC_CLAIMS_FILE:-$REPO/scripts/doc-claims.tsv}"
FIGURES="${DOC_FIGURES:-$REPO/scripts/doc-figures.sh}"
[ -f "$CLAIMS" ] || { echo "нет реестра $CLAIMS" >&2; exit 0; }
[ -f "$FIGURES" ] || { echo "нет $FIGURES" >&2; exit 0; }
command -v python3 >/dev/null 2>&1 || { echo "docs-refresh-claims: нужен python3 — не измерено" >&2; exit 2; }

# Производный документ (перевод с шапкой derived-from), отставший от источника, в сверке
# пропускается и называется числом (14 сентября 2026): его числа заведомо старые, и красить
# ими сверщик значило бы красить его в каждой сессии; свежим он станет пересборкой перед
# публикацией, и там же сверится. Перечень берётся у владельца признака, не считается здесь.
STALE_DERIVED=""
FRESH_DERIVED=""
if [ -f "$REPO/scripts/docs-derived-check.sh" ]; then
    STALE_DERIVED=$(bash "$REPO/scripts/docs-derived-check.sh" stale 2>/dev/null | tr '\n' ' ')
    # Снимок свежих ДО правки: `run` ведёт обе языковые версии синхронно (в реестре по 59
    # строк на язык), и производный, свежий до прогона, остаётся свежим после — штамп
    # переставляется ему же. Отставший по прозе в снимок не попал и останется отставшим.
    FRESH_DERIVED=$(bash "$REPO/scripts/docs-derived-check.sh" fresh 2>/dev/null | tr '\n' ' ')
fi

# Модуль исполнения со сроком — из дерева САМОГО прибора (D1239): `REPO` бывает чужим или песочным деревом, где его нет.
_BR_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")/../hooks/lib" 2>/dev/null && pwd -P)"
[ -f "$_BR_DIR/bounded_run.py" ] || _BR_DIR="$HOME/.claude/hooks/lib"
BOUNDED_RUN_DIR="$_BR_DIR" REPO_DIR="$REPO" CLAIMS_FILE="$CLAIMS" FIGURES_SH="$FIGURES" MODE="$MODE" CLAIM_KEYS="$KEYS" STALE_DERIVED="$STALE_DERIVED" python3 - <<'PY'
import os, re, shlex, subprocess, sys, pathlib
repo = pathlib.Path(os.environ["REPO_DIR"]); mode = os.environ["MODE"]
# Замок на файлах документов (род H, брат корня, найденного 14 сентября 2026 в
# docs_derived_stamp): README и справочник правят несколько механизмов сразу —
# count-stats под замком, штамп производных под замком, этот сверщик писал без него.
# Признак прибора родов смотрит оболочечную форму и python-запись не видел по построению.
# Отсутствие библиотеки НЕ роняет работу, но говорится вслух — молчание тут неотличимо
# от «замок взят».
# Библиотека замка — из дерева САМОГО прибора (D1239, брат корня): `repo` бывает чужим или песочным деревом.
_SL = os.environ.get("BOUNDED_RUN_DIR") or str(repo / "hooks" / "lib")
if _SL not in sys.path: sys.path.insert(0, _SL)
try:
    from state_lock import with_lock  # type: ignore
except ImportError:
    from contextlib import contextmanager
    @contextmanager
    def with_lock(_path):  # type: ignore
        print("docs-refresh-claims: нет hooks/lib/state_lock.py — документы правятся БЕЗ замка",
              file=sys.stderr)
        yield False
rows, broken = [], []
for lineno, line in enumerate(open(os.environ["CLAIMS_FILE"], encoding="utf-8"), 1):
    if not line.strip() or line.startswith("#"): continue
    parts = line.rstrip("\n").split("\t")
    # Ровно пять полей: лишний таб сдвигал ключ в «», и строка тихо уходила в «пропущено».
    if len(parts) != 5 or not all(parts[:3]):
        broken.append(f"строка {lineno}: полей {len(parts)}, а не 5 — {line.strip()[:80]}"); continue
    rows.append(parts)
keys = {k for k in os.environ.get("CLAIM_KEYS", "").split(",") if k}
if keys:
    rows = [r for r in rows if r[2] in keys]

# Источник числа исполняется ПРАВИЛОМ ИСПОЛНИТЕЛЕЙ (`hooks/lib/bounded_run.py`, D1239): по сроку снимается группа
# со всеми потомками (`doc-figures.sh` зовёт прогоны и `root-map.py`), у команды свой TMPDIR. Модуля нет — прежний
# вызов, снимающий только `bash`. Срок — ручка для свидетеля.
sys.path.insert(0, os.environ.get("BOUNDED_RUN_DIR") or "")
try:
    import bounded_run  # type: ignore
except ImportError:
    bounded_run = None
FIG_TIMEOUT = float(os.environ.get("DOC_FIGURES_TIMEOUT") or 120)
cache = {}
def figure(key):
    if key not in cache:
        # Ключ, чей источник ЗАПУСКАЕТ прогон (тесты, drift-check), под нагрузкой не
        # укладывается в срок, и до 11 сентября 2026 это валило весь сверщик трейсбеком
        # прямо в гейте публикации. «Не успел» — третье состояние прибора, не равное ни
        # «источника здесь нет», ни «числа разошлись», и называется оно отдельно.
        try:
            if bounded_run is not None:
                r = bounded_run.run_bounded("bash " + shlex.quote(os.environ["FIGURES_SH"]) + " " + shlex.quote(key),
                                            FIG_TIMEOUT, cwd=None, env=os.environ, prefix="drc.", capture=True)
            else:
                r = subprocess.run(["bash", os.environ["FIGURES_SH"], key], capture_output=True, text=True,
                                   timeout=FIG_TIMEOUT)
            cache[key] = (r.stdout or "").strip()
        except subprocess.TimeoutExpired:
            cache[key] = "timeout"
    return cache[key]

def fmt(v, f):
    if f == "comma": return v.replace(".", ",")
    if f == "thousands_comma": return f"{int(v):,}"
    if f == "thousands_space": return f"{int(v):,}".replace(",", " ")
    return v

drift, skipped, missing, srcerr, changed = [], [], [], [], {}
stale_derived = set(os.environ.get("STALE_DERIVED", "").split()); derived_skipped = []
texts = {}
for file, rx, key, f, note in rows:
    path = repo / file
    # Пропуск — только в сверке. В записи отставший правится, как его правит count-stats: у двух писателей одного
    # документа правило к нему одно (D1223 — иначе строки README называли 91 и 94 хука). Отставание прозы держит
    # штамп источника, и числа его не снимают: штамп переставляется лишь свежим до прогона.
    if file in stale_derived and mode == "--check":
        derived_skipped.append(file); continue
    if not path.is_file():
        missing.append(f"{file}: файла нет"); continue
    text = texts.get(file) or path.read_text(encoding="utf-8")
    m = re.search(rx, text, re.M)
    if not m:
        missing.append(f"{file}: выражение не нашло места в тексте — «{note}» ({rx})"); continue
    if mode == "--places":
        continue          # место найдено — источник для этого вопроса не нужен
    val = figure(key)
    if val == "err":
        # Источник есть, а числа нет — сломан ПРИБОР, а не документ и не реестр: своя корзина и код 2.
        srcerr.append(f"{file}: «{note}» — источник {key} есть, но числа не дал (форма итога не разобрана)"); continue
    if val == "timeout":
        skipped.append(f"{file}: «{note}» — источник {key} НЕ УСПЕЛ за 120 с (машина занята), число не сверено"); continue
    if val in ("", "n/a"):
        skipped.append(f"{file}: «{note}» — источник {key} недоступен здесь"); continue
    want = fmt(val, f)
    have = m.group(1)
    if have == want: continue
    drift.append(f"{file}: «{note}» — в документе {have}, в мире {want}")
    if mode != "--check":
        text = text[:m.start(1)] + want + text[m.end(1):]
        texts[file] = text; changed[file] = changed.get(file, 0) + 1
    else:
        texts[file] = text

for file, t in texts.items():
    if file in changed:
        with with_lock(str(repo / file)):
            (repo / file).write_text(t, encoding="utf-8")

if derived_skipped:
    print(f"пропущено (производный документ отстал от источника, пересборка перед публикацией): {len(derived_skipped)} строк в {', '.join(sorted(set(derived_skipped)))}")
if broken:
    print(f"сломанных строк реестра: {len(broken)}")
    for b in broken: print(f"  · {b}")
if skipped:
    print(f"пропущено (источник недоступен): {len(skipped)}")
    for s in skipped[:12]: print(f"  · {s}")
if srcerr:
    print("источники без числа (прибор сломан — не документ и не реестр):")
    for s in srcerr: print(f"  · {s}")
if missing:
    print("утверждения без места в документе (реестр устарел или текст переписан):")
    for s in missing: print(f"  · {s}")
# ТРИ КОДА — ТРИ СОСТОЯНИЯ (13 сентября 2026, D377, корень R6). Прежде код 1 отвечал и на
# «числа разошлись», и на «реестр устарел», и на «источник без числа» — сверщик был красен
# всегда, и замер doc-claims помечал его «с находками» каждый прогон, не различая, какими.
#   1 — числа документа разошлись с миром (правится `run`); при расхождении он и печатается,
#       даже если рядом устарел реестр: работа есть, и она первая;
#   3 — реестр устарел или сломан: выражение без места, файла нет, строка не из пяти полей
#       (правится реестр: `places` называет строки);
#   2 — прибор не отработал: нет python3 либо источник есть, а числа не дал.
# Потребители читают код, а не текст: measurement-due (3 — находки второго рода),
# docs-family-check и гейт публикации (у каждого кода своя строка).
if mode == "--check":
    if drift:
        print("числа документов разошлись с миром:")
        for d in drift: print(f"  · {d}")
        print("[замер: находки, не сбой] правь: bash scripts/docs-refresh-claims.sh run (реестр — scripts/doc-claims.tsv)")
        sys.exit(1)
    if srcerr:
        print("[замер: сбой] источник есть, а числа не дал — сломан прибор, числа не сверены")
        sys.exit(2)
    if missing or broken:
        print("[замер: находки, не сбой] РЕЕСТР УСТАРЕЛ ИЛИ СЛОМАН — по этим строкам числа не сверялись: bash scripts/docs-refresh-claims.sh places (реестр — scripts/doc-claims.tsv)")
        sys.exit(3)
    print(f"утверждения документов совпадают с миром: проверено {len(rows) - len(skipped) - len(derived_skipped)}")
    sys.exit(0)
if changed:
    print("подставлено: " + ", ".join(f"{k} ×{v}" for k, v in changed.items()))
    for d in drift: print(f"  · {d}")
elif mode == "--places":
    # Режим `places` чисел не сверяет — он ищет МЕСТО каждой строки реестра в тексте (D1336): прежде итог был общий с
    # `run`, и «всё совпадает» звучало при расхождении, которого режим не смотрел.
    print(f"места найдены: строк реестра {len(rows)}, без места {len(missing)} (числа в режиме places не сверяются)")
else:
    print(f"обновлять нечего: проверено {len(rows) - len(skipped) - len(derived_skipped)}, всё совпадает")
if srcerr: sys.exit(2)
sys.exit(3 if (missing or broken) else 0)
PY
rc=$?

# Свежие до правки производные остаются свежими: штамп переставляется им (см. снимок выше).
# Только в режиме записи — `check`/`places` мир не меняют, и штамп там трогать нечем.
if [ "$MODE" != "--check" ] && [ "$MODE" != "--places" ]; then
    for _d in $FRESH_DERIVED; do
        bash "$REPO/scripts/docs-derived-check.sh" stamp "$_d" >/dev/null 2>&1 || \
            echo "docs-refresh-claims: штамп производного $_d не переставлен" >&2
    done
fi
exit $rc
