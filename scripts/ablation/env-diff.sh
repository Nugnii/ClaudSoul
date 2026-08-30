#!/usr/bin/env bash
# env-diff.sh — автоматическая проверка песочницы против манифеста treatment (§6).
#
# Манифест: Full = правила ClaudSoul + хуки + скиллы + MCP + снимок базы знаний;
# Core = тот же снимок базы знаний + инжектор обвязки и больше ничего;
# Vanilla = ни одного компонента ClaudSoul. Расхождение до старта =
# infrastructure_failure (протокол §6) — код выхода 1 и именованные находки.
#
# Проверка Core двусторонняя намеренно: плечо задано и тем, что в нём есть, и
# тем, чего в нём быть не должно. Односторонняя проверка пропустила бы
# протёкшую policy — а именно её отсутствие и есть treatment этого плеча.
#
# Использование: env-diff.sh full|core|vanilla <sandbox_home>
set -euo pipefail

ARM="${1:?плечо: full|core|vanilla}"
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
core)
    [ -d "$H/.claude/global-lessons" ]                || say "core: нет снимка базы знаний"
    [ -f "$H/.claude/core/inject.py" ]                || say "core: нет инжектора плеча"
    [ -f "$H/.claude/settings.json" ]                 || say "core: нет settings.json (регистрация инжектора)"
    ls "$H/.claude/hooks/"*.sh >/dev/null 2>&1        && say "core: протекли хуки ClaudSoul"
    [ -f "$H/.claude/CLAUDE.md" ]                     && say "core: протекли глобальные правила"
    [ -d "$H/.claude/skills" ]                        && say "core: протекли скиллы"
    [ -d "$H/.claude/commands" ]                      && say "core: протекли скиллы (commands)"
    [ -d "$H/.claude/projects" ] && ls "$H/.claude/projects"/*/memory/*.md >/dev/null 2>&1 \
                                                      && say "core: протекли фрагменты памяти"
    grep -rqs "claudsoul" "$H/.claude/settings.json" 2>/dev/null \
                                                      && say "core: MCP/hooks ClaudSoul в settings.json"
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
*)  echo "env-diff: плечо — full|core|vanilla" >&2; exit 1 ;;
esac

if [ "$fail" -ne 0 ]; then
    echo "env-diff: расхождение с манифестом treatment → infrastructure_failure (§6)" >&2
    exit 1
fi
exit 0
