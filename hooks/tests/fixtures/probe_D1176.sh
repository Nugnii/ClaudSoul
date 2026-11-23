#!/usr/bin/env bash
# СУДИТ: lib/env-pin.jq scripts/world-locale-run.sh
# probe_D1176 — хуки терминальной сессии (LANG=ru_RU.UTF-8) разбирают числа и сравнивают метки как под C: env настроек
# Claude Code несёт закрепление `lib/env-pin.jq`. Окружение хука собирает `scripts/world-locale-run.sh` (он же судит,
# живая ли ru_RU, есть ли закрепление в мире и не перекрыто ли оно LC_ALL). Ноги: в этом окружении awk читает «1.5» как
# 1.5 и не равняет «☐» и «◐»; четыре файла набора, красные под голой ru_RU 28 октября 2026, зелёные; положительный
# контроль — под голой ru_RU красен КАЖДЫЙ из четырёх (иначе этот файл закрепление не различает — 2). Файлы идут
# параллельно, окружения одного файла — по очереди, коды — через каталог. Сторону установщика судит поведением `hooks/tests/test_env_pin.sh`, а не эта проба.
# Красная (1), пока хоть одна нога судит иначе; 2 — рамка не собралась.
R="${CLAUDSOUL_REPO:-$(cd "$(dirname "$0")/../../.." && pwd)}"
W="$R/scripts/world-locale-run.sh"
[ -f "$W" ] || { echo "нет scripts/world-locale-run.sh"; exit 1; }
AWK=/usr/bin/awk; [ -x "$AWK" ] || AWK=$(command -v awk) || exit 2
out=$(printf '1.5\n' | bash "$W" "$AWK" '{ printf "%d %d", $1 * 2, ("☐" == "◐") }'); rc=$?
[ "$rc" -eq 2 ] && exit 2
[ "$rc" -eq 0 ] && [ "$out" = "3 0" ] || { echo "в окружении хука awk даёт «${out}» (код ${rc}), ждали «3 0»"; exit 1; }
FILES="test_adv2_kia_reached_exceeds_stored test_costly_tests test_injection_log test_session_collector"
T=$(mktemp -d) || exit 2
trap 'rm -rf "$T"' EXIT
for t in $FILES; do
    [ -f "$R/hooks/tests/$t.sh" ] || { echo "нет $t.sh"; exit 1; }
    # Один тест сам с собой не идёт: окружения — по очереди, тесты между собой — параллельно, как в наборе.
    ( bash "$W" bash "$R/hooks/tests/$t.sh" >/dev/null 2>&1; echo $? > "$T/$t.pin"
      bash "$W" --bare bash "$R/hooks/tests/$t.sh" >/dev/null 2>&1; echo $? > "$T/$t.bare" ) &
done
wait
bad=0; blind=0
for t in $FILES; do
    [ "$(cat "$T/$t.pin" 2>/dev/null)" = 0 ] || { echo "$t красный в окружении хука"; bad=1; }
    [ "$(cat "$T/$t.bare" 2>/dev/null)" != 0 ] || { echo "$t зелёный и под голой ru_RU — закрепление не различает"; blind=1; }
done
[ "$bad" -eq 0 ] && [ "$blind" -eq 1 ] && exit 2
exit "$bad"
