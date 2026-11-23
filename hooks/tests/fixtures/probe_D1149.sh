#!/usr/bin/env bash
# СУДИТ: hooks/tests/test_reply_readers_behavior.sh hooks/lib/reply-readers.tsv
# probe_D1149 — подмена понятия у строки реестра `hooks/lib/reply-readers.tsv` краснит свидетеля поведения
# `hooks/tests/test_reply_readers_behavior.sh`: понятие строки сверяется с тем, что читатель делает на различающих
# случаях, а не только со словарём (повод — скептик opus по D1145, M1: подмена трёх понятий в копии реестра давала 0).
# Подмены — каждое понятие на другое (граница → речь и речь → граница, как в поводе; узкая ↔ широкая; без сводки →
# широкая; «до-текущей» ↔ «речь»), «не-реплика» у читателя с драйвером. Контроль — те же строки без подмены зелёные:
# иначе краснота подмены ничего не различает.
# Красная (1), пока свидетеля нет, подмена проходит зелёной или реестр расходится с поведением; 2 — рамка не собралась
# (нет реестра, подменяемой строки, mktemp).
R="${CLAUDSOUL_REPO:-$(cd "$(dirname "$0")/../../.." && pwd)}"
REG="$R/hooks/lib/reply-readers.tsv"
W="$R/hooks/tests/test_reply_readers_behavior.sh"
[ -f "$REG" ] || exit 2
[ -f "$W" ] || { echo "свидетеля поведения нет — понятие строки не сверяется с читателем"; exit 1; }
T=$(mktemp -d) || exit 2
trap 'rm -rf "$T"' EXIT
# Подмены — на ДЕШЁВЫХ читателях (все пять понятий и «не-реплика»): «Проверку» пункта исполняет completion-gate на Stop
# в общем бюджете открытых пунктов, и проба по дорогим стражам съедала его хвост (38 непроверенных против 4). Детектор
# подачи (единственный «до-текущей», самый дорогой драйвер) не гоняется: его ветку судьи держит подложенное наблюдение ниже.
SWAPS='hooks/shared-language-lib.sh	граница-узкая
hooks/shared-language-lib.sh	до-текущей
hooks/root-cause-lib.sh	речь
hooks/root-cause-lib.sh	граница-узкая
hooks/root-cause-lib.sh	не-реплика
hooks/root-cause-lib.sh	граница-без-сводки
scripts/stopper-effect.sh	граница-широкая
hooks/timestamp-canary-check.sh	граница-широкая'
paths=$(printf '%s\n' "$SWAPS" | cut -f1 | sort -u | paste -sd, -)
# Наблюдения читателей снимаются один раз (контролем) и судятся под каждым реестром: драйвер детерминирован.
export REPLY_READERS_OBS="$T/obs.tsv"
REPLY_READERS_REG="$REG" bash "$W" --only "$paths" > "$T/ctl.out" 2>&1 || {
    echo "реестр расходится с поведением на строках подмен (контроль):"; grep '^FAIL' "$T/ctl.out"; exit 1; }
bad=0; n=0
while IFS=$'\t' read -r p wrong; do
    n=$((n + 1))
    awk -F'\t' -v OFS='\t' -v p="$p" -v c="$wrong" '$1 == p { $2 = c; hit++ } { print } END { exit hit != 1 }' \
        "$REG" > "$T/reg$n.tsv" || { echo "рамка: строки $p в реестре нет (или она не одна)"; exit 2; }
    if REPLY_READERS_REG="$T/reg$n.tsv" bash "$W" --only "$p" > "$T/swap$n.out" 2>&1; then
        echo "подмена прошла зелёной: $p → ${wrong}"; bad=1
    elif ! grep -qE "^FAIL: $p: (объявлено|объявлен не-репликой)" "$T/swap$n.out"; then
        echo "подмена красна не расхождением понятия: $p → ${wrong}: $(grep '^FAIL' "$T/swap$n.out" | head -1)"; bad=1
    fi
