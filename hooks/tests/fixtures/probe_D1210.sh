#!/usr/bin/env bash
# СУДИТ: hooks/hook-input-lib.sh hooks/output-language-check.sh hooks/relative-date-check.sh hooks/fix-level-check.sh hooks/accepted-alternative-gap.sh hooks/declared-problem-recorded.sh
# probe_D1210 — читатели итога хода на Stop судят итог и тогда, когда файл расшифровки его ещё не догнал: текст итога
# приходит полем входа `last_assistant_message`. У каждого из пяти стражей — итог с его нарушением в пяти формах:
#   file  — итог в файле, поля нет (прежний путь);
#   field — итога в файле нет (последний блок агента — промежуточный, за ним вызов инструмента), итог только в поле;
#   both  — итог и в файле, и в поле (файл догнал);
#   tail  — как both, и за итогом служебная запись харнесса `last-prompt` (она пишется сразу за итогом и границей хода
#           не служит: скептик D1210, H1);
#   none  — итога нет ни в файле, ни в поле — контроль: отклик обязан отличаться от file, иначе нога не различает.
# Отклик — вывод стража и следы в каталоге состояния (имя файла и число строк); метки окна и свёртки расшифровки
# (`transcript-*`) — кэш помощника, не суждение, в сравнение не входят.
# Двойной суд в отклике не виден (стражи гасят повтор находки сами), поэтому сравнение `with_final` проверяется прямо:
# окно, догнавшее итог, не растёт, не догнавшее — растёт на одну запись.
# 0 — у всех пяти field, both и tail отвечают как file и сравнение верно; 1 — иначе (названо); 2 — рамка не собралась.
R="${CLAUDSOUL_REPO:-$(cd "$(dirname "$0")/../../.." && pwd)}"
command -v jq >/dev/null 2>&1 || { echo "рамка: нет jq" >&2; exit 2; }
W=$(mktemp -d "${TMPDIR:-/tmp}/probe-D1210.XXXXXX") || exit 2
trap 'rm -rf "$W"' EXIT

# obs <страж> <форма> <итог> → отпечаток отклика. Путь расшифровки у всех форм одного стража общий: ключ меток окна
# выводится из пути, а каталог состояния у каждой формы свой.
obs() {
    local d="$W/$1/$2" t="$W/$1/t.jsonl" lam="" out
    mkdir -p "$d"
    { jq -nc '{type:"user",message:{role:"user",content:"почему упало?"},timestamp:"2026-11-05T08:00:00Z"}'
      jq -nc '{type:"assistant",message:{role:"assistant",content:[{type:"text",text:"Смотрю журнал сборки."}]}}'
      jq -nc '{type:"assistant",message:{role:"assistant",content:[{type:"tool_use",id:"t1",name:"Bash",input:{command:"make"}}]}}'
      jq -nc '{type:"user",message:{role:"user",content:[{type:"tool_result",tool_use_id:"t1",content:"ok"}]}}'
      case "$2" in file|both|tail) jq -nc --arg m "$3" '{type:"assistant",message:{role:"assistant",content:[{type:"text",text:$m}]}}' ;; esac
      case "$2" in tail) jq -nc '{type:"last-prompt",lastPrompt:"почему упало?",sessionId:"s1"}' ;; esac
    } > "$t"
    case "$2" in field|both|tail) lam="$3" ;; esac
    out=$(jq -nc --arg t "$t" --arg c "$W" --arg l "$lam" \
            '{session_id:"s1",transcript_path:$t,cwd:$c,hook_event_name:"Stop",stop_hook_active:false}
             + (if $l == "" then {} else {last_assistant_message:$l} end)' \
          | STATE_DIR="$d" CLAUDE_PROJECT_DIR="$W" bash "$R/hooks/$1" 2>/dev/null)
    printf 'вывод %s\n' "$(printf '%s' "$out" | cksum | cut -d' ' -f1)"
    (cd "$d" && find . -type f ! -name 'transcript-*' ! -name '.transcript-*' | sort | while IFS= read -r f; do
        printf '%s %s\n' "$f" "$(grep -c '' "$f")"; done)
}

bad=""
for c in \
    "output-language-check.sh|Делаем fix'ом несколько лookup'ов подряд, ещё fix'ом." \
    "relative-date-check.sh|Сборка сломалась вчера, теперь собирается." \
    "fix-level-check.sh|Ошибка моя: пропустил проверку. Надо вынести урок и не повторять." \
    "accepted-alternative-gap.sh|Отличная идея, твой вариант лучше моего — вшиваю." \
    "declared-problem-recorded.sh|$(printf 'Итог.\n\n**Что найдено**\n- черновики ждут разбора\n')"; do
    h="${c%%|*}"; fin="${c#*|}"
    [ -f "$R/hooks/$h" ] || { echo "рамка: нет hooks/$h" >&2; exit 2; }
    a=$(obs "$h" file "$fin"); n=$(obs "$h" none "$fin")
    [ "$a" != "$n" ] || { echo "рамка: $h молчит и на итоге в файле — нарушение фикстуры не судится" >&2; exit 2; }
    f=$(obs "$h" field "$fin"); b=$(obs "$h" both "$fin"); t=$(obs "$h" tail "$fin")
    [ "$f" = "$a" ] || bad="$bad $h:поле"
    [ "$b" = "$a" ] || bad="$bad $h:файл+поле"
    [ "$t" = "$a" ] || bad="$bad $h:файл+last-prompt"
done

wf=$(bash -c '. "$1" >/dev/null 2>&1; printf %s "${HIL_WITH_FINAL_JQ:-}"' _ "$R/hooks/hook-input-lib.sh")
if [ -z "$wf" ]; then bad="$bad with_final:нет"
else
    # Краевой перевод строки у текста в файле, поле обрезано харнессом; промежуточный текст стоит раньше итога.
    win=$(jq -nc '[{type:"user",message:{role:"user",content:"почему упало?"}},
                   {type:"assistant",message:{role:"assistant",content:[{type:"text",text:"Смотрю журнал сборки."}]}},
                   {type:"assistant",message:{role:"assistant",content:[{type:"text",text:"Итог.\n"}]}}]')
    [ "$(printf '%s' "$win" | jq --arg l 'Итог.' "$wf"'with_final($l) | length' 2>/dev/null)" = 3 ] || bad="$bad with_final:догнавший файл"
    [ "$(printf '%s' "$win" | jq --arg l 'Другой итог.' "$wf"'with_final($l) | length' 2>/dev/null)" = 4 ] || bad="$bad with_final:файл не догнал"
fi
[ -z "$bad" ] || { echo "итог, не догнавший файл, судится не так, как итог в файле:$bad"; exit 1; }
echo "пять читателей итога судят итог из поля входа так же, как из файла"
exit 0
