#!/usr/bin/env bash
# knowledge-instrument-audit.sh — становится ли знание инструментом или только копится.
# Результат: очередь «знание → инструмент» пуста либо каждый её пункт разобран вердиктом
# Проверка результата: bash scripts/knowledge-instrument-audit.sh — очередь на производство равна 0
#
#
# Повод. 2026-07-29 собеседник спросил: «знания из базы сами формируют действенный инструмент
# или просто копятся?» Замер дал 1,4% — четыре записи из 280 способны дойти до действия.
# Но сам замер случился ПОТОМУ ЧТО СПРОСИЛИ. Без вопроса его бы не было, и отсутствия
# никто бы не заметил: у измерения не было ни владельца, ни срока. Отсюда этот скрипт
# и строка в `scripts/measurements.tsv` с периодом 7 дней.
#
# Что считается «инструментом». Не всякое влияние на контекст, а способность СТОЯТЬ НА ПУТИ
# ДЕЙСТВИЯ: знание с `blocker: true` и рабочими `detection_signals`, которые вычисляются
# перед вызовом инструмента. Инжект в контекст — подсказка; знание, читаемое агентом, —
# справка. Инструментом делает только гейт.
#
# Три уровня, и они меряются отдельно, потому что смешивать их — значит завышать:
#   хранится   — запись существует;
#   доходит    — попадала в контекст (есть в логе инжектов);
#   действует  — blocker: true + непустые сигналы, то есть проверяется перед действием.
#
# Производство. Скрипт не только считает, но и выдаёт ОЧЕРЕДЬ: знания, которые по своим
# признакам должны стать инструментом и ещё не стали. Признаки взяты из `knowledge/META.md`
# (критерии blocker-tier), а не придуманы: `outcome: error`, подтверждений ≥ порога,
# описывает поведение агента. Без очереди отчёт был бы констатацией, а не работой.

set -uo pipefail

REPO="${CLAUDSOUL_REPO:-$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")/.." 2>/dev/null && pwd -P)}"
LESSONS="${LESSONS_DIR:-$HOME/.claude/global-lessons}"
STATE="${STATE_DIR:-$HOME/.claude/hooks/state}"
OUT="${KIA_OUTPUT:-$STATE/knowledge-instrument.md}"
MIN_CONFIRMED="${KIA_MIN_CONFIRMED:-5}"
# Сколько дней пункт очереди может стоять, прежде чем замер покраснеет. Тот же приём, что
# закрыл D46 у эскалаций: растёт число от БЕЗДЕЙСТВИЯ, а не от подкрепления.
QUEUE_MAX_DAYS="${KIA_QUEUE_MAX_DAYS:-30}"

[ -d "$LESSONS" ] || { echo "knowledge-instrument-audit: нет базы знаний ($LESSONS)" >&2; exit 2; }
command -v python3 >/dev/null 2>&1 || { echo "knowledge-instrument-audit: нужен python3" >&2; exit 2; }

python3 - "$LESSONS" "$STATE" "$MIN_CONFIRMED" "$OUT" "$QUEUE_MAX_DAYS" <<'PY'
import json, re, sys, pathlib, datetime, collections, yaml

# --- Канал «не смог» (противник, раунд 1, 2026-08-29) ---
# У замера было ДВА исхода: «отработал, находок нет» (0) и «отработал и нашёл» (1). Третий —
# «не смог отработать» — был невыразим, и потому вырождался в первые два. Необработанное
# исключение даёт код 1, а `measurement-due.sh` читает 1 как НАХОДКУ: ставит отметку прогона
# и уводит вывод в /dev/null. Упавший замер числился выполненным, и следующие 7 дней его
# никто не перезапускал. Отсюда — верхний перехват: любое неожиданное падение выходит
# кодом 2, который тот же measurement-due отличает от находки.
def _die_as_failure(exc_type, exc, tb):
    import traceback, os
    traceback.print_exception(exc_type, exc, tb, file=sys.stderr)
    print("knowledge-instrument-audit: замер НЕ СМОГ отработать — это отказ, а не находка",
          file=sys.stderr)
    os._exit(2)          # именно _exit: sys.exit внутри excepthook код возврата не меняет
sys.excepthook = _die_as_failure

