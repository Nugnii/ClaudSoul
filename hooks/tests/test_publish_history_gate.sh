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
# Вырезается ФУНКЦИЯ ВМЕСТЕ С ИМЕНАМИ, которые она читает. Разрешающий перечень
# разрешающий перечень появился 14 сентября 2026 отдельной строкой ВНЕ функции, срез его не
# захватил, и под `set -u` обе ноги истории умирали на первом же чтении: «утечки не найдено» —
# ровно тот зелёно-выглядящий провал, ради которого тест и написан. Каждое имя берётся у
# владельца (самого скрипта), а не переписывается сюда: копия разошлась бы со скриптом молча.
{ awk '/^TOKEN_ALLOW=/' "$PUB"
  awk '/^history_forbidden_tokens\(\) \{/,/^\}/' "$PUB"; } > "$FN"
[ -s "$FN" ] || { echo "FAIL: не удалось вырезать history_forbidden_tokens из $PUB"; exit 1; }
grep -q '^TOKEN_ALLOW=' "$FN" \
    || { echo "FAIL: в срезе нет TOKEN_ALLOW — имя переименовано или ушло в другое место; без него ноги ниже молча зелены"; exit 1; }
# shellcheck source=/dev/null
. "$FN"

PASS=0
FAIL=0
ok()  { PASS=$((PASS + 1)); }
bad() { FAIL=$((FAIL + 1)); echo "FAIL [$1]: $2"; }

FORB=$(mktemp "${TMPDIR:-/tmp}/forb.XXXXXX")
# Шаблон ключа берётся ТОТ ЖЕ, что в бою: ноги T5/T5б о РАЗРЕШЕНИИ, и на фикстурном
# шаблоне они были бы зелены впустую — первая редакция стреляла значением, которого этот
# перечень не знал, и «разрешено» оказалось «не совпало» (фикстура беднее мира).
printf '# комментарий игнорируется\nSecretClientName\n[Bb]adToken\nAKIA[0-9A-Z]{16}\n' > "$FORB"

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

# --- T5: РАЗРЕШЁННОЕ ФИКСТУРНОЕ значение находкой НЕ считается ------------------------------
# Повод — потеря 15 сентября 2026. Гейт дерева знал синтетические фикстуры (TOKEN_ALLOW), гейт
# истории не знал, объявил историю грязной на них — и публикатор ПЕРЕСОЗДАЛ репозиторий, потеряв
# звёзды, issues и PR. Настоящих секретов среди совпадений было ноль. Перечень теперь один.
T5=$(mktemp -d); mkrepo "$T5/r"
( cd "$T5/r" && printf 'ключ AKIA3KJH2LK4J5HG6PQR из фикстуры\n' > f.txt && git add -A && git commit -q -m fixture )
got="$(history_forbidden_tokens "$T5/r" "$FORB")"
[ -z "$got" ] && ok || bad T5 "разрешённая фикстура засчитана находкой: [$got]"

# --- T5б: МУТАНТ к T5 — НАСТОЯЩЕЕ значение той же формы находкой остаётся --------------------
# Без этой ноги T5 зеленела бы на перечне, разрешающем всё подряд.
T5B=$(mktemp -d); mkrepo "$T5B/r"
# Значение собирается при прогоне: литералом в исходнике этот «живой» ключ ронял бы гейт открытого снимка (D1363).
( cd "$T5B/r" && printf 'ключ %s живой\n' "AKIA""Q7ZX4W9TLMNB2VCD" > f.txt && git add -A && git commit -q -m real )
got="$(history_forbidden_tokens "$T5B/r" "$FORB")"
case "$got" in *AKIA*) ok ;; *) bad T5b "настоящее значение пропущено: [$got]" ;; esac

# --- T6: хвост слова перед `sk-` — не ключ; ключ в любом из настоящих окружений — ключ (D1365) ---------------
# Шаблон берётся из боевого `scripts/publish/forbidden.txt`, а не копией: нога о его ГРАНИЦЕ. 23 ноября 2026
# публикация встала на имени знания `…background-task-…`: «ta|sk-…» совпадало с шаблоном ключа, а перечень
# разрешённого гейт истории сверяет с вырезанным совпадением, где контекста слова уже нет.
SKF=$(mktemp "${TMPDIR:-/tmp}/skforb.XXXXXX")
grep -E '^\(.*\)sk-' "$REPO/scripts/publish/forbidden.txt" > "$SKF"
if [ "$(wc -l < "$SKF" | tr -d ' ')" != 1 ]; then
    bad T6 "в forbidden.txt не одна строка шаблона ключа sk- с границей слова — нога не о боевом шаблоне"
else
    T6=$(mktemp -d); mkrepo "$T6/r"
    ( cd "$T6/r" && printf 'см. case-2026-09-10-background-task-invisible-to-owner и pattern-risk-assessment-before-action\n' \
        > w.txt && git add -A && git commit -q -m words )
    got="$(history_forbidden_tokens "$T6/r" "$SKF")"
    [ -z "$got" ] && ok || bad T6 "хвост слова перед sk- засчитан ключом: [$got]"
    # Мутанты: тот же ключ в каждом окружении, где он встречается в мире. Значение собирается при прогоне —
    # литералом в исходнике оно роняло бы гейт открытого снимка (D1363).
    K="sk""-proj9aB3dE7fG1hJ5kL2mN8"
    i=0
    for ctx in "OPENAI_API_KEY=$K" "{\"key\": \"$K\"}" "Authorization: Bearer $K" "$K" \
               'text":"мой ключ:\n'"$K" "https://x.example.com/cb?key%3D$K"; do
        i=$((i + 1)); M=$(mktemp -d); mkrepo "$M/r"
        ( cd "$M/r" && printf '%s\n' "$ctx" > k.txt && git add -A && git commit -q -m key )
        got="$(history_forbidden_tokens "$M/r" "$SKF")"
        case "$got" in *sk-*) ok ;; *) bad "T6m$i" "ключ в окружении №$i не найден — граница ослабила поиск: [$got]" ;; esac
    done
    # Ключ В НАЧАЛЕ строки — ветка `^` шаблона. Строку файла `git log -p` печатает с «+» впереди, и граница
    # нашлась бы и без `^` (скептик opus, 23 ноября 2026: мутант без `^|` зеленел 13/13). Сообщение
    # аннотированного тега `git show` печатает как есть — строка начинается прямо с ключа.
    M=$(mktemp -d); mkrepo "$M/r"
    ( cd "$M/r" && git tag -a v0.0.1 -m "$K" )
    got="$(history_forbidden_tokens "$M/r" "$SKF")"
    case "$got" in *sk-*) ok ;; *) bad T6m7 "ключ в начале строки (сообщение тега) не найден: [$got]" ;; esac
fi

echo "publish history gate: $PASS/$((PASS + FAIL)) passed"
exit $(( FAIL != 0 ))
