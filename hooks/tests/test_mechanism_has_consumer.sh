#!/usr/bin/env bash
# test_mechanism_has_consumer.sh — механизм без потребителя не уезжает в коммит молча.
#
# Результат: новый файл в scripts/ без исполнителя и без строки в реестре замеров назван;
#            подключённый любым из трёх способов — пропущен молча
# Проверка результата: bash hooks/tests/test_mechanism_has_consumer.sh даёт 0
#
# Повод, 10 сентября 2026. Правило «инструмент без результата — не инструмент» жило только
# текстом и не держало: написан scripts/root-map.py с зелёным тестом и коммитом — и не
# подключён ни к чему. Поймал собеседник вопросом «карту то ты построил, а механизм к
# проверке подключил?», а затем прямо: «результат разбора — механизм, не позволяющий
# подобному возникнуть, ты и это правило игноришь».
# Цена текстового уровня измерена: «знание было уместно и не применено» — 38 случаев;
# 28 августа 2026 — минимум девять случаев из девятнадцати, когда знание было в контексте
# В МОМЕНТ ДЕЙСТВИЯ и всё равно не применилось.
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
HOOK="$ROOT/hooks/mechanism-has-consumer.sh"
[ -f "$HOOK" ] || { echo "FAIL: нет $HOOK"; exit 1; }

TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
PASS=0; FAIL=0
ok()  { PASS=$((PASS+1)); }
bad() { FAIL=$((FAIL+1)); echo "FAIL: $1"; }

# Песочница-репозиторий: форма взята из мира — приборы в scripts/, вызовы из hooks/,
# реестр замеров с колонками id/период/команда/что меряет.
mkrepo() {
    rm -rf "$TMP/repo"; mkdir -p "$TMP/repo/scripts" "$TMP/repo/hooks"
    git -C "$TMP/repo" init -q .
    printf 'id\t7\tbash scripts/measured-tool.sh\tчто-то меряет\n' > "$TMP/repo/scripts/measurements.tsv"
}
say() {  # say → текст, который сказал страж (пусто = промолчал)
    jq -cn --arg c "git commit -m x" --arg d "$TMP/repo" \
        '{tool_name:"Bash",tool_input:{command:$c},cwd:$d}' \
      | bash "$HOOK" 2>/dev/null | jq -r '.hookSpecificOutput.additionalContext // ""' 2>/dev/null
}

# --- T1: сирота назван ---
mkrepo
printf '#!/usr/bin/env bash\necho ok\n' > "$TMP/repo/scripts/orphan.sh"
git -C "$TMP/repo" add -A
grep -q 'orphan.sh' <<< "$(say)" && ok || bad "T1: механизм без потребителя не назван"

# --- T2: вызов из хука — потребитель есть, молчим ---
mkrepo
printf '#!/usr/bin/env bash\necho ok\n' > "$TMP/repo/scripts/called.sh"
printf '#!/usr/bin/env bash\nbash scripts/called.sh\n' > "$TMP/repo/hooks/caller.sh"
git -C "$TMP/repo" add -A
grep -q 'called.sh' <<< "$(say)" && bash -c 'exit 1' && bad "T2: подключённый вызовом назван ложно" || ok

# --- T3: строка в реестре замеров — законный потребитель ---
mkrepo
printf '#!/usr/bin/env bash\necho ok\n' > "$TMP/repo/scripts/measured-tool.sh"
git -C "$TMP/repo" add -A
[ -z "$(say)" ] && ok || bad "T3: прибор из реестра замеров назван ложно"

# --- T4: УПОМИНАНИЕ В КОММЕНТАРИИ потребителем НЕ считается ---
# Первая редакция признака давала 0 из 65 именно на этом: имя прибора стояло в комментариях
# его же проб, и признак счёл их потребителями.
mkrepo
printf '#!/usr/bin/env bash\necho ok\n' > "$TMP/repo/scripts/commented.sh"
printf '#!/usr/bin/env bash\n# см. bash scripts/commented.sh — просто ссылка\necho hi\n' > "$TMP/repo/hooks/mentions.sh"
git -C "$TMP/repo" add -A
grep -q 'commented.sh' <<< "$(say)" && ok || bad "T4: упоминание в комментарии принято за потребителя"

# --- T5: ПРАВКА существующего механизма поводом не является ---
mkrepo
printf '#!/usr/bin/env bash\necho old\n' > "$TMP/repo/scripts/existing.sh"
git -C "$TMP/repo" add -A && git -C "$TMP/repo" -c user.email=t@t -c user.name=t commit -qm base
printf '#!/usr/bin/env bash\necho new\n' > "$TMP/repo/scripts/existing.sh"
git -C "$TMP/repo" add -A
[ -z "$(say)" ] && ok || bad "T5: правка существующего файла названа как новый механизм"

# --- T6: не коммит — страж молчит ---
mkrepo
printf '#!/usr/bin/env bash\necho ok\n' > "$TMP/repo/scripts/orphan.sh"
git -C "$TMP/repo" add -A
out=$(jq -cn --arg c "git status" --arg d "$TMP/repo" \
      '{tool_name:"Bash",tool_input:{command:$c},cwd:$d}' | bash "$HOOK" 2>/dev/null)
[ -z "$out" ] && ok || bad "T6: сработал не на коммите"

# --- T7: вне git-репозитория молчит, а не падает ---
out=$(jq -cn --arg c "git commit -m x" --arg d "$TMP" \
      '{tool_name:"Bash",tool_input:{command:$c},cwd:$d}' | bash "$HOOK" 2>/dev/null)
[ -z "$out" ] && ok || bad "T7: вне репозитория не промолчал"

# --- T8: страж ЗАРЕГИСТРИРОВАН, иначе он сам себе носитель ---
grep -q 'mechanism-has-consumer.sh' "$ROOT/install.sh" \
    && ok || bad "T8: страж не зарегистрирован в install.sh — механизм без потребителя"

echo "mechanism has consumer: PASS=$PASS FAIL=$FAIL"
exit $(( FAIL != 0 ))