lessons, state, min_conf, out_path = pathlib.Path(sys.argv[1]), pathlib.Path(sys.argv[2]), int(sys.argv[3]), pathlib.Path(sys.argv[4])
try:
    queue_max_days = int(sys.argv[5])
except ValueError:
    print(f"knowledge-instrument-audit: KIA_QUEUE_MAX_DAYS не число: {sys.argv[5]!r}", file=sys.stderr)
    sys.exit(2)

# Нечитаемые поля собираются здесь и НАЗЫВАЮТСЯ. Подстановка значения вместо сообщения о
# нечитаемости — то же, что соврать: подставленное всегда отвечает на вопрос замера, и
# всегда благоприятно (ноль подтверждений — не в очереди, ноль дней — не просрочен).
unreadable = []

# Вердикты, которые ЗАКРЫВАЮТ пункт: «инструментом не станет и вот почему».
# `candidate` сюда не входит по построению — он говорит обратное.
REFUSAL_VERDICTS = {"covered", "inexpressible", "invented"}

# --- Чтение шапки: настоящий разбор YAML, а не построчные шаблоны ---
#
# Корень класса, закрытый здесь (замер 29 августа 2026, три раунда прожарки). Поля читались
# регулярками по строкам, и КАЖДЫЙ раунд приносил новую форму, которую шаблон не знал:
# вердикт `Candidate` с заглавной, `blocker: True`, `outcome: error  # хвост`, пример поля
# в ТЕЛЕ документа, блочный скаляр `|-`, BOM и пустая строка перед `---`, незакрытая шапка,
# дублирующийся ключ. Семь атак трёх раундов — один род: шаблон описывает одну реализацию
# грамматики, а формат имеет грамматику.
#
# Контрфактическая проверка корня: с настоящим разбором ни одна из этих атак не возникает
# НИ ОДНИМ путём — форма перестаёт быть вопросом. Остаётся только семантика (что значит
# значение), и она решается ниже явно.
#
# Предел назван: разбор применяется к ЧТЕНИЮ. Правка знания на месте остаётся построчной,
# потому что round-trip с сохранением комментариев (`ruamel`) в среде отсутствует, а
# комментарии в шапке есть у 19 файлов из 394 — их потеря была бы порчей данных.
#
# Отказ разобрать шапку — НЕ повод подставить благоприятное значение: файл попадает в
# `unreadable` и называется вслух (класс B того же замера).
def parse_fm(text):
    """(словарь, ошибка). Ошибка не None — шапка не разобрана, значения брать неоткуда."""
    body = text.lstrip("\ufeff").lstrip()
    if not body.startswith("---"):
        return {}, "шапки нет"
    end = body.find("\n---", 3)
    if end < 0:
        return {}, "шапка не закрыта"
    try:
        d = yaml.safe_load(body[3:end])
    except Exception as e:
        return {}, f"YAML не разобран: {str(e).splitlines()[0][:60]}"
    if d is None:
        return {}, None
    if not isinstance(d, dict):
        return {}, "шапка не отображение"
    return d, None

def read_jsonl(path):
    """(записи, сколько строк не разобралось). Второе значение — не мусор, а ФАКТ.

    Класс B того же замера: оба читателя журналов молча пропускали битую строку через
    `except: continue`, и числа, выведенные из неполного чтения, отчёт заявлял как
    измеренные. Битая строка в журнале — не гипотеза: одна такая уже стоила проекту
    285 записей из 7665 при разборе `jq` (внутренний архив (не публикуется):1702).

    Контракт чтения обязан различать «прочитал» и «не смог». Пока не различает, незнание
    вынуждено выражаться значением — и выражается благоприятным: меньше строк, меньше
    находок, тише отчёт.
    """
    out, broken = [], 0
    if not path.is_file():
        return out, 0
    for line in path.read_text(errors="replace").splitlines():
        if not line.strip():
            continue
        try:
            out.append(json.loads(line))
        except Exception:
            broken += 1
    return out, broken

def as_text(v):
    """Значение поля строкой — так, как его увидел бы человек в отчёте."""
    if v is None:
        return ""
    if isinstance(v, bool):
        return "true" if v else "false"
    return str(v).strip()

records = [f for f in lessons.glob("*.md") if f.name != "META.md"]
stored = len(records)
known_stems = {f.stem for f in records}

