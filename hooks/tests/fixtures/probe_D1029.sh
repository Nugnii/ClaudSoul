#!/usr/bin/env bash
# СУДИТ: hooks/five-whys-gate.sh
# probe_D1029.sh — замысел D1029 («отказ снимает карта») отклонён владельцем 23 октября 2026 (⊘, дубль архитектуры);
# ноги судят нынешний договор (D1272): чтения и сама запись отказа не снимают — снимает исход, сверенный с записью
# (D1033, D1104); запись в носитель исхода через Edit/Write и одиночное `cat >>` не блокируется, `sed -i` — под отказом
# (D1036).
#
# Повод (23 октября 2026): в сессиях ProjectA 25414236 и ClaudSoul 73784af8 — 22 отказа, ни один не
# снят записью в карту или пункт; снимали их чтения тех самых мест, которые потом латались. Пять
# отказов из 22 били запись в носитель исхода через Bash (дописать SESSION.md, `sed -i` по
# BACKLOG.md, коммит бэклога), а запись в ROOTS.md страж отбивал всегда.
#
# Код: 0 — все ноги держат; 1 — нога красная (названа); 2 — нечем мерить.
set -uo pipefail
REPO="${CLAUDSOUL_REPO:-$(cd "$(dirname "$0")/../../.." && pwd)}"
HOOK="$REPO/hooks/five-whys-gate.sh"
[ -f "$HOOK" ] || exit 2
command -v jq >/dev/null 2>&1 || exit 2
T=$(mktemp -d) || exit 2
trap 'rm -rf "$T"' EXIT
export STATE_DIR="$T/state"; mkdir -p "$STATE_DIR"
P="$T/proj"; Q="$T/nomap"; mkdir -p "$P/hooks" "$Q/hooks"
printf '# ROOTS\n\n## R1 — x\n' > "$P/ROOTS.md"
printf '# BACKLOG\n\n- ☐ **D1** x\n' > "$P/BACKLOG.md"
RED=0
red() { RED=1; echo "КРАСНАЯ: $1"; }

tr_new() {   # tr_new <файл> — реплика собеседника и ответ без разбора
    printf '{"type":"user","message":{"role":"user","content":[{"type":"text","text":"чини"}]}}\n' > "$1"
    jq -cn '{type:"assistant",message:{role:"assistant",content:[{type:"text",text:"Правлю строку."}]}}' >> "$1"
}
add_read() { jq -cn --arg f "$2" '{type:"assistant",message:{role:"assistant",content:[{type:"tool_use",name:"Read",input:{file_path:$f}}]}}' >> "$1"; }
write() {    # write <sid> <cwd> <file_path> <транскрипт>
    jq -cn --arg s "$1" --arg d "$2" --arg f "$3" --arg p "$4" \
      '{session_id:$s, transcript_path:$p, hook_event_name:"PreToolUse", tool_name:"Write", cwd:$d, tool_input:{file_path:$f, content:"x"}}' \
      | bash "$HOOK" 2>/dev/null
}
bashc() {    # bashc <sid> <cwd> <команда> <транскрипт>
    jq -cn --arg s "$1" --arg d "$2" --arg c "$3" --arg p "$4" \
      '{session_id:$s, transcript_path:$p, hook_event_name:"PreToolUse", tool_name:"Bash", cwd:$d, tool_input:{command:$c}}' \
      | bash "$HOOK" 2>/dev/null
}
denied() { [ "$(jq -r '.hookSpecificOutput.permissionDecision // ""' <<< "${1:-}" 2>/dev/null)" = "deny" ]; }
setup() {    # setup <sid> → путь расшифровки; повод с правом на отказ — полоса провалов
    touch "$STATE_DIR/error_streak_fired_$1"; tr_new "$T/$1.jsonl"; printf '%s' "$T/$1.jsonl"
}

# 1. Проект с картой: три чтения отказ НЕ снимают.
TR=$(setup a); write a "$P" "$P/hooks/x.sh" "$TR" >/dev/null
add_read "$TR" "$P/hooks/a.sh"; add_read "$TR" "$P/hooks/b.sh"; add_read "$TR" "$P/hooks/c.sh"
denied "$(write a "$P" "$P/hooks/x.sh" "$TR")" || red "в проекте с ROOTS.md три чтения сняли отказ"

