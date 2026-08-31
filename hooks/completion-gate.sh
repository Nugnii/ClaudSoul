#!/usr/bin/env bash
# completion-gate.sh — Stop: пункт, объявленный ☑, сверяется со СВОИМ критерием, а не с отчётом.
# en: Stop hook — a backlog item declared done is judged by its own check command, not by the report.
#
# Инженерная эскалация pattern-completion-by-internal-proxy (confirmed 14 ≥ порога 12,
# заявка открыта 2026-08-16, исполнена 2026-08-31): «задача объявляется завершённой по
# внутреннему прокси (объём сделанного, факт артефакта, отчёт исполнителя), а не сверкой
# с внешним явным критерием». У пункта долга внешний критерий машинный — строка
# `**Проверка.** \`команда\` → 0` из контракта BACKLOG.md. Метку ☑ ставит исполнитель;
# этот страж прогоняет команду пункта и верит коду возврата.
#
# ДВА РУБЕЖА одного гейта. Здесь — обратная связь В ТОЙ ЖЕ СЕССИИ (инжект на Stop);
# неотвратимость — в `scripts/backlog-archive.sh`: ☑ с красной «Проверкой» в архив не
# переносится. Инжект, а не отказ (ADR-011): Stop нечего отказывать — действие уже
# совершено; последствие одно, но точка отказа — перенос, и она уже держится архиватором.
#
# НАЗВАННЫЙ ПРЕДЕЛ. Покрыт только пункт долга: у «скилл выполнен» и «задача сделана» нет
# машинного события завершения и машинного критерия — их слой держат skill-review-check
# (контракт DoD в файле скилла) и дисциплина; заявка эскалации закрыта в той части, где
# у завершения есть носитель. Пункты без D-номера и с номером < CG_MIN_ID (200, порог
# контракта) не проверяются — как в архиваторе, задним числом контракт не вменяется.
# Условие снятия: у «скилл выполнен» / «задача сделана» появится машинный носитель
# завершения с исполнимой проверкой (аналог строки «Проверка» у пункта долга) — тогда
# гейт расширяется на этот слой. Формулировка едина с модульным доком (single source).
#
# ДВА БЭКЛОГА, как у backlog-touch-check: долг ClaudSoul (абсолютный путь) + локальный
# долг проекта сессии (по cwd). Кэш по mtime: файл, чьи ☑ уже прошли зелёными и с тех
# пор не менялся, повторно не гоняется — Stop не платит за неизменное.
#
# Input  (stdin): {session_id, cwd, ...} (Stop JSON)
# Output (stdout): {systemMessage} либо пусто
# Exit:  always 0 — страж деградирует молча.
set -uo pipefail

command -v jq >/dev/null 2>&1 || exit 0
command -v python3 >/dev/null 2>&1 || exit 0
INPUT=$(cat 2>/dev/null) || exit 0
[ -n "$INPUT" ] || exit 0

PATHS_LIB="${PATHS_LIB:-$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" 2>/dev/null && pwd)/paths-lib.sh}"
[ -f "$PATHS_LIB" ] || PATHS_LIB="$HOME/.claude/hooks/paths-lib.sh"
# shellcheck source=/dev/null
[ -f "$PATHS_LIB" ] && . "$PATHS_LIB"
PORTABLE_LIB="${PORTABLE_LIB:-$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" 2>/dev/null && pwd)/portable-lib.sh}"
[ -f "$PORTABLE_LIB" ] || PORTABLE_LIB="$HOME/.claude/hooks/portable-lib.sh"
# shellcheck source=/dev/null
[ -f "$PORTABLE_LIB" ] && . "$PORTABLE_LIB"

STATE="${STATE_DIR:-$HOME/.claude/hooks/state}"
mkdir -p "$STATE" 2>/dev/null || exit 0

BACKLOG="${CG_BACKLOG:-${CLAUDSOUL_ROOT:-$HOME/My Project/ClaudSoul}/BACKLOG.md}"
CWD=$(printf '%s' "$INPUT" | jq -r '.cwd // ""' 2>/dev/null)
LOCAL_BACKLOG="${CG_LOCAL_BACKLOG:-}"
if [ -z "$LOCAL_BACKLOG" ] && [ -n "$CWD" ] && command -v find_project_root >/dev/null 2>&1; then
    _root=$(find_project_root "$CWD")
    [ -n "$_root" ] && [ -f "$_root/BACKLOG.md" ] && LOCAL_BACKLOG="$_root/BACKLOG.md"
fi
[ "${LOCAL_BACKLOG:-}" = "$BACKLOG" ] && LOCAL_BACKLOG=""