# --- уровень «доходит»: знание встречалось в логе инжектов
reached, reached_30 = set(), set()
log = state / "injection-log.jsonl"
cut = (datetime.date.today() - datetime.timedelta(days=30)).isoformat()
_log_records, _log_broken = read_jsonl(log)
if _log_broken:
    unreadable.append(("injection-log.jsonl", "строк не разобрано", str(_log_broken)))
for d in _log_records:
    f = d.get("file")
    if not f:
        continue
    # Числитель берётся ИЗ БАЗЫ, а колонка называется «Доля базы». Прежде в множество
    # клали значение из журнала как есть — журнал накопительный (3,3 МБ), в нём живут
    # прежние имена и удалённые знания, и с формой `.md` и без. Доля выходила за 100%,
    # то есть отвечала о другом множестве, чем заявляла.
    # Запись журнала описывает КАНДИДАТА; дошедшим знание делает `injected: true`.
    # Активатор пишет шесть кандидатов и инжектирует три — считая все строки, замер
    # мерил ранжирование, а утверждал о достижении. Замер боевого журнала: 11 знаний
    # встречались только с `injected: false` и числились дошедшими, ни разу не дойдя.
    if d.get("injected") is False:
        continue
    stem = f[:-3] if f.endswith(".md") else f
    if stem not in known_stems:
        continue
    reached.add(stem)
    if str(d.get("date", ""))[:10] >= cut:
        reached_30.add(stem)

# --- нарушения: знание было уместно и НЕ применено
# Замер 2026-08-28: разрыв знание→действие — 19 случаев, и пять из них дало одно знание,
# уже стоявшее на высшем уровне (blocker: true, сигналы написаны). Прежде этот журнал
# скрипт не открывал вовсе: он считал, куда знание ДОШЛО, и не считал, где оно НЕ
# сработало. Очередь на производство существует ради второго, а сортировалась по первому.
violations = collections.Counter()
outc = state / "disagreement-outcomes.jsonl"
_outc_records, _outc_broken = read_jsonl(outc)
if _outc_broken:
    unreadable.append(("disagreement-outcomes.jsonl", "строк не разобрано", str(_outc_broken)))
for d in _outc_records:
    if d.get("outcome") == "applicable_not_followed":
        k = str(d.get("knowledge", "")).removesuffix(".md")
        if k:
            violations[k] += 1