# 2. Проект с картой: правка ROOTS.md после повода отказ НЕ снимает. Прежде нога ждала обратного — отклонённый замысел
# D1029; по D1104 запись сама отказа не снимает, снимает исход, сверенный с записью (D1272).
TR=$(setup b); write b "$P" "$P/hooks/x.sh" "$TR" >/dev/null
printf '\n## R2 — y\n' >> "$P/ROOTS.md"
denied "$(write b "$P" "$P/hooks/x.sh" "$TR")" || red "правка ROOTS.md сама сняла отказ — по D1104 снимает исход"

# 3. Новый пункт долга после повода отказ НЕ снимает — по той же причине (D1104, D1272).
TR=$(setup h); write h "$P" "$P/hooks/x.sh" "$TR" >/dev/null
printf '\n- ☐ **D2** y\n' >> "$P/BACKLOG.md"
denied "$(write h "$P" "$P/hooks/x.sh" "$TR")" || red "новый пункт в BACKLOG.md сам снял отказ — по D1104 снимает исход"

# 4. Запись в саму карту не блокируется.
TR=$(setup c)
denied "$(write c "$P" "$P/ROOTS.md" "$TR")" && red "запись в ROOTS.md отбита"

# 5. Bash: одиночное дописывание `cat >>` в запись не блокируется; `sed -i` по BACKLOG.md — под отказом: из Bash
# освобождается только `cat >> <запись> <<'М'`, у неё одной квантор полон (D1036, решение 5 сентября 2026). Прежде нога
# ждала, что и `sed -i` пройдёт, — отклонённый замысел D1029 (D1272).
TR=$(setup d)
denied "$(bashc d "$P" "cat >> SESSION.md <<'EOF'
## запись
EOF" "$TR")" && red "дописывание SESSION.md через Bash отбито"
denied "$(bashc d "$P" "cat >> BACKLOG.md <<'EOF'
- ☐ **D3** z
EOF" "$TR")" && red "дописывание BACKLOG.md через cat >> отбито"
denied "$(bashc d "$P" "sed -i '' 's/^- ☐ \*\*D1\*\*/- ◐ **D1**/' BACKLOG.md && grep -n D1 BACKLOG.md" "$TR")" \
    || red "sed -i по BACKLOG.md прошёл — из Bash освобождается только cat >> (D1036)"

# Контроль 6: приманка — носитель рядом с правкой механизма — отказ остаётся.
TR=$(setup f)
denied "$(bashc f "$P" "cat >> SESSION.md <<'EOF'
x
EOF
sed -i '' 's/a/b/' hooks/x.sh" "$TR")" || red "приманка SESSION.md сняла отказ с правки hooks/x.sh"
denied "$(bashc f "$P" "sed -i '' -e 's/a/b/' hooks/x.sh BACKLOG.md" "$TR")" \
    || red "sed -i с -e: скрипт принят за файл, правка hooks/x.sh прошла"

# Контроль 7: проект без карты — три чтения отказ НЕ снимают. Прежде нога ждала обратного («как прежде»), но договор
# сменили D1033 и D1035: отказ снимает названный исход либо след разбора, а чтения — нигде, и с карты это не зависит.
# Нога краснела на исправном страже (прибор свидетелей-атак числил её рамкой, не собравшейся и без выхолащивания, —
# D1222, 8 ноября 2026); теперь она судит нынешнее правило.
TR=$(setup g); write g "$Q" "$Q/hooks/x.sh" "$TR" >/dev/null
add_read "$TR" "$Q/hooks/a.sh"; add_read "$TR" "$Q/hooks/b.sh"; add_read "$TR" "$Q/hooks/c.sh"
denied "$(write g "$Q" "$Q/hooks/x.sh" "$TR")" || red "в проекте без ROOTS.md три чтения сняли отказ — по D1033 чтения его не снимают"

exit "$RED"
