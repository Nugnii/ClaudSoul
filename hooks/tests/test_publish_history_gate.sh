#!/usr/bin/env bash
# test_publish_history_gate.sh — способ публикации выбирается замером истории, а не памятью.
#
# Публикация перестала удалять репозиторий на каждом релизе: с force-push переживают issues,
# pull request'ы и звёзды, то есть канал обратной связи. Безопасность force-push держится
# ровно на одном утверждении — «в публичной истории нет запретного». Утверждение проверяемо,
# и здесь проверяется именно оно.
#
# Почему проверка обязана смотреть ТЕГИ отдельно: незачищенное дерево в этом проекте жило
# под тегом v1.7.5, и такой коммит может не быть достижим ни из одной ветки. `git log --all`
# его не покажет. Проверка, которая смотрит только ветки, на этом самом случае и промолчала бы.

set -uo pipefail

REPO="$(cd "$(dirname "$0")/../.." && pwd)"
PUB="$REPO/scripts/publish-public.sh"
[ -f "$PUB" ] || { echo "SKIP: нет $PUB (не публикуемая подсистема)"; exit 0; }

# Функцию берём из самого скрипта — не копию. Скрипт при source выполняет проверки
# предусловий и выходит, поэтому вырезаем ровно определение функции.
FN=$(mktemp "${TMPDIR:-/tmp}/histfn.XXXXXX")
awk '/^history_forbidden_tokens\(\) \{/,/^\}/' "$PUB" > "$FN"
[ -s "$FN" ] || { echo "FAIL: не удалось вырезать history_forbidden_tokens из $PUB"; exit 1; }
# shellcheck source=/dev/null
. "$FN"

PASS=0
FAIL=0
ok()  { PASS=$((PASS + 1)); }
bad() { FAIL=$((FAIL + 1)); echo "FAIL [$1]: $2"; }

FORB=$(mktemp "${TMPDIR:-/tmp}/forb.XXXXXX")
printf '# комментарий игнорируется\nSecretClientName\n[Bb]adToken\n' > "$FORB"

mkrepo() {
    local d="$1"
    mkdir -p "$d"
    ( cd "$d" && git init -q -b main \
      && git config user.email t@t && git config user.name t \
      && printf 'чисто\n' > a.txt && git add -A && git commit -q -m init )
}

# --- T1: чистая история — пусто ---
T1=$(mktemp -d); mkrepo "$T1/r"
got="$(history_forbidden_tokens "$T1/r" "$FORB")"
[ -z "$got" ] && ok || bad T1 "чистая история признана грязной: [$got]"

# --- T2: запретное в СОДЕРЖИМОМ старого коммита, которого нет в текущем дереве ---
T2=$(mktemp -d); mkrepo "$T2/r"
( cd "$T2/r" && printf 'клиент SecretClientName\n' > leak.txt && git add -A && git commit -q -m leak \
  && git rm -q leak.txt && git commit -q -m "убрал" )
got="$(history_forbidden_tokens "$T2/r" "$FORB")"
case "$got" in
    *SecretClientName*) ok ;;
    *) bad T2 "утечка в истории не найдена — force-push оставил бы её доступной по SHA" ;;
esac

# --- T3: запретное ТОЛЬКО под тегом, вне веток — тот самый случай v1.7.5 ---
T3=$(mktemp -d); mkrepo "$T3/r"
( cd "$T3/r" \
  && printf 'токен BadToken тут\n' > t.txt && git add -A && git commit -q -m tagged \
  && git tag v0.0.1 \
  && git reset -q --hard HEAD~1 )
got="$(history_forbidden_tokens "$T3/r" "$FORB")"
# Функция возвращает СРАБОТАВШИЙ ШАБЛОН, а не найденную строку: искать в её выводе
# литерал «BadToken» — значит проверять не то, что она обещает. Первая версия теста
# краснела именно на этом, и функция была ни при чём.
case "$got" in
    *'[Bb]adToken'*) ok ;;
    *) bad T3 "запретное под тегом вне веток пропущено — ровно случай v1.7.5: [$got]" ;;
esac

# --- T4: комментарии в forbidden.txt не считаются шаблонами ---
T4=$(mktemp -d); mkrepo "$T4/r"
( cd "$T4/r" && printf 'комментарий игнорируется\n' > c.txt && git add -A && git commit -q -m c )
got="$(history_forbidden_tokens "$T4/r" "$FORB")"
[ -z "$got" ] && ok || bad T4 "строка-комментарий из forbidden.txt сработала как шаблон: [$got]"

echo ""
echo "publish history gate: $PASS/$((PASS + FAIL)) passed"
[ "$FAIL" -eq 0 ]
