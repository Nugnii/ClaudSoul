#!/usr/bin/env bash
# test_project_conformance.sh — проверка соответствия обязана мерить работу, а не договор.
#
# Повод дословно: «а если выполнить инициацию в том проекте, где она ранее уже была?
# приведёт ли это к тому, что по-новому перепишется какой-то файл инструкций? Было бы
# неплохо, если бы происходил аудит соответствия актуальной версии взаимодействия».
#
# Первая версия проверки сравнивала ЗАГОЛОВКИ CLAUDE.md как строки и объявила устаревшим
# сам ClaudSoul: «Стек» против «Стек технологий». Тот же класс, что чинился всю неделю —
# совпадение с текстом вместо совпадения со смыслом. Поэтому здесь закреплено разделение:
# ДЕФЕКТ — только то, что ломает названный механизм; отличие от шаблона — справка.
#
# T4 закрепляет, что `sessions/` и `refactoring/` не входят в РАСХОЖДЕНИЯ. Обоснование —
# не «их никто не использует» (это было моей ошибкой в v1.16.0: замер спрашивал, какой
# ХУК ссылается на путь, а писатель там агент по правилу; живой счёт в ProjectA_NEW —
# 19 и 40 файлов). Обоснование в другом: их отсутствие ничего не ломает. Проект без
# рефакторинга законно не имеет `refactoring/`, и объявлять это дефектом значит делать
# фон. `modules/` тоже не требуется отдельно — см. проверку выше про описание устройства.

set -uo pipefail

REPO="$(cd "$(dirname "$0")/../.." && pwd)"
SCRIPT="$REPO/scripts/project-conformance.sh"
[ -f "$SCRIPT" ] || { echo "FAIL: нет $SCRIPT"; exit 1; }
command -v python3 >/dev/null 2>&1 || { echo "SKIP: нет python3"; exit 0; }

PASS=0
FAIL=0
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
ok()  { PASS=$((PASS + 1)); }
bad() { FAIL=$((FAIL + 1)); echo "FAIL [$1]: $2"; }
has() { printf '%s' "$2" | grep -qF -- "$1"; }

# Шаблон-фикстура: девять нумерованных разделов, как в настоящем.
mkdir -p "$TMP/tmpl"
{ for i in 1 2 3 4 5 6 7 8 9; do printf '## %d. Раздел %d\n\nтекст\n\n' "$i" "$i"; done; } \
    > "$TMP/tmpl/CLAUDE.md.tmpl"

_mkproj() { # $1=имя; создаёт проект «по договору»
    local p="$TMP/$1"
    mkdir -p "$p/.claude-docs/modules" "$p/.git"
    { for i in 1 2 3 4 5 6 7 8 9; do printf '## %d. Раздел %d\n\nтекст\n\n' "$i" "$i"; done; } > "$p/CLAUDE.md"
    printf '# Session Log\n' > "$p/SESSION.md"
    printf '# BACKLOG\n' > "$p/BACKLOG.md"
    printf '0.1.0\n' > "$p/VERSION"
    printf '# Changelog\n' > "$p/CHANGELOG.md"
    # Путь берётся РАЗРЕШЁННЫЙ: скрипт делает `pwd -P`, а на macOS каталог временных
    # файлов лежит за симлинком /var → /private/var. Фикстура с неразрешённым путём
    # кодировала бы другое имя, и проверка памяти промахивалась бы всегда.
    p=$(cd "$p" && pwd -P)
    local enc="-${p#/}"; enc="${enc//\//-}"; enc="${enc// /-}"
    mkdir -p "$TMP/projects/$enc/memory"
    printf '# MEMORY\n' > "$TMP/projects/$enc/memory/MEMORY.md"
    printf '%s' "$p"
}
run() { CLAUDSOUL_TEMPLATES="$TMP/tmpl" CLAUDE_PROJECTS_DIR="$TMP/projects" bash "$SCRIPT" "$1" 2>&1; }

# --- T1: проект по договору — расхождений нет, код возврата 0 ---
P=$(_mkproj "good")
OUT=$(run "$P"); RC=$?
[ "$RC" -eq 0 ] && ok || bad "T1a" "здоровый проект дал код $RC: $OUT"
has "Расхождений нет" "$OUT" && ok || bad "T1b" "нет строки об исправном состоянии"

# --- T2: проверка ничего не пишет ---
# Главное свойство: в CLAUDE.md живут написанные руками бизнес-правила.
BEFORE=$(cd "$P" && find . -type f | sort | xargs shasum 2>/dev/null | shasum)
run "$P" >/dev/null
AFTER=$(cd "$P" && find . -type f | sort | xargs shasum 2>/dev/null | shasum)
[ "$BEFORE" = "$AFTER" ] && ok || bad "T2" "проверка изменила файлы проекта"

