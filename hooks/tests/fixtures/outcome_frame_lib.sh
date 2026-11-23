#!/usr/bin/env bash
# outcome_frame_lib.sh — общая рамка проб сверки исхода (D1108–D1110): настоящий страж разбора и настоящая
# команда исхода на песочнице. Источается пробой; сама ничего не судит. Токены поводов производит сам страж из входов
# своих детекторов (текст хода, журнал переработки) — проба не пишет журнал стража руками: фикстура, собранная проще
# мира, уже дала зелёный положительный контроль мимо настоящей формы токена (скептик D1107, H2).
R="${CLAUDSOUL_REPO:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)}"
HOOK="$R/hooks/five-whys-gate.sh"; OUTCMD="$R/scripts/outcome.sh"
[ -f "$HOOK" ] && [ -f "$OUTCMD" ] && [ -f "$R/hooks/root-cause-lib.sh" ] || exit 2
command -v jq >/dev/null 2>&1 && command -v git >/dev/null 2>&1 || exit 2
SB=$(mktemp -d "${TMPDIR:-/tmp}/probe-outcome.XXXXXX") || exit 2
SB=$(cd "$SB" && pwd -P)
# Уборка — у рамки, а не у каждой пробы: из 19 потребителей не убирал ни один, и прямой прогон оставлял каталог в
# системном TMPDIR (2437 к 2 ноября 2026; скептик opus по d271f058, L2). Потребитель со своей ловушкой EXIT её перекроет.
trap 'rm -rf "$SB"' EXIT
ST="$SB/state"; mkdir -p "$ST" || exit 2
export CLAUDSOUL_REPO="$R"
mk_tr() {   # <файл> <текст ответа> — ход: реплика собеседника и ответ агента
    : > "$1"
    printf '{"type":"user","message":{"role":"user","content":[{"type":"text","text":"чини"}]}}\n' >> "$1"
    jq -cn --arg t "$2" '{type:"assistant",message:{role:"assistant",content:[{type:"text",text:$t}]}}' >> "$1"
}
next_turn() {   # <файл> <реплика> <ответ> — новый ход в той же расшифровке
    jq -cn --arg t "$2" '{type:"user",message:{role:"user",content:[{type:"text",text:$t}]}}' >> "$1"
    jq -cn --arg t "$3" '{type:"assistant",message:{role:"assistant",content:[{type:"text",text:$t}]}}' >> "$1"
}
cw() {   # <sid> <file_path> <транскрипт> <каталог сессии> — вызов стража на запись
    jq -cn --arg s "$1" --arg f "$2" --arg p "$3" --arg d "$4" \
      '{session_id:$s, transcript_path:$p, hook_event_name:"PreToolUse", tool_name:"Write", cwd:$d, tool_input:{file_path:$f, content:"x"}}' \
      | STATE_DIR="$ST" bash "$HOOK" 2>/dev/null
}
cr() {   # <sid> <транскрипт> <каталог> — читающий вызов оболочки (страж видит повод, записи нет)
    jq -cn --arg s "$1" --arg p "$2" --arg d "$3" \
      '{session_id:$s, transcript_path:$p, hook_event_name:"PreToolUse", tool_name:"Bash", cwd:$d, tool_input:{command:"cat BACKLOG.md"}}' \
      | STATE_DIR="$ST" bash "$HOOK" >/dev/null 2>&1
}
dec() { jq -r '.hookSpecificOutput.permissionDecision // "allow"' <<< "${1:-{\}}" 2>/dev/null || echo allow; }
no() {   # <sid> <исход> <вид> <чем> <каталог вызова> — команда исхода; код как у неё
    ( cd "$5" && DIS_SESSION="$1" STATE_DIR="$ST" bash "$OUTCMD" "$2" "$3" "$4" >/dev/null 2>&1 )
}
gproj() {   # <каталог> — проект под git с hooks/x.sh, hooks/y.sh и пустым бэклогом в коммите
    mkdir -p "$1/hooks" && seq 1 20 > "$1/hooks/x.sh" && seq 1 20 > "$1/hooks/y.sh" \
      && ( cd "$1" && git init -q . && printf '%s\n' '# BACKLOG' '' > BACKLOG.md && git add -A \
           && git -c user.email=t@t -c user.name=t commit -qm i )
}
item() {   # <бэклог> <ID> <адрес> — открытый пункт с корнем из карты и адресом проявления
    printf '%s\n' "- ☐ **$2** находка" "  **Повод.** \`$3\` ломается." '  **Корень.** R6 — два состояния.' >> "$1"
}
rewrite() {   # <файл> <awk-программа> — правка без `sed -i` (у GNU и BSD разный синтаксис)
    awk "$2" "$1" > "$1.tmp.$$" && mv "$1.tmp.$$" "$1"
}
FINDING="Побочно вылезла дыра в границе слова, чиню заодно."