acting, broken, predicate, queue, assessed = [], [], [], [], []
blocker_violated = []
for f in records:
    t = f.read_text(errors="replace")
    fm, fm_err = parse_fm(t)
    if fm_err:
        unreadable.append((f.stem, "frontmatter", fm_err))
    def field_of(key):
        return as_text(fm.get(key))
    # YAML сам приводит `true` / `True` / `yes` / `on` к булеву — нормализация регистра
    # перестаёт быть отдельным правилом.
    is_blocker = fm.get("blocker") is True
    _sig_raw = fm.get("detection_signals")
    if _sig_raw is None:
        sig = None
    elif isinstance(_sig_raw, (dict, list)):
        sig = _sig_raw
    else:
        try:
            sig = json.loads(_sig_raw)
        except Exception:
            sig = "bad"
    raw_cc = field_of("confirmed_count") or "0"
    m_cc = re.match(r"-?\d+", raw_cc)
    if m_cc:
        cc = int(m_cc.group(0))          # хвост (комментарий через #) не мешает числу
    else:
        # Ноль здесь был бы ответом на вопрос замера, а не признанием, что поле не
        # прочитано: знание выпадало и из очереди, и из «оценены» — из отчёта целиком.
        cc = 0
        unreadable.append((f.stem, "confirmed_count", raw_cc[:40]))
    outcome = field_of("outcome")
    status = field_of("status")

    if is_blocker:
        if sig in (None, "bad") or not sig:
            broken.append((f.stem, "blocker: true, но сигналов нет или они не разбираются"))
        else:
            acting.append(f.stem)
            if "tool_input_regex" in json.dumps(sig):
                predicate.append(f.stem)
            # Высший уровень укоренённости не гарантирует применения. Такое знание из
            # очереди выпадает по построению («уже гейт»), и его нарушения становились
            # невидимы — а это самый сильный сигнал в отчёте: уровень не помог.
            if violations.get(f.stem):
                blocker_violated.append((violations[f.stem], f.stem, field_of("description")[:96]))
        continue

    # Очередь на производство: признаки из META (критерии blocker-tier).
    # Уже оценённые не предлагаются повторно — иначе отчёт каждую неделю показывал бы
    # один и тот же список, и «очередь» перестала бы означать работу. Вердикт ставится
    # разбором и хранится в самом знании (`instrument_verdict`).
    if f.name.startswith(("pattern-", "principle-")) and outcome == "error" \
       and status != "deprecated" and cc >= min_conf:
        v = field_of("instrument_verdict")
        # Нормализация: побайтовое сравнение выпускало `Candidate` и `candidate,` из
        # очереди — то есть D106 возвращался целиком через опечатку. Поле пишется рукой
        # (15 значений в базе, все рукописные), регистр и пунктуация неизбежны.
        verdict = re.sub(r"[^a-z_]", "", v.split()[0].lower()) if v else ""
        # `candidate` — не выход. Вердикты `covered`/`inexpressible`/`invented` говорят
        # «инструментом не станет и почему»; `candidate` говорит ОБРАТНОЕ — «выразим, но
        # ещё не построен». До 28 августа 2026 он выводил пункт из очереди наравне с
        # отказами, и `pattern-subject-of-measurement-mismatch` простоял так с 29 июля в
        # таблице с заголовком «инструментом не станут», хотя вердикт означал «станет».
        # Реестр, из которого пункт уходит, ничего не построив, не имеет условия выхода —
        # он имеет способ из него исчезнуть (D106).
        # Выпускает из очереди только ЯВНЫЙ ОТКАЗ. Прежнее условие «вердикт есть и он не
        # candidate» — перечень наоборот: любое неизвестное слово молча означало отказ.
        # `candidate` значит «выразим, инструмента ещё нет» и выходом не является.
        if verdict in REFUSAL_VERDICTS:
            assessed.append((verdict, f.stem, field_of("instrument_assessed")))
        else:
            queue.append((violations.get(f.stem, 0), cc, f.stem, field_of("description")[:96]))

# --- Возраст пункта очереди (D106, 2026-08-28) ---
# Очередь имела условие выхода (`instrument_verdict` — разобрали, вердикт записан), но не
# имела СРОКА: пункт мог стоять сколько угодно, потому что стоял в списке. Замер 28 августа
# 2026: `pattern-subject-of-measurement-mismatch` — 28 подтверждений, вердикт `candidate` с
# 29 июля, инструментом не стал; за одну сессию попал в контекст 252 раза, и при нём же
# произошли три случая своего класса подряд.
#
# Приём тот же, что закрыл D46 у эскалаций: у пункта появляется дата ВХОДА, и растёт число
# от бездействия. Дата живёт сбоку от отчёта, а не в самом знании: отчёт пересобирается
# каждый прогон, знание же правится разбором, и запись туда из замера смешала бы
# наблюдение с суждением.
#
# КОНТРПРИМЕР: знание, покинувшее очередь (получило `instrument_verdict`), теряет отметку
# входа — вернувшись позже, оно начинает срок заново, а не тащит прежний.
# Реестр «Уровень не помог» получает тот же выход, что и очередь (D106): дата входа,
# возраст, срок. Прежде выхода не было вовсе — знание с нарушениями стояло в разделе
# неограниченно долго, и раздел, заведённый как САМЫЙ СИЛЬНЫЙ сигнал отчёта, копил записи
# без единого повода их пересмотреть.
#
# Выход у пункта тут иной, чем у очереди: он покидает раздел, когда нарушений больше нет
# (гейт стал применяться) либо когда знанию записан `instrument_verdict` — то есть решено,
# что выше этого уровня его не поднять. Срок нужен, чтобы «нарушения продолжаются» не
# стало фоном: пункт старше порога роняет замер, как и просроченный пункт очереди.
violated_ledger_path = state / "knowledge-instrument-violated.json"

