#!/usr/bin/env bash
set -u
# СУДИТ: hooks/backfill-intrusiveness.sh hooks/backfill-compliance.sh
# probe_D1208 — массовые реплеи проходят путь расшифровки с пробелом и апострофом: `xargs` без NUL делил строку списка по
#   пробелу и разбирал кавычки, воркер получал обрывки пути (D1208). Те же расшифровки лежат в каталоге без пробела
#   (контроль: событий и наблюдений больше нуля) и в «sp proj/…/it's.jsonl» — выход и число строк обязаны совпасть у
#   обоих оркестраторов: `hooks/backfill-intrusiveness.sh` и брата того же корня `hooks/backfill-compliance.sh`.
#   Плюс проба D1150 под `TMPDIR` с пробелом (её рамка зовёт массовый реплей) — 0.
# Код: 0 — пути с пробелом и апострофом проходят; 1 — нет (названо); 2 — нет оркестраторов/jq/python3 либо контроль пуст.
R="${CLAUDSOUL_REPO:-$(cd "$(dirname "$0")/../../.." && pwd)}"
BI="$R/hooks/backfill-intrusiveness.sh"; BC="$R/hooks/backfill-compliance.sh"
[ -f "$BI" ] && [ -f "$BC" ] && command -v jq >/dev/null 2>&1 && command -v python3 >/dev/null 2>&1 || exit 2
W=$(mktemp -d) || exit 2
trap 'rm -rf "$W"' EXIT
# Реплей интрузивности: предложение и согласие → событие `gentle` (как у ноги T2 `hooks/tests/test_backfill.sh`).
{
    jq -cn '{type:"user", timestamp:"2026-04-01T10:00:00Z", message:{role:"user", content:[{type:"text", text:"напиши функцию"}]}}'
    jq -cn '{type:"assistant", timestamp:"2026-04-01T10:00:05Z", message:{role:"assistant", content:[{type:"text", text:"Вот набросок функции. Всё готово, запускаем?"}]}}'
    jq -cn '{type:"user", timestamp:"2026-04-01T10:00:30Z", message:{role:"user", content:[{type:"text", text:"да"}]}}'
} > "$W/i.jsonl"
# Реплей соответствия: блокер, правка, чтение, правка (как у ноги T15 `hooks/tests/test_backfill_compliance.sh`).
{
    jq -cn '{type:"attachment",timestamp:"2026-07-01T00:00:00Z",attachment:{type:"hook_additional_context",hookName:"PreToolUse:Edit",toolUseID:"t1",content:["🛑 Blocker: long_lived_markdown_doc_edit"]}}'
    jq -cn '{type:"assistant",timestamp:"2026-07-01T00:00:00Z",message:{role:"assistant",content:[{type:"tool_use",name:"Edit",id:"t1",input:{file_path:"/p/PLAN.md"}}]}}'
    jq -cn '{type:"assistant",timestamp:"2026-07-01T00:00:00Z",message:{role:"assistant",content:[{type:"tool_use",name:"Read",id:"r",input:{file_path:"/p/PLAN.md"}}]}}'
    jq -cn '{type:"assistant",timestamp:"2026-07-01T00:00:00Z",message:{role:"assistant",content:[{type:"tool_use",name:"Edit",id:"t2",input:{file_path:"/p/PLAN.md"}}]}}'
} > "$W/c.jsonl"
mkdir -p "$W/plain/-P" "$W/sp proj/-P" || exit 2
cp "$W/i.jsonl" "$W/plain/-P/i.jsonl"; cp "$W/c.jsonl" "$W/plain/-P/c.jsonl"
cp "$W/i.jsonl" "$W/sp proj/-P/it's i.jsonl"; cp "$W/c.jsonl" "$W/sp proj/-P/it's c.jsonl"
run() {  # run <каталог> <метка> → «код_интрузивности код_соответствия событий наблюдений»
    env -u STATE_DIR -u ITR_STATE_DIR BACKFILL_PROJECTS_DIR="$W/$1" BACKFILL_OUT="$W/bi-$2.jsonl" bash "$BI" >/dev/null 2>&1
    local a=$?
    BACKFILL_PROJECTS_DIR="$W/$1" COMPLIANCE_OUT="$W/bc-$2.jsonl" bash "$BC" >/dev/null 2>&1
    local b=$?
    printf '%s %s %s %s' "$a" "$b" "$(grep -c . "$W/bi-$2.jsonl" 2>/dev/null)" "$(grep -c . "$W/bc-$2.jsonl" 2>/dev/null)"; }
read -r pa pb pe po <<< "$(run plain p)"
[ "$pa" = 0 ] && [ "$pb" = 0 ] && [ "${pe:-0}" -gt 0 ] && [ "${po:-0}" -gt 0 ] \
    || { echo "рамка: без пробела коды $pa/$pb, событий ${pe:-0}, наблюдений ${po:-0}" >&2; exit 2; }
read -r sa sb se so <<< "$(run "sp proj" s)"
miss=""
[ "$sa" = 0 ] && [ "$se" = "$pe" ] || miss="$miss интрузивность(код $sa, событий ${se:-0} из $pe)"
[ "$sb" = 0 ] && [ "$so" = "$po" ] || miss="$miss соответствие(код $sb, наблюдений ${so:-0} из $po)"
# Голый `mktemp -d` на macOS TMPDIR не читает — подмена из дерева (`hooks/lib/mktemp-shim.sh`, её ставят исполнители
# проверок) повторяет поведение GNU, иначе рамка пробы D1150 легла бы мимо пробела и нога не различала бы.
mkdir -p "$W/t mp/.bin" && cp "$R/hooks/lib/mktemp-shim.sh" "$W/t mp/.bin/mktemp" && chmod +x "$W/t mp/.bin/mktemp" || exit 2
PATH="$W/t mp/.bin:$PATH" TMPDIR="$W/t mp" CLAUDSOUL_REPO="$R" bash "$R/hooks/tests/fixtures/probe_D1150.sh" >/dev/null 2>&1; d=$?
[ "$d" = 0 ] || miss="$miss проба_D1150_под_TMPDIR_с_пробелом(код $d)"
[ -z "$miss" ] && { echo "пути с пробелом и апострофом проходят оба реплея"; exit 0; }
echo "путь с пробелом или апострофом не проходит:$miss"
exit 1
