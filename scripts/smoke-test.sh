#!/usr/bin/env bash
# smoke-test.sh — проверка успешной установки ClaudSoul.
# v1.7.5: вызывается из install.sh в конце, либо запускается отдельно для
# валидации существующей установки.
#
# Проверяет:
#   1. Структура каталогов в ~/.claude/ создана
#   2. Глобальные правила установлены, маркеры на месте
#   3. Хуки скопированы и зарегистрированы в settings.json
#   4. Скиллы скопированы в ~/.claude/commands/
#   5. База знаний скопирована
#   6. MCP-сервер: venv создан, зависимости поставлены (если uv доступен)
#   7. Session Registry готов
#
# Exit codes:
#   0 — все проверки прошли
#   1 — критические компоненты отсутствуют
#   2 — все базовое работает, но есть некритичные пропуски (warnings only)

set -uo pipefail

CLAUDE_HOME="${CLAUDE_HOME:-$HOME/.claude}"
CLAUDSOUL_DIR="${CLAUDSOUL_DIR:-$(cat "$CLAUDE_HOME/claudsoul-repo" 2>/dev/null)}"

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

PASS=0
WARN=0
FAIL=0

check_pass() { echo -e "  ${GREEN}✓${NC} $1"; PASS=$((PASS + 1)); }
check_warn() { echo -e "  ${YELLOW}⚠${NC} $1"; WARN=$((WARN + 1)); }
check_fail() { echo -e "  ${RED}✗${NC} $1"; FAIL=$((FAIL + 1)); }

echo ""
echo -e "${GREEN}━━ ClaudSoul smoke test ━━${NC}"

# 1. Структура каталогов
echo ""
echo "1. Структура каталогов:"
[ -d "$CLAUDE_HOME" ] && check_pass "~/.claude/ существует" || check_fail "~/.claude/ отсутствует"
[ -d "$CLAUDE_HOME/hooks" ] && check_pass "~/.claude/hooks/ существует" || check_fail "~/.claude/hooks/ отсутствует"
[ -d "$CLAUDE_HOME/commands" ] && check_pass "~/.claude/commands/ существует" || check_fail "~/.claude/commands/ отсутствует"
[ -d "$CLAUDE_HOME/global-lessons" ] && check_pass "~/.claude/global-lessons/ существует" || check_fail "~/.claude/global-lessons/ отсутствует"

# 2. Глобальные правила
echo ""
echo "2. Глобальные правила:"
GLOBAL_CLAUDE_MD="$CLAUDE_HOME/CLAUDE.md"
if [ -f "$GLOBAL_CLAUDE_MD" ]; then
    check_pass "CLAUDE.md установлен"
    if grep -qF "ClaudSoul: managed-start" "$GLOBAL_CLAUDE_MD"; then
        check_pass "маркеры managed-start/end на месте"
    else
        check_warn "маркеры отсутствуют — повторная установка не сможет sync (см. v1.7.4)"
    fi
else
    check_fail "CLAUDE.md отсутствует"
fi

# 3. Хуки
echo ""
echo "3. Хуки:"
HOOK_COUNT=$(find "$CLAUDE_HOME/hooks" -maxdepth 1 -name "*.sh" 2>/dev/null | wc -l | tr -d ' ')
if [ "$HOOK_COUNT" -ge 15 ]; then
    check_pass "хуков установлено: $HOOK_COUNT"
else
    check_warn "хуков всего $HOOK_COUNT (ожидалось ≥15)"
fi

SETTINGS="$CLAUDE_HOME/settings.json"
if [ -f "$SETTINGS" ] && command -v jq >/dev/null 2>&1; then
    REGISTERED_COUNT=$(jq -r '[.hooks // {} | to_entries[] | .value[]?.hooks[]?.command] | length' "$SETTINGS" 2>/dev/null || echo 0)
    if [ "$REGISTERED_COUNT" -ge 15 ]; then
        check_pass "хуков зарегистрировано в settings.json: $REGISTERED_COUNT"
    else
        check_warn "хуков в settings.json: $REGISTERED_COUNT (ожидалось ≥15)"
    fi
