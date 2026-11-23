#!/usr/bin/env bash
# adversary-recall.sh — снимки для замера полноты критика /adversary на старых поломках.
#
# Результат: на каждый случай корпуса (`scripts/adversary-recall-corpus.tsv`) — каталог с кодом на
#            момент ДО починки (у контроля — на коммите состояния), без истории git и без файлов,
#            где назван номер пункта; и текст задания критику — тот же, что даёт /adversary.
# Проверка результата: bash scripts/adversary-recall.sh --self-test даёт 0
#
# Зачем (18 ноября 2026, приём из статьи команды Claude Code «How the Claude Code team thinks
# about verification»). Критик /adversary находит дефекты, но какую ДОЛЮ настоящих — не мерил
# никто: `scripts/adversary-replay.sh` мерит другое — уходят ли коммиты без прогона вовсе.
# Поломки с известным ответом лежат в истории: пункт долга описал дефект, коммит его починил.
# Критик получает код до починки, ответа не знает; засчитывается только находка, описывающая
# именно эту поломку. Контроль — файлы без единой починки: на них мерятся ложные тревоги.
#
# ПОДСКАЗКИ ВЫЧИЩАЮТСЯ. До починки пункт уже записан: BACKLOG.md, проба probe_D<N>.sh, SESSION.md
# и журнал активности описывают дефект словами. Снимок — `git archive` без истории (сообщения
# коммитов «D<N> в работе — разбор» тоже подсказка), из него убраны журналы долга и сессий и
# каждый файл, кроме предмета, где номер пункта стоит словом.
#
# НАЗВАННЫЕ ПРЕДЕЛЫ.
#  1. База знаний `~/.claude/global-lessons` вне снимка: кейс о поломке там может лежать. Критик
#     идёт агентом `lean` без CLAUDE.md и правил, дороги туда ему не дано; запрет — в границах.
#  2. Сборка задания повторяет `criticPrompt` из `skills/adversary/references/adversary-rounds.js`
#     (три строки склейки); тексты CRITIC и TECHNIQUES берутся из файла, не копией.
#     ponytail: склейка — копия; разойдётся с js — замер мерит не тот промпт; вынести, когда js сменит склейку.
#  3. Правила, выведенные из пропусков этого корпуса, мерить на ЭТОМ же корпусе нельзя —
#     критик подгонится под экзамен; для них нужен новый набор случаев.
set -uo pipefail

REPO="$(cd "$(dirname "$0")/.." && pwd)"
CORPUS="${ADVERSARY_RECALL_CORPUS:-$REPO/scripts/adversary-recall-corpus.tsv}"   # корпус 2 — adversary-recall-corpus-2.tsv
JS="$REPO/skills/adversary/references/adversary-rounds.js"

rows() { grep -vE '^(#|$)' "$CORPUS"; }

# snapshot <id> <род> <коммит> <файл> <каталог>
snapshot() {
  local id="$1" kind="$2" sha="$3" file="$4" dir="$5" state f
  state="$sha"; [ "$kind" = bug ] && state="$sha^"
  mkdir -p "$dir" || return 1
  git -C "$REPO" archive "$state" | tar -x -C "$dir" || return 1
  for f in BACKLOG.md BACKLOG-archive.md SESSION.md CHANGELOG.md внутренний архив (не публикуется); do
    [ -e "$dir/$f" ] && rm -f "$dir/$f"
  done
  if [ "$kind" = bug ]; then
    while IFS= read -r f; do
      [ "$f" = "$dir/$file" ] || rm -f "$f"
    done < <(grep -rlw -- "$id" "$dir")
  fi
  git -C "$dir" init -q && git -C "$dir" add -A \
    && git -C "$dir" -c user.name=snapshot -c user.email=snapshot@localhost commit -qm snapshot
}

# prompt <id> <каталог снимка>
prompt() {
  local id="$1" dir="$2" file
  file="$(rows | awk -F'\t' -v id="$id" '$1 == id { print $4 }')"
  [ -n "$file" ] || { echo "нет случая $id в корпусе" >&2; return 2; }
  node -e '
    const fs = require("fs"); const [js, dir, file] = process.argv.slice(1)
    const src = fs.readFileSync(js, "utf8")
    const pick = n => eval(src.match(new RegExp("const " + n + " = (\\[[\\s\\S]*?\\])\\.join"))[1]).join("\n")
    const fill = (s, a, b) => s.split(a).join(b)
    const bounds = `Работай только внутри каталога ${dir}: это копия проекта, предмет лежит в ней. Другие каталоги не открывай и не меняй, базу знаний ~/.claude/global-lessons не читай.`
    const subject = `${file} (файл в каталоге ${dir})`
    const test = `${dir}/hooks/tests/test_adv_r1_<имя>.sh`
    process.stdout.write(bounds + "\n\n"
      + fill(fill(fill(pick("CRITIC"), "<ПРЕДМЕТ>", subject), "<ПУТЬ ДЛЯ ТЕСТОВ>", test), "<КОМАНДА ЗАПУСКА>", "bash <файл теста>")
      + `\n\nПриёмы атаки (чем бить; это ПРИЁМЫ, а не классы дефектов):\n${pick("TECHNIQUES")}`
      + "\n\nУже ЗАКРЫТЫЕ классы — новый вход в них помечай «ВХОД ЗАКРЫТОГО КЛАССА: <класс>», а не новой находкой: нет\n")
  ' "$JS" "$dir" "$file"
}

