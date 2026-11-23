#!/usr/bin/env bash
set -u
# СУДИТ: hooks/backfill-compliance.sh hooks/lib/backfill-compliance-one.py
# probe_D1246 — отказ воркера реплея соответствия виден в итоге: нечитаемая расшифровка (воркер падает на чтении) даёт
#   реплею `hooks/backfill-compliance.sh` ненулевой код, а воркер `hooks/lib/backfill-compliance-one.py` на аргументе,
#   который не файл, отвечает не 0. Контроль — исправный каталог: код 0 и наблюдений больше нуля (как у probe_D1208).
#   До D1246 реплей глушил stderr воркера и не читал код трубы: нечитаемая расшифровка давала 0 и «наблюдений: N» без её
#   вклада, а воркер на не-файле выходил с 0.
# Код: 0 — отказ виден; 1 — нет (названо); 2 — нет реплея, jq, python3 либо контроль пуст.
R="${CLAUDSOUL_REPO:-$(cd "$(dirname "$0")/../../.." && pwd)}"
BC="$R/hooks/backfill-compliance.sh"; WK="$R/hooks/lib/backfill-compliance-one.py"
[ -f "$BC" ] && [ -f "$WK" ] && command -v jq >/dev/null 2>&1 && command -v python3 >/dev/null 2>&1 || exit 2
W=$(mktemp -d) || exit 2
trap 'chmod -R u+rw "$W" 2>/dev/null; rm -rf "$W"' EXIT
# Блокер, правка, чтение, правка — наблюдение класса A (как у ноги T15 `hooks/tests/test_backfill_compliance.sh`).
{
    jq -cn '{type:"attachment",timestamp:"2026-07-01T00:00:00Z",attachment:{type:"hook_additional_context",hookName:"PreToolUse:Edit",toolUseID:"t1",content:["🛑 Blocker: long_lived_markdown_doc_edit"]}}'
    jq -cn '{type:"assistant",timestamp:"2026-07-01T00:00:00Z",message:{role:"assistant",content:[{type:"tool_use",name:"Edit",id:"t1",input:{file_path:"/p/PLAN.md"}}]}}'
    jq -cn '{type:"assistant",timestamp:"2026-07-01T00:00:00Z",message:{role:"assistant",content:[{type:"tool_use",name:"Read",id:"r",input:{file_path:"/p/PLAN.md"}}]}}'
    jq -cn '{type:"assistant",timestamp:"2026-07-01T00:00:00Z",message:{role:"assistant",content:[{type:"tool_use",name:"Edit",id:"t2",input:{file_path:"/p/PLAN.md"}}]}}'
} > "$W/c.jsonl"
mkdir -p "$W/ok/-P" "$W/bad/-P" || exit 2
cp "$W/c.jsonl" "$W/ok/-P/a.jsonl"; cp "$W/c.jsonl" "$W/bad/-P/a.jsonl"; cp "$W/c.jsonl" "$W/bad/-P/b.jsonl"
chmod 000 "$W/bad/-P/b.jsonl"
[ -r "$W/bad/-P/b.jsonl" ] && { echo "рамка: chmod 000 не отнял чтение (запуск от root?)" >&2; exit 2; }
BACKFILL_PROJECTS_DIR="$W/ok" COMPLIANCE_OUT="$W/ok.jsonl" bash "$BC" >/dev/null 2>&1; ok_rc=$?
ok_n=$(grep -c . "$W/ok.jsonl" 2>/dev/null)
[ "$ok_rc" = 0 ] && [ "${ok_n:-0}" -gt 0 ] || { echo "рамка: исправный каталог — код $ok_rc, наблюдений ${ok_n:-0}" >&2; exit 2; }
# Пустой каталог — не отказ: без этой ноги починка «любой ненулевой код трубы — сбой» (пустой список даёт `grep` 1)
# проходила и пробу, и набор (скептик opus по 03474690, L1).
mkdir -p "$W/empty/-P"
BACKFILL_PROJECTS_DIR="$W/empty" COMPLIANCE_OUT="$W/empty.jsonl" bash "$BC" >/dev/null 2>&1; em_rc=$?
[ "$em_rc" = 0 ] || { echo "рамка: пустой каталог — код $em_rc (реплей зовёт отказом отсутствие данных)" >&2; exit 2; }
BACKFILL_PROJECTS_DIR="$W/bad" COMPLIANCE_OUT="$W/bad.jsonl" bash "$BC" >/dev/null 2>"$W/bad.err"; bad_rc=$?
python3 "$WK" "$W/нет-такого.jsonl" >/dev/null 2>&1; wk_rc=$?
miss=""
[ "$bad_rc" != 0 ] || miss="$miss реплей на нечитаемой расшифровке ответил 0;"
[ "$bad_rc" = 0 ] || [ -s "$W/bad.err" ] || miss="$miss реплей отказал без строки причины;"
[ "$wk_rc" != 0 ] || miss="$miss воркер на не-файле ответил 0;"
[ -z "$miss" ] && { echo "отказ воркера виден: реплей $bad_rc, воркер на не-файле $wk_rc"; exit 0; }
echo "отказ воркера не виден:$miss"
exit 1