# --- T3: каждое расхождение называет механизм ---
P2=$(_mkproj "broken"); rm -f "$P2/CLAUDE.md" "$P2/CHANGELOG.md"; rm -rf "$P2/.claude-docs/modules"
OUT=$(run "$P2"); RC=$?
[ "$RC" -ne 0 ] && ok || bad "T3a" "проект с дырами вернул 0"
has "CLAUDE.md отсутствует" "$OUT" && ok || bad "T3b" "не назван отсутствующий CLAUDE.md"
has "docs-family-check.sh:208" "$OUT" && ok || bad "T3c" "расхождение не называет механизм, который ломается"
has "нет CHANGELOG.md" "$OUT" && ok || bad "T3d" "версионная дисциплина не проверена"

# --- T4: sessions/ и refactoring/ не входят в РАСХОЖДЕНИЯ ---
# Не потому, что их никто не использует — это было ошибкой v1.16.0, см. врезку в шапке.
# А потому, что их отсутствие ничего не ломает: проект без рефакторинга законно не имеет
# `refactoring/`, и объявлять это дефектом значит делать фон.
#
# Проверяется ПОВЕДЕНИЕ, а не текст сообщения. Первая версия T4 искала слова «sessions» и
# «refactoring» в выводе — и прошла вхолостую под откатом, где условие вернули, а сообщение
# осталось прежним. Ровно то, за чем этот тест и написан: совпадение с текстом вместо
# совпадения с делом.
P3=$(_mkproj "no-dead-dirs")
[ -d "$P3/.claude-docs/sessions" ]    && bad "T4-фикстура" "мёртвый каталог создан фикстурой — случай не тот" || ok
[ -d "$P3/.claude-docs/refactoring" ] && bad "T4-фикстура2" "мёртвый каталог создан фикстурой" || ok
OUT=$(run "$P3"); RC=$?
[ "$RC" -eq 0 ] && ok \
    || bad "T4" "проект БЕЗ sessions/ и refactoring/, но с modules/, объявлен несоответствующим: $OUT"

# --- T5: отличие заголовков — справка, а не дефект ---
# Отрицательный контроль на первую версию: она объявляла устаревшим сам ClaudSoul.
P4=$(_mkproj "renamed")
python3 - "$P4/CLAUDE.md" <<'PY'
import pathlib, sys, re
p = pathlib.Path(sys.argv[1])
p.write_text(re.sub(r'^## 2\. Раздел 2$', '## 2. Совсем иначе назван', p.read_text(), flags=re.M))
PY
OUT=$(run "$P4"); RC=$?
[ "$RC" -eq 0 ] && ok || bad "T5a" "переименованный раздел объявлен расхождением — сопоставление по тексту вернулось"
has "нумерация разделов" "$OUT" && ok || bad "T5b" "нумерация не проверяется вовсе"

# --- T6: пропавший раздел по НОМЕРУ попадает в справку и не роняет прогон ---
P5=$(_mkproj "short")
python3 - "$P5/CLAUDE.md" <<'PY'
import pathlib, sys, re
p = pathlib.Path(sys.argv[1])
t = re.sub(r'## [789]\. Раздел [789]\n\nтекст\n\n', '', p.read_text())
p.write_text(t)
PY
OUT=$(run "$P5"); RC=$?
has "нет №7, №8, №9" "$OUT" && ok || bad "T6a" "недостающие разделы не названы: $OUT"
[ "$RC" -eq 0 ] && ok || bad "T6b" "справочное отличие уронило прогон — станет фоном за неделю"

# --- T7: протухший SESSION.md — дефект, свежий — нет ---
P6=$(_mkproj "stale")
touch -t 202601010000 "$P6/SESSION.md"
has "SESSION.md не обновлялся" "$(run "$P6")" && ok || bad "T7a" "устаревший SESSION.md не замечен"
touch "$P6/SESSION.md"
has "SESSION.md не обновлялся" "$(run "$P6")" && bad "T7b" "свежий SESSION.md назван протухшим" || ok

# --- T7c: проект без BACKLOG.md — расхождение названо (читатель без писателя) ---
P7=$(_mkproj "nobl")
rm "$P7/BACKLOG.md"
has "BACKLOG.md отсутствует" "$(run "$P7")" && ok || bad "T7c" "проект без BACKLOG.md прошёл как здоровый"

# --- T8: скилл инициации ведёт на эту проверку ---
# Без этого проверка есть, а гестом «запусти инициацию» её не достать.
grep -q 'project-conformance' "$REPO/skills/init-project/SKILL.md" && ok \
    || bad "T8" "init-project не зовёт проверку — повторный запуск снова рискует перезаписью"

echo ""
echo "project conformance tests: $PASS/$((PASS + FAIL)) passed"
[ "$FAIL" -eq 0 ]
