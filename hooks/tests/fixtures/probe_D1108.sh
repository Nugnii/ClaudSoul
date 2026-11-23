#!/usr/bin/env bash
# СУДИТ: hooks/root-cause-lib.sh hooks/five-whys-gate.sh scripts/outcome.sh
# probe_D1108 — свежесть записи разбора судится состоянием записи на момент первого взгляда стража на повод, а не
# временем изменения файла. Красная (1), пока: (а) старый незакоммиченный пункт делает «свежим» правка ДРУГОГО пункта;
# (б) вне git старый пункт делает «свежим» правка заголовка файла; (в) старое знание делает «свежим» правка его
# счётчика. Положительный контроль: пункт, дописанный после первого взгляда, и знание, созданное после него, принимаются,
# и страж снимает отказ. Рамка не собралась — 2.
. "$(dirname "$0")/outcome_frame_lib.sh" || exit 2
TR="$SB/tr.jsonl"; mk_tr "$TR" "$FINDING"
L="$SB/lessons"; mkdir -p "$L" || exit 2; export LESSONS_DIR="$L"
printf -- '---\nconfirmed_count: 5\n---\nстарое знание\n' > "$L/pattern-old-thing.md"; touch -t 202601010000 "$L/pattern-old-thing.md"
# (а) git: пункт дописан ДО повода и не закоммичен
P="$SB/git"; gproj "$P" || exit 2
item "$P/BACKLOG.md" D9950 "hooks/x.sh:3"; touch -t 202601010000 "$P/BACKLOG.md"
[ "$(dec "$(cw s1 "$P/hooks/x.sh" "$TR" "$P")")" = deny ] || exit 2
item "$P/BACKLOG.md" D9951 "hooks/y.sh:2"
no s1 debt discovery D9950 "$P" && { echo "(а) старый незакоммиченный пункт стал свежим от правки другого пункта" >&2; exit 1; }
# (б) без git: закрытый пункт десять месяцев назад
Q="$SB/nogit"; mkdir -p "$Q/hooks" && seq 1 20 > "$Q/hooks/x.sh" || exit 2
printf '%s\n' '# BACKLOG' '' '- ☑ **D9960** старое' '  **Повод.** `hooks/x.sh:3` ломался.' '  **Корень.** R6 — два.' > "$Q/BACKLOG.md"
touch -t 202601010000 "$Q/BACKLOG.md"
[ "$(dec "$(cw s2 "$Q/hooks/x.sh" "$TR" "$Q")")" = deny ] || exit 2
rewrite "$Q/BACKLOG.md" 'NR == 1 { print "# BACKLOG проекта"; next } { print }'
no s2 debt discovery D9960 "$Q" && { echo "(б) вне git старый пункт стал свежим от правки заголовка" >&2; exit 1; }
# (в) знание, существовавшее до повода, — правка счётчика
[ "$(dec "$(cw s3 "$P/hooks/x.sh" "$TR" "$P")")" = deny ] || exit 2
rewrite "$L/pattern-old-thing.md" '{ sub(/confirmed_count: 5/, "confirmed_count: 6"); print }'
no s3 knowledge discovery pattern-old-thing "$P" && { echo "(в) старое знание стало свежим от правки счётчика" >&2; exit 1; }
# Положительный контроль
item "$P/BACKLOG.md" D9952 "hooks/x.sh:5"
no s1 debt discovery D9952 "$P" || { echo "свежий пункт по цели отказа не принят" >&2; exit 1; }
[ "$(dec "$(cw s1 "$P/hooks/x.sh" "$TR" "$P")")" = deny ] && { echo "свежий исход не снял отказ" >&2; exit 1; }
printf -- '---\nconfirmed_count: 1\n---\nновое знание\n' > "$L/case-new-thing.md"
no s3 knowledge discovery case-new-thing "$P" || { echo "новое знание не принято" >&2; exit 1; }
echo "свежесть — по записи на момент повода: старые не приняты, новые приняты"
exit 0
