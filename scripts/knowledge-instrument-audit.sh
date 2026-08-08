#!/usr/bin/env bash
# knowledge-instrument-audit.sh — становится ли знание инструментом или только копится.
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

[ -d "$LESSONS" ] || { echo "knowledge-instrument-audit: нет базы знаний ($LESSONS)" >&2; exit 2; }
command -v python3 >/dev/null 2>&1 || { echo "knowledge-instrument-audit: нужен python3" >&2; exit 2; }

python3 - "$LESSONS" "$STATE" "$MIN_CONFIRMED" "$OUT" <<'PY'
import json, re, sys, pathlib, datetime, collections

lessons, state, min_conf, out_path = pathlib.Path(sys.argv[1]), pathlib.Path(sys.argv[2]), int(sys.argv[3]), pathlib.Path(sys.argv[4])

def field(text, key):
    m = re.search(rf"^{key}:\s*(.*)$", text, re.M)
    return m.group(1).strip().strip('"') if m else ""

def signals(text):
    m = re.search(r"detection_signals: \|\n((?:  .*\n)+)", text)
    if not m:
        return None
    try:
        return json.loads("".join(l[2:] for l in m.group(1).splitlines(True)))
    except Exception:
        return "bad"

records = [f for f in lessons.glob("*.md") if f.name != "META.md"]
stored = len(records)

# --- уровень «доходит»: знание встречалось в логе инжектов
reached, reached_30 = set(), set()
log = state / "injection-log.jsonl"
cut = (datetime.date.today() - datetime.timedelta(days=30)).isoformat()
if log.is_file():
    for line in log.read_text(errors="replace").splitlines():
        try:
            d = json.loads(line)
        except Exception:
            continue
        f = d.get("file")
        if not f:
            continue
        reached.add(f)
        if str(d.get("date", ""))[:10] >= cut:
            reached_30.add(f)

acting, broken, predicate, queue, assessed = [], [], [], [], []
for f in records:
    t = f.read_text(errors="replace")
    is_blocker = bool(re.search(r"^blocker: true", t, re.M))
    sig = signals(t)
    try:
        cc = int(field(t, "confirmed_count") or 0)
    except ValueError:
        cc = 0
    outcome = field(t, "outcome")
    status = field(t, "status")

    if is_blocker:
        if sig in (None, "bad") or not sig:
            broken.append((f.stem, "blocker: true, но сигналов нет или они не разбираются"))
        else:
            acting.append(f.stem)
            if "tool_input_regex" in json.dumps(sig):
                predicate.append(f.stem)
        continue

    # Очередь на производство: признаки из META (критерии blocker-tier).
    # Уже оценённые не предлагаются повторно — иначе отчёт каждую неделю показывал бы
    # один и тот же список, и «очередь» перестала бы означать работу. Вердикт ставится
    # разбором и хранится в самом знании (`instrument_verdict`).
    if f.name.startswith(("pattern-", "principle-")) and outcome == "error" \
       and status != "deprecated" and cc >= min_conf:
        v = field(t, "instrument_verdict")
        if v:
            assessed.append((v.split()[0] if v else "?", f.stem, field(t, "instrument_assessed")))
        else:
            queue.append((cc, f.stem, field(t, "description")[:96]))

queue.sort(reverse=True)

def pct(n):
    return f"{100 * n / stored:.1f}%" if stored else "—"

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
lines.append(f"| хранится | {stored} | 100% |")
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

lines.append("## Очередь на производство")
lines.append("")
if queue:
    lines.append(f"Знания с `outcome: error` и подтверждениями ≥ {min_conf}, ещё не ставшие гейтом.")
    lines.append("Порядок — по числу подтверждений. Признаки взяты из `knowledge/META.md`.")
    lines.append("")
    lines.append("| Подтверждений | Знание | О чём |")
    lines.append("|---------------|--------|-------|")
    for cc, name, desc in queue:
        lines.append(f"| {cc} | `{name}` | {desc} |")
    lines.append("")
    lines.append("**Что значит «стать инструментом».** Написать `detection_signals`, выведенные из")
    lines.append("ИЗМЕРЕННЫХ проявлений, а не придуманные: придуманный словарь уже стоил проекту")
    lines.append("в v1.13.3 — девять срабатываний за 214 сессий и ноль на реальных поправках.")
    lines.append("Если проявления описываются правилом, а не списком, сигнал пишется предикатом")
    lines.append("(`tool_input_regex`), иначе класс будет ловиться постфактум по одной форме.")
else:
    lines.append(f"Пусто: неоценённых знаний с `outcome: error` и подтверждениями ≥ {min_conf} нет.")
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
print(f"  отчёт: {out_path}")
PY