ledger_path = state / "knowledge-instrument-queue.json"
# Файл реестра, который ЕСТЬ, но не читается, — это отказ, а не пустой реестр. Гашение
# через `ledger = {}` списывало все накопленные сроки (99 дней просрочки исчезали) и
# затирало испорченный файл сегодняшними датами, унося улику. Запись неатомарна, так что
# оборванный файл — не гипотеза: два прогона разом, нехватка места, обрыв.
if ledger_path.exists():
    try:
        ledger = json.loads(ledger_path.read_text(errors="replace"))
    except Exception as e:
        print(f"knowledge-instrument-audit: реестр входа {ledger_path} не читается ({e}) — "
              "сроки не списываются, файл не тронут", file=sys.stderr)
        sys.exit(2)
    if not isinstance(ledger, dict):
        print(f"knowledge-instrument-audit: реестр входа {ledger_path} не объект — "
              "сроки не списываются, файл не тронут", file=sys.stderr)
        sys.exit(2)
else:
    ledger = {}

today = datetime.date.today()
in_queue = {name for _, _, name, _ in queue}
# Пункт, вернувшийся в очередь с вердиктом `candidate`, тащит СВОЙ срок: часы пошли в
# день разбора, а не в день, когда починили учёт. Нет записанной даты — считаем с сегодня
# и не выдаём это за измеренный возраст.
assessed_dates = {}
candidate_stems = set()
for f in records:
    if not f.name.startswith(("pattern-", "principle-")):
        continue
    txt = f.read_text(errors="replace")
    _fm2, _ = parse_fm(txt)
    _v = as_text(_fm2.get("instrument_verdict"))
    _vn = re.sub(r"[^a-z_]", "", _v.split()[0].lower()) if _v.split() else ""
    if _vn == "candidate":
        candidate_stems.add(f.stem)
        d = as_text(_fm2.get("instrument_assessed"))
        # Разбор, а не форма: `2026-13-45` регулярку проходил, попадал в реестр и делал
        # возраст пункта нулевым навсегда.
        try:
            datetime.date.fromisoformat(d)
        except ValueError:
            if d:
                unreadable.append((f.stem, "instrument_assessed", d[:40]))
        else:
            assessed_dates[f.stem] = d
# Где дата входа ЗАПИСАНА, а где предположена, различаем явно: без этого «0 дн.» у пункта
# с неизвестной датой и у вошедшего сегодня — одна ячейка. На боевой базе так выглядели все
# шесть пунктов очереди, включая `pattern-subject-of-measurement-mismatch`, ради которого
# D106 и делался: вердикт `candidate` у него с 29 июля, а отчёт показывал «0 дн.».
# Предположенной дата входа считается только там, где она ДОЛЖНА была быть и её нет:
# у пункта с вердиктом `candidate` часы пошли в день разбора, а он не записан. Пункт,
# впервые попавший в очередь сегодня и вердикта не имеющий, вошёл сегодня по-настоящему —
# помечать его «дата не записана» значило бы соврать в другую сторону.
def _since(v):
    return v.get("since") if isinstance(v, dict) else v

def _guessed(v):
    return bool(isinstance(v, dict) and v.get("source") == "guessed")

for name in in_queue:
    if name not in ledger:
        if name in assessed_dates:
            ledger[name] = {"since": assessed_dates[name], "source": "assessed"}
        elif name in candidate_stems:
            # Дата ПРЕДПОЛОЖЕНА: вердикт `candidate` есть, а день разбора не записан.
            # Провенанс хранится рядом с датой, иначе он не переживает прогон.
            ledger[name] = {"since": today.isoformat(), "source": "guessed"}
        else:
            ledger[name] = {"since": today.isoformat(), "source": "entered"}
    elif not isinstance(ledger[name], dict):
        # Плоская форма прежних прогонов: происхождение неизвестно, так и записываем —
        # объявить её измеренной значило бы повторить ту же ложь задним числом.
        ledger[name] = {"since": _since(ledger[name]), "source": "unknown"}
# Ушедшие из очереди отметку не сохраняют — но только те, кто ушёл ПО СУЩЕСТВУ.
# Выпавший из-за нечитаемого поля не «покинул очередь», он не был прочитан: стирать ему
# срок значит списывать просрочку опечаткой, которую завтра исправят.
_unreadable_stems = {stem for stem, _, _ in unreadable}
ledger = {k: v for k, v in ledger.items() if k in in_queue or k in _unreadable_stems}