done <<< "$SWAPS"
# Судья целиком, а не точечно (скептики opus, круг 3 M2 и круг 4 M1): для каждого понятия каноническое наблюдение
# обязано пройти, а каждое отличие от него на один разряд — случай, форма, P, «?» — краснеть. Ослабленный судья
# (сверяет не все разряды сигнатуры или не все формы) иначе давал пробе 0, и вместе с ним проходила настоящая подмена.
# Наблюдения подложены памятью, читатели не гоняются: строки — пути с драйвером, по одному случаю на путь за прогон.
set -f
canon='граница-узкая	0 0 0 0 0 0 - - 0 0 0 1 0 0
граница-широкая	0 1 1 1 1 0 - - 0 1 0 1 0 0
граница-без-сводки	0 0 1 0 1 0 - - 0 0 0 1 0 0
речь	1 0 0 0 0 1 - - 0 0 0 1 1 0
до-текущей	1 0 0 0 0 1 0 0 0 0 0 1 1 0'
vec() { local out="" n; for n in Q S1 S2 S1w S2w Qs P Ps M Sc Qn U0 Q0 Qp; do out="$out $n=$1"; shift; done; printf '%s' "${out# }"; }
cases=""
while IFS=$'\t' read -r c v; do
    cases="$cases$c	$(vec $v)	ok
"
    # Разряд понятия — парой с его второй формой (Q+Qs, S1+S1w, S2+S2w): формы согласованы, судит сигнатура. Одиночный
    # переворот второй формы (S1w, S2w, Qs) судит проверку формы. Одиночный переворот разряда понятия неотличим от
    # переворота формы — его отбила бы проверка формы, и сигнатура осталась бы несудимой (так выжили мутанты J6–J9).
    # Служебные поля и автор (M, Sc, Qn, U0, Qp — D1202) судятся каждый сам, Q0 — вторая форма Q (переворот Q идёт
    # тройкой с Qs и Q0); боковая ветка у границ и реплика без автора у канарейки не судятся — их переворот обязан пройти.
    for pair in '0 5 12' '1 3' '2 4' 3 4 5 8 9 10 11 12 13; do
        a=($v); for k in $pair; do a[$k]=$((1 - a[k])); done
        e=FAIL; case "$c:$pair" in граница-широкая:9|граница-без-сводки:9|граница-без-сводки:11) e=ok ;; esac
        cases="$cases$c	$(vec "${a[@]}")	$e
"
    done
done <<< "$canon"
cases="${cases}речь	$(vec 1 0 0 0 0 1 1 1 0 0 0 1 1 0)	ok
речь	$(vec 1 0 0 0 0 1 0 0 0 0 0 1 1 0)	FAIL
речь	$(vec 1 0 0 0 0 1 1 0 0 0 0 1 1 0)	FAIL
до-текущей	$(vec 1 0 0 0 0 1 1 1 0 0 0 1 1 0)	FAIL
до-текущей	$(vec 1 0 0 0 0 1 - - 0 0 0 1 1 0)	FAIL
до-текущей	$(vec 1 0 0 0 0 1 0 1 0 0 0 1 1 0)	FAIL
"
# «?» — в каждом разряде по отдельности: в двух сразу его отбил бы второй, и ослабленная проверка первого прошла бы.
for k in 0 1 2 3 4 5 6 8 9 10 11 12 13; do
    a=(0 0 0 0 0 0 - - 0 0 0 1 0 0); a[$k]='?'; [ "$k" -eq 6 ] && a[7]='?'
    cases="${cases}граница-узкая	$(vec "${a[@]}")	не измерено
