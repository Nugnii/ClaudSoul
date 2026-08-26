#!/usr/bin/env bash
# env-diff.sh — автоматическая проверка песочницы против манифеста treatment (§6).
#
# Манифест: Full = правила ClaudSoul + хуки + скиллы + MCP + снимок базы знаний;
# Vanilla = ни одного компонента ClaudSoul. Расхождение до старта =
# infrastructure_failure (протокол §6) — код выхода 1 и именованные находки.
#
# Использование: env-diff.sh full|vanilla <sandbox_home>
set -euo pipefail

ARM="${1:?плечо: full|vanilla}"
H="${2:?путь к sandbox HOME обязателен}"
[ -d "$H" ] || { echo "env-diff: $H не существует" >&2; exit 1; }

fail=0
say() { echo "  ✗ $1"; fail=1; }

case "$ARM" in
full)
    ls "$H/.claude/hooks/"*.sh >/dev/null 2>&1        || say "full: нет хуков в .claude/hooks"
    [ -f "$H/.claude/CLAUDE.md" ]                     || say "full: нет глобальных правил CLAUDE.md"
    [ -f "$H/.claude/settings.json" ]                 || say "full: нет settings.json (регистрация хуков)"
    [ -d "$H/.claude/global-lessons" ]                || say "full: нет снимка базы знаний"
    ;;
vanilla)
    ls "$H/.claude/hooks/"*.sh >/dev/null 2>&1        && say "vanilla: остались хуки ClaudSoul"
    [ -f "$H/.claude/CLAUDE.md" ]                     && say "vanilla: остались глобальные правила"
    [ -d "$H/.claude/global-lessons" ]                && say "vanilla: осталась база знаний"
    [ -d "$H/.claude/projects" ] && ls "$H/.claude/projects"/*/memory/*.md >/dev/null 2>&1 \
                                                      && say "vanilla: остались фрагменты памяти"
    grep -rqs "claudsoul" "$H/.claude/settings.json" 2>/dev/null \
                                                      && say "vanilla: MCP/hooks ClaudSoul в settings.json"
    ;;
*)  echo "env-diff: плечо — full|vanilla" >&2; exit 1 ;;
esac

if [ "$fail" -ne 0 ]; then
    echo "env-diff: расхождение с манифестом treatment → infrastructure_failure (§6)" >&2
    exit 1
fi
exit 0