def queue_age(name):
    """Возраст пункта либо None, если он НЕИЗВЕСТЕН.

    Ноль здесь был бы ответом на вопрос замера: неразбираемая дата давала «вечно молод»,
    и такой пункт не догонял НИКАКОЙ порог. Неизвестный возраст считается просроченным —
    сторона безопасная: пункт попадёт на глаза, а не растворится.
    """
    raw = _since(ledger.get(name))
    try:
        d = datetime.date.fromisoformat(str(raw))
    except Exception:
        return None
    age = (today - d).days
    return None if age < 0 else age      # дата из будущего — не «минус N дней», а «неизвестно»

def age_mark(name):
    a = queue_age(name)
    if a is None:
        return "неизвестно ⏰"
    if _guessed(ledger.get(name)):
        # Возраст называется ВСЕГДА, а происхождение даты — оговоркой рядом. Прежняя
        # ячейка печатала только оговорку, и пункт, простоявший 240 дней, выглядел так же,
        # как вошедший вчера: искать просроченный в таблице было не по чему, хотя отчёт
        # рядом писал «Просрочено: 1». Починка прошлого раунда закрыла ложь «0 дн.» и
        # завела на её месте молчание — а молчание тот же ответ, только неопровержимый.
        return f"≥ {a} дн. ⏰ (дата входа не записана)" if a > queue_max_days \
            else f"≥ {a} дн. (дата входа не записана)"
    if isinstance(ledger.get(name), dict) and ledger[name].get("source") == "unknown":
        return f"{a} дн. (происхождение даты неизвестно)"
    return f"{a} дн." + (" ⏰" if a > queue_max_days else "")

ledger_path.parent.mkdir(parents=True, exist_ok=True)
_tmp = ledger_path.with_suffix(".json.tmp")
_tmp.write_text(json.dumps(ledger, ensure_ascii=False, indent=1, sort_keys=True), encoding="utf-8")
_tmp.replace(ledger_path)      # атомарно: оборванный файл не переживёт запись

# Реестр нарушений: та же механика, что у очереди, и та же честность про происхождение даты.
try:
    vled = json.loads(violated_ledger_path.read_text(errors="replace"))
    if not isinstance(vled, dict):
        vled = {}
except FileNotFoundError:
    vled = {}
except Exception:
    print(f"knowledge-instrument-audit: реестр {violated_ledger_path} не читается — "
          "сроки не списываются, файл не тронут", file=sys.stderr)
    sys.exit(2)

in_violated = {name for _, name, _ in blocker_violated}
for name in in_violated:
    vled.setdefault(name, today.isoformat())
vled = {k: v for k, v in vled.items() if k in in_violated}

def violated_age(name):
    try:
        return (today - datetime.date.fromisoformat(str(vled.get(name)))).days
    except Exception:
        return None

_vtmp = violated_ledger_path.with_suffix(".json.tmp")
violated_ledger_path.parent.mkdir(parents=True, exist_ok=True)
_vtmp.write_text(json.dumps(vled, ensure_ascii=False, indent=1, sort_keys=True), encoding="utf-8")
_vtmp.replace(violated_ledger_path)

violated_overdue = sorted(
    (violated_age(n) if violated_age(n) is not None else 10**6, n)
    for n in in_violated
    if violated_age(n) is None or violated_age(n) > queue_max_days)

overdue = sorted((queue_age(n) if queue_age(n) is not None else 10**6, n)
                 for n in in_queue
                 if queue_age(n) is None or queue_age(n) > queue_max_days)

# Порядок: сперва НАРУШЕНИЯ, потом подтверждения. Подтверждения говорят, где знание
# срабатывало; очередь спрашивает обратное — где оно не дошло до действия.
queue.sort(reverse=True)
blocker_violated.sort(reverse=True)

def pct(n):
    return f"{100 * n / stored:.1f}%" if stored else "—"

def stored_pct():
    # Доля хранимого от хранимого — 100% ровно тогда, когда хранить есть что. У пустой
    # базы доли нет, как и у всех остальных строк той же таблицы.
    return "100%" if stored else "—"