case "${1:-}" in
  prepare)
    out="${2:?каталог для снимков}"
    rows | while IFS=$'\t' read -r id kind sha file key; do
      snapshot "$id" "$kind" "$sha" "$file" "$out/$id" && echo "$id	$out/$id" || { echo "снимок $id не собран" >&2; exit 1; }
    done ;;
  prompt) prompt "${2:?id}" "${3:?каталог снимка}" ;;
  --self-test)
    FAIL=0; T="$(mktemp -d)"
    IFS=$'\t' read -r id kind sha file key < <(rows | head -1)
    snapshot "$id" "$kind" "$sha" "$file" "$T/s" || { echo "FAIL: снимок не собран"; exit 1; }
    cmp -s "$T/s/$file" <(git -C "$REPO" show "$sha^:$file") && echo "PASS: предмет — код до починки" \
      || { echo "FAIL: предмет не равен $sha^:$file"; FAIL=1; }
    left="$(grep -rlw -- "$id" "$T/s" | grep -v "^$T/s/$file$")"
    [ -z "$left" ] && echo "PASS: номер $id вычищен" || { echo "FAIL: номер $id остался: $left"; FAIL=1; }
    [ "$(git -C "$T/s" rev-list --count HEAD)" = 1 ] && echo "PASS: история — один коммит" \
      || { echo "FAIL: история не вычищена"; FAIL=1; }
    P="$(prompt "$id" "$T/s")"
    grep -q 'Ты противник' <<< "$P" && grep -q "$T/s" <<< "$P" && ! grep -qE '<ПРЕДМЕТ>|<КОМАНДА ЗАПУСКА>' <<< "$P" \
      && echo "PASS: задание собрано из adversary-rounds.js" || { echo "FAIL: задание не собрано"; FAIL=1; }
    # Каждый случай обоих корпусов: коммит — ПЕРВАЯ починка пункта, и предмет до неё номер не называет. Иначе снимок
    # «до починки» уже несёт починку (18 ноября 2026: в корпус 2 сперва лёг круг правок скептика 44ebae5b вместо 5d465274).
    for c in "$REPO"/scripts/adversary-recall-corpus*.tsv; do
        while IFS=$'\t' read -r id kind sha file key; do
            [ "$kind" = bug ] || continue
            # Фиксированной строкой и границей номера в awk: `-E --grep` с `\b` под bash этой машины не находит ничего.
            log=$(git -C "$REPO" log --reverse --format='%h %s' -F --grep="$id")
            # Починка пункта — номер первым словом после «fix(…):»; упоминание («заведён D<N>», брат в чужой починке) — нет.
            first=$(awk -v id="$id" '$0 ~ ("^[0-9a-f]+ fix[^:]*: " id "([^0-9a-z]|$)") { print $1; exit }' <<< "$log")
            [ -n "$first" ] && [ "$(git -C "$REPO" rev-parse -q --verify "$first^{commit}")" = "$(git -C "$REPO" rev-parse -q --verify "$sha^{commit}")" ] \
                || { echo "FAIL: $(basename "$c") $id — коммит $sha, первая починка ${first:-не найдена}"; FAIL=1; }
            # here-string, а не труба в grep -q: под pipefail совпадение давало бы 141 и читалось как «нет».
            grep -qw -- "$id" <<< "$(git -C "$REPO" show "$sha^:$file" 2>/dev/null)" \
                && { echo "FAIL: $(basename "$c") $id — предмет до починки уже называет пункт"; FAIL=1; }
        done < <(grep -vE '^(#|$)' "$c")
    done
    [ "$FAIL" = 0 ] && echo "PASS: случаи корпусов — первые починки, предмет без номера"
    exit $(( FAIL != 0 )) ;;
  *) echo "использование: $0 prepare <каталог> | prompt <id> <каталог снимка> | --self-test" >&2; exit 2 ;;
esac