else
    check_warn "settings.json отсутствует или jq не доступен"
fi

# 4. Скиллы
echo ""
echo "4. Скиллы:"
SKILL_COUNT=$(find "$CLAUDE_HOME/commands" -maxdepth 2 -name "SKILL.md" 2>/dev/null | wc -l | tr -d ' ')
if [ "$SKILL_COUNT" -ge 10 ]; then
    check_pass "скиллов установлено: $SKILL_COUNT"
else
    check_warn "скиллов всего $SKILL_COUNT (ожидалось ≥10)"
fi

# 5. База знаний
echo ""
echo "5. База знаний:"
KNOWLEDGE_COUNT=$(find "$CLAUDE_HOME/global-lessons" -maxdepth 1 -name "*.md" 2>/dev/null | wc -l | tr -d ' ')
if [ "$KNOWLEDGE_COUNT" -gt 0 ]; then
    check_pass "файлов знаний: $KNOWLEDGE_COUNT"
else
    check_warn "база знаний пуста — нормально для свежей установки, наполняется через /retro и /learn"
fi

# Дрейф seed: страж test_seed_integrity.py проверяет только интринсик-свойства
# (счётчики/scope), но НЕ content-drift — его ловит только regen-seed.py --check.
# Без этой проверки seed «застывает» при росте рабочей базы (false-green перед
# релизом → чистая установка получает неполную мудрость). Неблокирующий warn.
if command -v python3 >/dev/null 2>&1 && [ -f "$CLAUDSOUL_DIR/scripts/regen-seed.py" ] && [ -d "$CLAUDE_HOME/global-lessons" ]; then
    if python3 "$CLAUDSOUL_DIR/scripts/regen-seed.py" --check >/dev/null 2>&1; then
        check_pass "seed синхронен с рабочей базой (regen-seed --check)"
    else
        check_warn "seed расходится с рабочей базой — пересобрать перед релизом: python3 scripts/regen-seed.py"
    fi
fi

# 6. MCP-сервер
echo ""
echo "6. MCP-сервер (опционально):"
if [ -n "$CLAUDSOUL_DIR" ] && [ -d "$CLAUDSOUL_DIR/mcp-server" ]; then
    if [ -d "$CLAUDSOUL_DIR/mcp-server/.venv" ]; then
        check_pass ".venv создан"
        if [ -x "$CLAUDSOUL_DIR/mcp-server/.venv/bin/python" ]; then
            check_pass "python в .venv доступен"
        else
            check_warn "python в .venv недоступен"
        fi
    else
        check_warn ".venv не создан — uv sync пропущен или uv не установлен"
    fi
else
    check_warn "mcp-server/ не найден или CLAUDSOUL_DIR не задан"
fi

if command -v uv >/dev/null 2>&1; then
    check_pass "uv доступен"
else
    check_warn "uv не доступен — MCP не будет работать"
fi

# 7. Session Registry
echo ""
echo "7. Session Registry:"
if [ -d "$CLAUDE_HOME/sessions/active" ]; then
    check_pass "~/.claude/sessions/active/ существует"
else
    check_warn "~/.claude/sessions/active/ отсутствует"
fi

# Итог
echo ""
echo -e "${GREEN}━━ Итог ━━${NC}"
echo "  Прошло:        $PASS"
echo "  Предупреждений: $WARN"
echo "  Провалов:       $FAIL"
echo ""

if [ "$FAIL" -gt 0 ]; then
    echo -e "${RED}Установка неполная — критичные компоненты отсутствуют.${NC}"
    exit 1
elif [ "$WARN" -gt 0 ]; then
    echo -e "${YELLOW}Установка работает, но есть некритичные пропуски (см. ⚠ выше).${NC}"
    exit 2
else
    echo -e "${GREEN}Установка прошла полностью.${NC}"
    exit 0
fi