lines = []
lines.append("# Знание → инструмент")
lines.append("")
lines.append(f"Замер: {datetime.date.today().isoformat()}. Период — 7 дней (`scripts/measurements.tsv`).")
lines.append("")
lines.append("Инструментом считается способность стоять НА ПУТИ ДЕЙСТВИЯ: `blocker: true` плюс")
lines.append("рабочие `detection_signals`. Инжект в контекст — подсказка, не инструмент.")
lines.append("")
lines.append("| Уровень | Сколько | Доля базы |")
lines.append("|---------|---------|-----------|")
lines.append(f"| хранится | {stored} | {stored_pct()} |")
lines.append(f"| доходило до контекста (за всю историю) | {len(reached)} | {pct(len(reached))} |")
lines.append(f"| доходило за 30 дней | {len(reached_30)} | {pct(len(reached_30))} |")
lines.append(f"| **действует** (гейт перед действием) | **{len(acting)}** | **{pct(len(acting))}** |")
lines.append(f"| из них выражают правило, а не перечень | {len(predicate)} | {pct(len(predicate))} |")
lines.append("")

if broken:
    lines.append("## Объявлены инструментом, но не работают")
    lines.append("")
    for name, why in broken:
        lines.append(f"- `{name}` — {why}")
    lines.append("")

if unreadable:
    lines.append(f"**Не прочитано полей: {len(unreadable)}.** Такое знание могло не попасть")
    lines.append("в счёт — подстановка значения вместо признания нечитаемости отвечает на")
    lines.append("вопрос замера вместо него.")
    for stem, fld, raw in unreadable:
        lines.append(f"- `{stem}`: `{fld}` = `{raw}`")
    lines.append("")
lines.append("## Очередь на производство")
lines.append("")
if queue:
    lines.append(f"Знания с `outcome: error` и подтверждениями ≥ {min_conf}, ещё не ставшие гейтом.")
    lines.append("Порядок — сперва по НАРУШЕНИЯМ (знание было уместно и не применено), потом по")
    lines.append("подтверждениям. Подтверждения говорят, где знание срабатывало; очередь спрашивает")
    lines.append("обратное — где оно не дошло до действия. Признаки взяты из `knowledge/META.md`.")
    lines.append("")
    lines.append(f"Срок стояния — {queue_max_days} дн. Просроченный пункт роняет замер: очередь без срока")
    lines.append("это не очередь, а список (D106).")
    lines.append("")
    lines.append("| Нарушений | Подтверждений | В очереди | Знание | О чём |")
    lines.append("|-----------|---------------|-----------|--------|-------|")
    for vio, cc, name, desc in queue:
        lines.append(f"| {vio} | {cc} | {age_mark(name)} | `{name}` | {desc} |")
    lines.append("")
    if overdue:
        lines.append(f"**Просрочено: {len(overdue)}.** Пункт покидает очередь одним из трёх способов —")
        lines.append("стал гейтом, признан невыразимым с доказательством (`instrument_verdict`), снят")
        lines.append("решением владельца. Четвёртого способа, «стоять дальше», нет.")
        lines.append("")
    lines.append("**Что значит «стать инструментом».** Написать `detection_signals`, выведенные из")
    lines.append("ИЗМЕРЕННЫХ проявлений, а не придуманные: придуманный словарь уже стоил проекту")
    lines.append("в v1.13.3 — девять срабатываний за 214 сессий и ноль на реальных поправках.")
    lines.append("Если проявления описываются правилом, а не списком, сигнал пишется предикатом")
    lines.append("(`tool_input_regex`), иначе класс будет ловиться постфактум по одной форме.")
else:
    if unreadable:
        # «Пусто» здесь было бы утверждением о МИРЕ, выведенным из отказа прочитать вход.
        lines.append(f"Очередь пуста, но {len(unreadable)} пол(я/ей) не прочитано — часть знаний")
        lines.append("могла не попасть в счёт по нечитаемости, а не по существу. Список выше.")
    else:
        lines.append(f"Пусто: неоценённых знаний с `outcome: error` и подтверждениями ≥ {min_conf} нет.")
lines.append("")

