#!/usr/bin/env bash
# test_adv_secret_guard_broken_config.sh — АТАКА: сломанный gitleaks молчит как «чисто».
#
# Шапка hooks/secret-guard.sh объявляет ТРИ состояния прибора:
#   gitleaks не установлен → молчать и выйти 0
#   gitleaks сломался      → СКАЗАТЬ и пропустить
#   отработал, чисто       → молчать
# Ветка поломки стоит на `RC -ge 2` (secret-guard.sh:80). Замер: gitleaks 8.30.1 при
# НЕЧИТАЕМОМ конфиге пишет FTL и выходит с кодом 1, а не ≥2. Значит поломка попадает в
# ветку «находок нет», отчёт остаётся пустым (gitleaks его не создаёт), N=0 — и секрет
# уходит в файл при полном молчании стража.
#
# Конфиг живёт в `$HOME/.claude/security/gitleaks.toml` — это файл семьи `security`,
# у которой пара в drift-check заведена только 10 сентября 2026, а `uninstall.sh` её
# не знал вовсе. Машина с установленным хуком и без конфига — не фикстура, а история.
#
# Признак секрета собирается из кусков намеренно: страж проверяет и запись ЭТОГО файла.
set -uo pipefail

HOOK="$(cd "$(dirname "$0")/.." && pwd)/secret-guard.sh"
TMP=$(mktemp -d) || exit 1
PASS=0; FAIL=0

command -v gitleaks >/dev/null 2>&1 || { echo "SKIP: нет gitleaks — атака непроверяема"; exit 0; }
command -v jq       >/dev/null 2>&1 || { echo "SKIP: нет jq"; exit 0; }

_p1='AK'; _p2='IA3KJH'; _p3='2LK4J5HG6PQR'
SECRET="AWS = \"${_p1}${_p2}${_p3}\""

payload() {  # $1 — file_path, $2 — содержимое
    jq -n --arg f "$1" --arg c "$2" \
       '{tool_name:"Write", tool_input:{file_path:$f, content:$c}}'
}

ok()  { PASS=$((PASS+1)); printf '  ok   %s\n' "$1"; }
bad() { FAIL=$((FAIL+1)); printf '  FAIL %s\n     %s\n' "$1" "$2"; }

# --- положительный контроль: с живым конфигом страж отбивает ------------------------
OUT_REAL=$(payload /Users/x/app/config.py "$SECRET" | bash "$HOOK" 2>/dev/null)
DEC=$(printf '%s' "$OUT_REAL" | jq -r '.hookSpecificOutput.permissionDecision // "-"' 2>/dev/null)
if [ "$DEC" = "deny" ]; then
    ok "положительный_контроль: живой конфиг → deny"
else
    bad "положительный_контроль: живой конфиг → deny" \
        "получено decision=$DEC (окружение не годится для атаки, дальше смысла нет)"
    echo "guard-broken-config: $PASS ok, $FAIL FAIL"; exit 1
fi

# --- АТАКА: конфига стража нет (HOME без ~/.claude/security/gitleaks.toml) -----------
# Ожидание по шапке хука: либо deny (секрет всё же пойман), либо СЛОВО о поломке.
# Молчание здесь неотличимо от «чисто» — ровно то, что шапка запрещает.
OUT=$(payload /Users/x/app/config.py "$SECRET" | HOME="$TMP" bash "$HOOK" 2>/dev/null)
if [ -n "$OUT" ]; then
    ok "конфиг_отсутствует: страж не молчит"
else
    bad "конфиг_отсутствует: страж не молчит" \
        "вывод ПУСТ: секрет пропущен, поломка не названа. gitleaks при нечитаемом конфиге отдаёт 1, а ветка поломки ждёт >= 2 (secret-guard.sh:80)"
fi

# --- АТАКА-2: конфиг есть, но синтаксически битый ------------------------------------
mkdir -p "$TMP/.claude/security"
printf 'это не toml [[[\n' > "$TMP/.claude/security/gitleaks.toml"
OUT2=$(payload /Users/x/app/config.py "$SECRET" | HOME="$TMP" bash "$HOOK" 2>/dev/null)
if [ -n "$OUT2" ]; then
    ok "конфиг_битый: страж не молчит"
else
    bad "конфиг_битый: страж не молчит" \
        "вывод ПУСТ при неразбираемом gitleaks.toml — тот же код 1, та же тишина"
fi

echo "guard-broken-config: $PASS ok, $FAIL FAIL"
exit $(( FAIL != 0 ))
