#!/usr/bin/env bash
# СУДИТ: scripts/sync-drifted.sh lib/carry-log.sh install.sh
# probe_D1166 — перенос не ставит новые хуки рядом со старой библиотекой ввода. Песочница установки под чужим
# CLAUDE_HOME (рамка `hooks/tests/test_sync_drifted.sh`): приёмник `hooks/hook-input-lib.sh` правлен после записанного
# в журнал переноса, у `fix-level-check.sh` (подключает её) и `secret-guard.sh` (не подключает) в установке старая
# редакция. `sync-drifted.sh --apply`: библиотека не перезаписана, `fix-level-check.sh` не перенесён и назван,
# `secret-guard.sh` перенесён. `install.sh` целиком в песочнице не прогнать (грузит агенты launchd в настоящий домен
# пользователя) — сверяется, что его цикл хуков зовёт ту же функцию `carry_ordered`.
# Красная (1), пока потребитель переносится рядом со старой библиотекой; 2 — рамка не собралась.
R="${CLAUDSOUL_REPO:-$(cd "$(dirname "$0")/../../.." && pwd)}"
for f in scripts/sync-drifted.sh lib/carry-log.sh install.sh hooks/hook-input-lib.sh hooks/fix-level-check.sh hooks/secret-guard.sh; do
    [ -f "$R/$f" ] || exit 2
done
grep -qF 'hook-input-lib' "$R/hooks/fix-level-check.sh" || exit 2
grep -qF 'hook-input-lib' "$R/hooks/secret-guard.sh" && exit 2
T=$(mktemp -d) || exit 2
trap 'rm -rf "$T"' EXIT
H="$T/home"
mkdir -p "$H/hooks/lib" "$H/commands" "$H/bin" "$H/templates" "$H/global-lessons" "$H/security" || exit 2
cp "$R"/hooks/*.sh "$H/hooks/" 2>/dev/null || exit 2
cp "$R"/hooks/lib/* "$H/hooks/lib/" 2>/dev/null || true   # каталог __pycache__ краснит cp, файлы скопированы
cp "$R"/bin/resolve-claudsoul-repo.sh "$H/bin/" && cp "$R"/templates/*.tmpl "$H/templates/" \
    && cp "$R"/scripts/statusline-claudsoul.sh "$H/" || exit 2
for d in "$R"/skills/*/; do
    n=$(basename "$d"); mkdir -p "$H/commands/$n"; cp "$d"SKILL.md "$H/commands/$n/" || exit 2
    [ -d "$d/references" ] && { mkdir -p "$H/commands/$n/references"; cp "$d"references/* "$H/commands/$n/references/" || exit 2; }
done
. "$R/lib/claude-md-merge.sh" 2>/dev/null && _cm_write_managed_block "$R/rules/CLAUDE.md" > "$H/CLAUDE.md"
cp "$R"/knowledge/*.md "$H/global-lessons/" && cp "$R"/security/* "$H/security/" || exit 2
python3 "$R/hooks/tests/_decl_hooks.py" "$R/install.sh" > "$H/settings.json" 2>/dev/null || exit 2

# Журнал знает хеш приёмника библиотеки, затем приёмник правят в установке — «разошлось в обе стороны».
( CLAUDE_HOME="$H"; . "$R/lib/carry-log.sh"; carry_record probe "$R/hooks/hook-input-lib.sh" "$H/hooks/hook-input-lib.sh" ) || exit 2
printf '# правлено в установке\n' >> "$H/hooks/hook-input-lib.sh"
printf '# старая редакция\n' >> "$H/hooks/fix-level-check.sh"
printf '# старая редакция\n' >> "$H/hooks/secret-guard.sh"
# Второй круг (скептик H1): цепочка «библиотека → библиотека → хук» — `root-cause-lib.sh` подключает отбитую библиотеку
# кодом, `session-collector.sh` называет только `root-cause-lib`. M1: нового хука (приёмника нет) пропуск не касается.
printf '# старая редакция\n' >> "$H/hooks/root-cause-lib.sh"
printf '# старая редакция\n' >> "$H/hooks/session-collector.sh"
mv "$H/hooks/accepted-alternative-gap.sh" "$T/aag-removed.sh" || exit 2

OUT=$(CLAUDE_HOME="$H" CLAUDSOUL_REPO="$R" bash "$R/scripts/sync-drifted.sh" --apply 2>&1)
grep -q 'правлено в установке' "$H/hooks/hook-input-lib.sh" || { echo "рамка: правленная библиотека перезаписана"; exit 2; }
cmp -s "$R/hooks/secret-guard.sh" "$H/hooks/secret-guard.sh" || { echo "хук без библиотеки не перенесён"; exit 1; }
grep -q 'старая редакция' "$H/hooks/fix-level-check.sh" || { echo "потребитель перенесён рядом со старой библиотекой"; exit 1; }
grep -q 'fix-level-check.sh.*hook-input-lib' <<< "$OUT" || { echo "непереносённый потребитель не назван"; exit 1; }
grep -q 'старая редакция' "$H/hooks/root-cause-lib.sh" || { echo "библиотека, подключающая отбитую, перенесена"; exit 1; }
grep -q 'старая редакция' "$H/hooks/session-collector.sh" || { echo "хук за библиотекой-посредником перенесён рядом со старой библиотекой"; exit 1; }
[ -f "$H/hooks/accepted-alternative-gap.sh" ] || { echo "новый хук пропущен — регистрация упадёт кодом 127"; exit 1; }

# install.sh: цикл хуков идёт через ту же функцию.
sed -n '/^info "Устанавливаю хуки/,/^info "Установлено hook lib/p' "$R/install.sh" | grep -v '^[[:space:]]*#' | grep -q 'carry_ordered' \
    || { echo "install.sh переносит хуки мимо carry_ordered"; exit 1; }
exit 0