if blocker_violated:
    lines.append("## Уровень не помог: гейт есть, а знание не применено")
    lines.append("")
    lines.append("Знания с `blocker: true` и рабочими сигналами, которые всё равно были уместны")
    lines.append("и не применены. В очередь они не попадают по построению («уже гейт»), и без")
    lines.append("этого раздела их нарушения невидимы — а это самый сильный сигнал отчёта:")
    lines.append("высшая ступень укоренённости не дала применения.")
    lines.append("")
    lines.append(f"Срок стояния — {queue_max_days} дн., как у очереди. Пункт покидает раздел, когда")
    lines.append("нарушения прекратились либо знанию записан `instrument_verdict`; просроченный роняет")
    lines.append("замер, чтобы «нарушения продолжаются» не стало фоном.")
    lines.append("")
    lines.append("| Нарушений | В разделе | Знание | О чём |")
    lines.append("|-----------|-----------|--------|-------|")
    for vio, name, desc in blocker_violated:
        a = violated_age(name)
        mark = "неизвестно ⏰" if a is None else f"{a} дн." + (" ⏰" if a > queue_max_days else "")
        lines.append(f"| {vio} | {mark} | `{name}` | {desc} |")
    lines.append("")
    if violated_overdue:
        lines.append(f"**Просрочено: {len(violated_overdue)}.** Гейт стоит, нарушения идут дольше срока —")
        lines.append("значит уровень не помогает и решение о нём откладывать больше нечем.")
        lines.append("")

if assessed:
    lines.append("## Оценены: инструментом не станут")
    lines.append("")
    lines.append("Разобраны, вердикт записан в самом знании. Повторно в очередь не попадают.")
    lines.append("")
    counts = collections.Counter(v for v, _, _ in assessed)
    lines.append("| Вердикт | Знание | Когда |")
    lines.append("|---------|--------|-------|")
    for v, name, when in sorted(assessed):
        lines.append(f"| `{v}` | `{name}` | {when or '—'} |")
    lines.append("")
    lines.append(f"Итог оценки: " + ", ".join(f"{k} — {n}" for k, n in counts.most_common()) + ".")
    lines.append("")
    lines.append("**Что это значит.** `inexpressible` — не лень и не недоработка: у проявлений нет")
    lines.append("признака, наблюдаемого В МОМЕНТ действия. Знание о суждении (спросил ли о")
    lines.append("потребности, полно ли сделал, не показалось ли очевидным) такого признака не имеет")
    lines.append("в принципе — при нынешнем наборе матчеров. Знание о синтаксисе и артефактах имеет.")
    lines.append("Поэтому доля «действует» — не задолженность, которую надо выбрать, а свойство")
    lines.append("того, из чего база состоит.")
    lines.append("")

lines.append("## Чего этот замер НЕ говорит")
lines.append("")
lines.append("Он меряет СПОСОБНОСТЬ знания встать на пути действия, а не влияние на решение.")
lines.append("Влияние не измерено ни одним прибором системы: запись `pending` создаётся в момент")
lines.append("инжекта, а закрывающий исход пишет тот же агент про самого себя. Пока это так,")
lines.append("«действует» означает «проверяется перед действием», а не «меняет действие».")
lines.append("")

out_path.parent.mkdir(parents=True, exist_ok=True)
out_path.write_text("\n".join(lines) + "\n", encoding="utf-8")

# stdout — короткая сводка для дайджеста и для человека
print(f"знание → инструмент: хранится {stored}, доходит {len(reached)}, действует {len(acting)} ({pct(len(acting))})")
if broken:
    print(f"  объявлены инструментом, но сломаны: {len(broken)}")
print(f"  очередь на производство: {len(queue)}; оценены и не станут: {len(assessed)}")
if overdue:
    print(f"  ПРОСРОЧЕНО в очереди (> {queue_max_days} дн.): {len(overdue)}")
    for age, name in sorted(overdue, reverse=True):
        a = queue_age(name)
        print(f"    · {'возраст неизвестен' if a is None else str(a) + ' дн.'} — {name}")
if unreadable:
    print(f"  НЕ ПРОЧИТАНО полей: {len(unreadable)} — знание могло не попасть в счёт")
    for stem, fld, raw in unreadable:
        print(f"    · {stem}: {fld} = {raw!r}")
print(f"  отчёт: {out_path}")
# Код 1 — «отработал и нашёл», его measurement-due отличает от отказа (код ≥ 2).
# Нечитаемое поле — НАХОДКА, а не «отработал, находок нет»: замер не смог прочесть часть
# своего входа, и молчание об этом ставит отметку прогона на неделю вперёд.
sys.exit(1 if (overdue or violated_overdue or unreadable) else 0)
PY
