#!/usr/bin/env bash
# СУДИТ: hooks/root-cause-lib.sh scripts/outcome.sh
# probe_D1255 — свежесть пункта судится и по составу архива на момент повода: снимок несёт номера пунктов архива.
#   (а) пункт записан ПОСЛЕ повода, исход принят, затем архиватор унёс его в архив без изменений — следующая запись того
#       же хода не отбивается: исход держится (номера в архиве снимка нет — свежий);
#   (б) пункт лежал в АРХИВЕ на момент повода и возвращён в BACKLOG.md без правки — исход по нему не принимается
#       (номер в архиве снимка — прежний пункт, нужен новый со ссылкой).
# Код: 0 — так; 1 — нет (названо); 2 — рамка не собралась.
. "$(dirname "$0")/outcome_frame_lib.sh" || exit 2
why() {   # <sid> <исход> <вид> <чем> <каталог> — причина отказа команды исхода в stdout; код как у неё
    ( cd "$5" && DIS_SESSION="$1" STATE_DIR="$ST" bash "$OUTCMD" "$2" "$3" "$4" 2>&1 >/dev/null )
}
ci() { ( cd "$1" && git add -A && git -c user.email=t@t -c user.name=t commit -qm "$2" ); }
closed() {   # <файл> <ID> <адрес> — закрытый пункт ☑ с теми же строками, что у `item`
    printf '%s\n' "- ☑ **$2** находка" "  **Повод.** \`$3\` ломается." '  **Корень.** R6 — два состояния.' >> "$1"
}
miss=""
# (а) свежий пункт, унесённый в архив после принятого исхода
P="$SB/a"; gproj "$P" || exit 2
printf '%s\n' '# Архив' '' > "$P/BACKLOG-archive.md"; ci "$P" base || exit 2
TA="$SB/ta.jsonl"; mk_tr "$TA" "$FINDING"
[ "$(dec "$(cw s1 "$P/hooks/x.sh" "$TA" "$P")")" = deny ] || exit 2
closed "$P/BACKLOG.md" D9981 "hooks/x.sh:3"
why s1 debt discovery D9981 "$P" >/dev/null || { echo "рамка: свежий пункт после повода не принят" >&2; exit 2; }
printf '%s\n' '# BACKLOG' '' > "$P/BACKLOG.md"; closed "$P/BACKLOG-archive.md" D9981 "hooks/x.sh:3"
[ "$(dec "$(cw s1 "$P/hooks/x.sh" "$TA" "$P")")" = deny ] && miss="$miss (а) перенос свежего пункта в архив отозвал принятый исход;"
# (б) архивный пункт, возвращённый в BACKLOG.md без правки
P="$SB/b"; gproj "$P" || exit 2
printf '%s\n' '# Архив' '' > "$P/BACKLOG-archive.md"; closed "$P/BACKLOG-archive.md" D9982 "hooks/x.sh:3"; ci "$P" arch || exit 2
TB="$SB/tb.jsonl"; mk_tr "$TB" "$FINDING"
[ "$(dec "$(cw s2 "$P/hooks/x.sh" "$TB" "$P")")" = deny ] || exit 2
printf '%s\n' '# Архив' '' > "$P/BACKLOG-archive.md"; closed "$P/BACKLOG.md" D9982 "hooks/x.sh:3"
why s2 debt discovery D9982 "$P" >/dev/null && miss="$miss (б) архивный пункт, возвращённый в BACKLOG.md без правки, принят свежим;"
# (в) номера архива считаются раз на версию архива (круг скептика, M1): два снимка при том же архиве — один подсчёт;
# (г) нечитаемый архив строки архива снимка не даёт (M2): пустой список номеров — не «архив пуст».
P="$SB/c"; mkdir -p "$P" || exit 2
printf '%s\n' '# Архив' '' > "$P/BACKLOG-archive.md"; closed "$P/BACKLOG-archive.md" D9983 "hooks/x.sh:3"
J="$SB/c.seen"; : > "$J"
R="$R" P="$P" J="$J" bash -c '. "$R/hooks/root-cause-lib.sh"; _rc_need_backlog_lib || exit 2
    eval "_o_$(declare -f backlog_ids)"; backlog_ids() { echo >> "$J.calls"; _o_backlog_ids "$@"; }
    _rc_snap_archive "$J" s1 "$P/BACKLOG.md"; _rc_snap_archive "$J" s2 "$P/BACKLOG.md"
    chmod 000 "$P/BACKLOG-archive.md"; _rc_snap_archive "$J" s3 "$P/BACKLOG.md"; chmod 644 "$P/BACKLOG-archive.md"' || exit 2
[ "$(grep -c '^snaparch|s[12]|' "$J")" = 2 ] || { echo "рамка: снимки архива не легли" >&2; exit 2; }
[ "$(wc -l < "$J.calls" 2>/dev/null | tr -d ' ')" = 1 ] || miss="$miss (в) номера архива посчитаны заново при том же архиве;"
grep -q '^snaparch|s3|' "$J" && miss="$miss (г) нечитаемый архив лёг в снимок пустым;"
[ -z "$miss" ] && { echo "свежесть судится и по архиву снимка: свежий в архиве держится, возвращённый архивный — нет"; exit 0; }
echo "не держится:$miss"
exit 1