"
done
dpaths=$(awk -F'\t' '!/^#/ && NF >= 2 && $2 != "источник" && $2 != "не-реплика" { print $1 }' "$REG")
nd=$(printf '%s\n' "$dpaths" | grep -c .)
[ "$nd" -ge 10 ] || { echo "рамка: путей с драйвером в реестре $nd"; exit 2; }
nc=$(printf '%s' "$cases" | grep -c .); b=0; done_=0; judged=0
while [ "$done_" -lt "$nc" ]; do
    b=$((b + 1)); : > "$T/jreg$b.tsv"; : > "$T/jobs$b.tsv"; : > "$T/jexp$b.tsv"
    printf '%s' "$cases" | sed -n "$((done_ + 1)),$((done_ + nd))p" | paste - <(printf '%s\n' "$dpaths") | \
        while IFS=$'\t' read -r c v e path; do
            [ -n "$path" ] || continue
            printf '%s\t%s\n' "$path" "$c" >> "$T/jreg$b.tsv"; printf '%s\t%s\n' "$path" "$v" >> "$T/jobs$b.tsv"
            printf '%s\t%s\t%s\t%s\n' "$path" "$e" "$c" "$v" >> "$T/jexp$b.tsv"
        done
    only=$(cut -f1 "$T/jreg$b.tsv" | paste -sd, -)
    REPLY_READERS_OBS="$T/jobs$b.tsv" REPLY_READERS_REG="$T/jreg$b.tsv" bash "$W" --only "$only" > "$T/judge$b.out" 2>&1
    while IFS=$'\t' read -r path e c v; do
        judged=$((judged + 1))
        if [ "$e" = ok ]; then
            grep -qF -- "ok: $path — " "$T/judge$b.out" || { echo "судья отверг законное: «${c}» при $v"; bad=1; }
        else
            grep -qF -- "FAIL: $path:" "$T/judge$b.out" || { echo "судья пропустил почти совпадение: «${c}» при $v"; bad=1; continue; }
            # «?» — драйвер не смог наблюдать, и слово обязано это сказать: «вне словаря» читалось бы поведением читателя.
            [ "$e" = FAIL ] || grep -F -- "FAIL: $path:" "$T/judge$b.out" | grep -qF -- "$e" \
                || { echo "судья назвал «${c}» при $v не «${e}»"; bad=1; }
        fi
    done < "$T/jexp$b.tsv"
    done_=$((done_ + nd))
done
set +f
[ "$judged" -eq "$nc" ] || { echo "рамка: судимо $judged случаев из $nc"; exit 2; }
# Ветки свидетеля помимо судьи: строка без драйвера, путь `--only` без строки, «ни одной судимой строки», драйвер без
# строки — и полный прогон НЕ читает память из окружения (отравленная память дала бы root-cause-lib чужое понятие).
legs=0
judge() {  # judge <имя ноги> <ожидаемая строка FAIL> <реестр> [аргументы свидетеля]
    local leg="$1" want="$2" reg="$3"; shift 3; legs=$((legs + 1))
    if REPLY_READERS_REG="$reg" bash "$W" "$@" > "$T/$leg.out" 2>&1; then
        echo "ветка свидетеля не держит ($leg): свидетель зелёный"; bad=1
    elif ! grep -qF -- "$want" "$T/$leg.out"; then
        echo "ветка свидетеля не держит ($leg): нет «${want}» — $(grep '^FAIL' "$T/$leg.out" | head -1)"; bad=1
    fi
}
{ cat "$REG"; printf 'hooks/paths-lib.sh\tречь\n'; } > "$T/reg-nodrv.tsv"
judge nodrv "драйвера нет" "$T/reg-nodrv.tsv" --only hooks/paths-lib.sh
judge unknown "назван в --only, а строки реестра нет" "$REG" --only hooks/nope.sh
judge nojudged "по --only не судилась ни одна строка" "$REG" --only ,
{ grep '^#' "$REG"; awk -F'\t' '$1 == "hooks/root-cause-lib.sh"' "$REG"; } > "$T/reg-orphan.tsv"
printf 'hooks/root-cause-lib.sh\t%s\n' "$(vec 1 0 0 0 0 1 - - 0 0 0 1 1 0)" > "$T/obs-poison.tsv"
REPLY_READERS_OBS="$T/obs-poison.tsv" judge orphan "драйвер без строки реестра" "$T/reg-orphan.tsv"
grep -qF "FAIL: hooks/root-cause-lib.sh:" "$T/orphan.out" && { echo "полный прогон прочёл память из окружения"; bad=1; }
[ "$bad" -eq 0 ] || exit 1
echo "подмена понятия у строки реестра краснит свидетеля поведения ($n из $n); судья: $judged случаев; ветки свидетеля: $legs из $legs"
exit 0