RED=""
# Оба пути В КАВЫЧКАХ: незакавыченный $LOCAL_BACKLOG дробился по пробелу пути
# («My Project/…»), и локальный бэклог таких проектов молча выпадал из проверки
# (прожарка 31.08, атака adv5 spaced_local_backlog). Пустой LOCAL отсекает -n.
for f in "$BACKLOG" "$LOCAL_BACKLOG"; do
    [ -n "$f" ] && [ -f "$f" ] || continue
    _mt=""
    command -v file_mtime >/dev/null 2>&1 && _mt=$(file_mtime "$f" 2>/dev/null)
    _key=$(printf '%s' "$f" | cksum 2>/dev/null | awk '{print $1}')
    OKF="$STATE/completion-gate-${_key:-0}.ok"
    if [ -n "$_mt" ] && [ -f "$OKF" ] && [ "$(cat "$OKF" 2>/dev/null)" = "$_mt" ]; then
        continue
    fi
    _out=$(CG_FILE="$f" python3 - <<'PY' 2>/dev/null
import os, re, subprocess

path = os.environ["CG_FILE"]
min_id = int(os.environ.get("CG_MIN_ID", "200"))
max_runs = int(os.environ.get("CG_MAX", "3"))
timeout = int(os.environ.get("CG_TIMEOUT", "60"))
# errors="replace": один битый байт в markdown не имеет права онеметь стража —
# прожарка 31.08 показала: краш до первого print читался бashем как «чисто» и
# ОТРАВЛЯЛ кэш зелёным (атака cg_nonutf8_false_green).
text = open(path, encoding="utf-8", errors="replace").read()

# Предмет пункта — правило backlog-lib.sh (обе вёрстки: список и заголовок);
# метки альтернативой литералов, не классом — тот же байтовый капкан mawk/C-локали.
# Квантор ЛЕНИВЫЙ: метка пункта — ПЕРВЫЙ глиф строки, как у архиватора и backlog-lib.
# Жадный [^|\n]* откатывался к ПОСЛЕДНЕЙ метке, и «### D200 ☑ … (было ◐)» читался
# открытым — два парсера одного контракта расходились (атака cg_mark_backtrack_blind).
item_re = re.compile(r'^(?:- |#{2,6} )[^|\n]*?(☐|◐|☑|⊘)')
items, cur = [], None
for ln in text.splitlines(True):
    m = item_re.match(ln)
    if m:
        if cur: items.append(cur)
        cur = [m.group(1), ln, []]
    elif re.match(r'^#{2,6} ', ln):
        if cur: items.append(cur)
        cur = None
    elif cur:
        cur[2].append(ln)
if cur: items.append(cur)

runs = 0
partial = False
for mk, head, body_lines in items:
    if mk != "☑":
        continue
    idm = re.search(r'D(\d+)', head)
    if not idm or int(idm.group(1)) < min_id:
        continue
    body = "".join(body_lines)
    # ВСЕ строки «Проверки», не первая: пункт с двумя строками судится всеми — иначе
    # красная вторая молча проезжала за зелёной первой (прожарка 31.08, атака adv6).
    checks = list(re.finditer(r'\*\*Проверка\.\*\*\s*`([^`]+)`', body))
    if not checks:
        continue   # отсутствие строки — предмет архиватора, не этого стража
    for cm in checks:
        if runs >= max_runs:
            partial = True   # подлежало проверке и не проверено — покрытие частичное
            break
        # Команда исполняется КАК ЕСТЬ: прежний " ".join(split()) склеивал многострочную
        # команду в другую (перенос — не пробел: `a=ok<NL>[ "$a" = ok ]` превращался в
        # env-присваивание для `[`) — bash переносы штатны, нормализация только в показе.
        cmd = cm.group(1).strip()
        runs += 1
        try:
            rc = subprocess.run(["bash", "-c", cmd], capture_output=True,
                                cwd=os.path.dirname(os.path.abspath(path)) or ".",
                                timeout=timeout).returncode
        except Exception:
            rc = 125
        if rc != 0:
            disp = " ".join(cmd.split())
            print(f"D{idm.group(1)} (rc={rc}): `{disp[:110]}`")

# Статус-строка — второй сигнал канала. Без неё пустой stdout значил РАЗНОЕ:
# «проверено, чисто», «питон упал», «не дошли до пункта за лимитом» — и всё это
# кэшировалось зелёным (корень трёх атак прожарки 31.08). Кэшировать можно только
# явное «ok»; отсутствие статуса = сбой разбора, «partial» = не всё проверено.
print("#CG_STATUS partial" if partial else "#CG_STATUS ok")
PY
)
    _st=$(printf '%s\n' "$_out" | grep '^#CG_STATUS ' | tail -1 | awk '{print $2}')
    _out=$(printf '%s\n' "$_out" | grep -v '^#CG_STATUS ' | grep -v '^$' || true)
    if [ -n "$_out" ]; then
        RED="${RED}${RED:+
}$_out"
    elif [ "$_st" = "ok" ] && [ -n "$_mt" ]; then
        # Зелёный кэш пишется ТОЛЬКО на явном «ok»: сбой питона (нет статуса) и
        # частичное покрытие («partial», ☑-пунктов с командой больше CG_MAX) кэша
        # не получают — файл перечитается следующим Stop, а неотвратимость держит
        # архиватор, у которого лимита нет.
        printf '%s\n' "$_mt" > "$OKF" 2>/dev/null || true
    fi
done

[ -n "$RED" ] || exit 0

MSG="⚠️ completion-gate: закрытие расходится со своим же критерием:
$RED
Метку ☑ держит команда пункта, а не отчёт. Исполнимо без разрешения: почини мир до зелёной команды либо верни метке ◐ — красное ☑ архиватор не унесёт."
jq -n --arg m "$MSG" '{systemMessage: $m}' 2>/dev/null || true
exit 0
