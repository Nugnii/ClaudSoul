#!/usr/bin/env bash
# test_adv_rules_write_flag_bypass.sh — отказ уровня 4 в rules-write-bypass.sh снимается
# ОДНИМ флагом у команды копирования.
#
# Атака. Признак «оператор записи и путь стоят РЯДОМ» (ADJ_RE, rules-write-bypass.sh:117)
# для команд `cp`/`mv`/`install` записан как
#     (cp|mv|install)[[:space:]]+[^[:space:]]+[[:space:]]+<путь>
# то есть «имя команды, РОВНО ОДНО слово, путь». Любая опция занимает это единственное
# слово, и путь оказывается третьим словом — соседство теряется:
#     cp     rules/CLAUDE.md ~/.claude/CLAUDE.md   → ОТКАЗ
#     cp -f  rules/CLAUDE.md ~/.claude/CLAUDE.md   → тот же эффект, отказа нет
#     install -m 644 rules/CLAUDE.md ~/.claude/CLAUDE.md → каноничная форма install, отказа нет
#     tee -i ~/.claude/CLAUDE.md                   → ADJ_RE знает только `-a`
# Признак `IS_WRITE` при этом срабатывает во всех четырёх (:88), то есть страж ЗНАЕТ, что
# команда пишет, и всё равно пропускает её с информационным сообщением.
#
# Последствие ОДНО и то же, что у формы, на которой отказ стоит: маркеры управляемого блока
# в ~/.claude/CLAUDE.md затираются, пара «правила» в drift-check становится BROKEN. Разных
# последствий у формы с флагом и без него нет — значит это не «признак взят выше корня»,
# а дыра в перечне.
#
# НАЗВАННЫЙ ПРЕДЕЛ стража («запись через переменную рядом не стоит», :95) этот случай НЕ
# покрывает: здесь путь стоит литералом в самой команде.
#
# Тест написан, чтобы УПАСТЬ на текущем коде. Ничего не чинит.

set -uo pipefail

REPO="$(cd "$(dirname "$0")/../.." && pwd)"
HOOK="$REPO/hooks/rules-write-bypass.sh"
[ -f "$HOOK" ] || { echo "FAIL: не найден $HOOK"; exit 1; }
command -v jq >/dev/null 2>&1 || { echo "SKIP: jq недоступен"; exit 0; }

PASS=0; FAIL=0
ok()  { PASS=$((PASS+1)); echo "  ok   — $1"; }
bad() { FAIL=$((FAIL+1)); echo "  FAIL — $1"; }

verdict() {   # verdict <команда> → deny | warn | silent
    local out
    out=$(jq -cn --arg c "$1" '{tool_name:"Bash", tool_input:{command:$c}}' \
          | bash "$HOOK" 2>/dev/null)
    if grep -q '"permissionDecision":"deny"' <<< "$out"; then printf 'deny'
    elif [ -n "$out" ]; then printf 'warn'
    else printf 'silent'; fi
}

must_deny() {  # must_deny <команда> <имя>
    local v; v=$(verdict "$1")
    if [ "$v" = "deny" ]; then ok "$2"
    else bad "$2 — ОТКАЗА НЕТ (вердикт: $v); команда: $1"; fi
}

# --- Контроль: форма без опций отбивается, значит фикстура рабочая --------------
must_deny 'cp rules/CLAUDE.md ~/.claude/CLAUDE.md'  'контроль: «cp src ~/.claude/CLAUDE.md» → отказ'
must_deny 'cat new.md > ~/.claude/CLAUDE.md'        'контроль: перенаправление → отказ'

# --- Атака: тот же эффект, один флаг ------------------------------------------
must_deny 'cp -f rules/CLAUDE.md ~/.claude/CLAUDE.md' \
          '«cp -f src ~/.claude/CLAUDE.md» → отказ'
must_deny 'install -m 644 rules/CLAUDE.md ~/.claude/CLAUDE.md' \
          '«install -m 644 src ~/.claude/CLAUDE.md» → отказ'
must_deny 'mv -f /tmp/new.md ~/.claude/CLAUDE.md' \
          '«mv -f src ~/.claude/CLAUDE.md» → отказ'
must_deny 'cat new.md | tee -i ~/.claude/CLAUDE.md' \
          '«tee -i ~/.claude/CLAUDE.md» → отказ'

# --- Свидетельство: страж ЗНАЕТ, что команда пишет ------------------------------
# Если бы он не признавал её записью, до ADJ_RE дело бы не дошло и вердикт был бы silent.
# ОЖИДАНИЕ ПЕРЕВЁРНУТО ПОСЛЕ ПОЧИНКИ (10 сентября 2026). В момент написания теста эта нога
# фиксировала ДЕФЕКТ: страж распознавал запись (не silent), но отказ снимался проверкой
# соседства, и вердикт был `warn`. Починка выразила роль («цель — последний аргумент»)
# вместо позиции, и та же команда даёт `deny`. Нога сохранена как свидетельство обратного:
# запись по-прежнему распознаётся, и теперь доводится до отказа. `silent` здесь означал бы,
# что страж перестал видеть запись вовсе, — это была бы новая поломка.
V=$(verdict 'install -m 644 rules/CLAUDE.md ~/.claude/CLAUDE.md')
if [ "$V" = "deny" ]; then
    ok "свидетельство: запись распознана И доведена до отказа (было warn — обход флагом)"
else
    bad "свидетельство не получено: вердикт [$V], ожидался deny"
fi

echo
echo "PASS=$PASS FAIL=$FAIL"
exit $(( FAIL != 0 ))
