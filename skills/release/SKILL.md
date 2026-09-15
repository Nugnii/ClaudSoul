---
name: release
description: "Выпустить релиз проекта: bump SemVer → CHANGELOG из conventional commits → sync README/CLAUDE.md → commit + tag. Применяет global `## Versioning discipline`."
description_en: "Ship a project release: bump SemVer → CHANGELOG from conventional commits → sync README/CLAUDE.md → commit + tag. Applies the global `## Versioning discipline` rule."
user-invocable: true
argument-hint: "[patch|minor|major] [--push]"
---

# Release

**Type:** worker

Выпустить новую версию проекта. Реализация global rule `## Versioning discipline` из `~/.claude/CLAUDE.md`.

## Аргументы

- `patch` / `minor` / `major` — явный уровень бампа. Если не указан — auto-detect из conventional commits с прошлого тега (см. `Auto-detect bump`).
- `--push` — после успешного релиза автоматически `git push` ветки и тегов. По умолчанию **выключено**.

Примеры:
- `/release` — auto-detect bump, без push
- `/release minor` — явно minor, без push
- `/release patch --push` — явный patch, с push

## Pre-flight checks (ABORT если фейлятся)

1. Working tree чистый: `git status --porcelain` пустой. Если нет — попросить юзера закоммитить или stash'нуть.
2. На ветке (не detached HEAD): `git symbolic-ref -q HEAD`.
3. Нет активного merge/rebase: `.git/MERGE_HEAD`, `.git/REBASE_HEAD` отсутствуют.
4. Existence: один из version sources найден (см. ниже). Если ни одного — попросить запустить `/init-project` или создать `VERSION` вручную.
5. CHANGELOG.md существует. Если нет — создать минимальный шаблон (как в `/init-project`), но предупредить юзера.
6. Если у проекта объявлен прогон тестов — выполнить его; ненулевой код = ABORT.
   Для ClaudSoul: `bash hooks/tests/run_all.sh`. В других проектах — команда из
   проектного CLAUDE.md / package.json (`npm test`) / Makefile; нет объявленного
   прогона — шаг пропускается с пометкой юзеру. Повод: v1.32.0 ушёл с красным
   набором тестов — тег опубликован, пять корней чинили после релиза.
7. Если у проекта есть генерируемая поставка знаний — сверить её с источником:
   для ClaudSoul `python3 scripts/regen-seed.py --check` → 0, иначе ABORT с советом
   `python3 scripts/regen-seed.py`. Нет `scripts/regen-seed.py` — шаг пропускается.
   Повод (12 сентября 2026, D354): правило «перед релизом — `--check`» стояло прозой в
   проектном `CLAUDE.md` без исполнителя, seed отставал от базы между релизами по норме,
   и отставание в тег не ловил никто.

## Source of truth: версия проекта

Сканировать в этом порядке, первый найденный — source of truth:
1. `VERSION` (текстовый файл, одна строка `MAJOR.MINOR.PATCH`)
2. `package.json` (поле `version`)
3. `pyproject.toml` (`[project] version` или `[tool.poetry] version`)
4. `Cargo.toml` (`[package] version`)
5. `setup.py` (`version=`)
6. `version.txt`

Если найдено несколько — приоритет по списку. Остальные синхронизируются от source of truth (показать юзеру какие файлы будут обновлены).

**ИСКЛЮЧЕНИЕ: носитель публичного обещания.** Файл пакета виден чужим людям в реестре и
сообщает им, что готово. Перед синхронизацией проверить его `description` и `private`:
если пакет объявлен заглушкой («placeholder», «in development», «not ready»), НЕ поднимать
его версию — это объявит наружу готовность, которой нет. Назвать исключение юзеру и
оставить файл нетронутым.

Повод измерен 2026-08-28 на ClaudSoul: `VERSION` = 1.28.1, `package.json` = 0.0.4 с
описанием «Placeholder release — full installer in development». Слепое исполнение правила
подняло бы npm-версию до 1.29.0.

## Auto-detect bump

Анализировать `git log <last-tag>..HEAD` (если тегов нет — `git log` с начала истории). Парсить conventional commits:

| Маркер в коммите | Bump |
|------------------|------|
| `feat!:` / `fix!:` / `BREAKING CHANGE:` в теле | **major** |
| `feat:` / `feat(scope):` | **minor** |
| `fix:` / `perf:` / `refactor:` без break | **patch** |
| `docs:` / `chore:` / `test:` / `style:` only | **patch** (но предупредить юзера, может релиз не нужен) |

**Pre-1.0 special case:** если текущая версия `0.X.Y`, то `BREAKING CHANGE` мапится в **minor** (по SemVer pre-1.0 правилам), не major. Предупредить юзера: «релиз содержит breaking changes, в pre-1.0 это minor — но при подъёме 1.0.0 надо учесть».

## Process

### 1. Pre-flight
Запустить все pre-flight checks. Если фейл — abort с объяснением.

### 2. Determine current version
Прочитать source of truth. Показать юзеру: `Текущая версия: X.Y.Z (источник: VERSION | package.json | ...)`.

### 3. Determine bump level
- Если аргумент `patch|minor|major` — взять его.
- Иначе auto-detect из commits с прошлого тега. Показать юзеру: `Auto-detect: <level> (на основе N коммитов: M feat, K fix, ...)`.

### 4. Compute new version
- `patch`: `X.Y.(Z+1)`
- `minor`: `X.(Y+1).0`
- `major`: `(X+1).0.0`

Показать юзеру: `Новая версия: A.B.C → A.B.D`. Спросить подтверждение если auto-detect (не если явный аргумент).

### 5. Update version source
- Обновить source of truth файл.
- Если есть другие version sources — синхронизировать от source of truth, показать diff юзеру.

### 6. Update CHANGELOG.md

**Случай A — `[Unreleased]` непустой:**
- Переименовать `## [Unreleased]` → `## [A.B.C] - YYYY-MM-DD` (текущая дата).
- Добавить новый пустой блок `## [Unreleased]` сверху.

**Случай B — `[Unreleased]` пустой/отсутствует:**
- Сгенерировать черновик из conventional commits с прошлого тега, разнести по секциям:
  - `feat:` → `### Added` (или `### Changed` если scope намекает на enhancement)
  - `fix:` → `### Fixed`
  - `refactor:` / `perf:` → `### Changed`
  - `docs:` → `### Documentation`
  - Удалённые фичи (`feat!:` с явным removal) → `### Removed`
- Показать юзеру черновик. Спросить: «Принять как есть / отредактировать / отменить?» Если отменить — abort.
- После approve — записать в CHANGELOG как блок `## [A.B.C] - YYYY-MM-DD`.

### 7. Sync public docs (правило `On version bumps — sync public docs`)

Найти и предложить обновить:
- **README.md Roadmap section** — если есть таблица/список версий, показать что нужно добавить.
- **CLAUDE.md status** — если в проектном CLAUDE.md есть упоминание текущей версии, обновить.
- **`Текущая версия` в CLAUDE.md «Точки входа»** — если есть.

Для каждого файла показать diff юзеру. Не менять автоматически — это feature copy, требует review.

### 8. Commit

```bash
git add VERSION CHANGELOG.md <other version sources> <synced docs>
git commit -m "chore(release): vA.B.C"
```

Сообщение коммита фиксированное: `chore(release): vX.Y.Z`. Без тела (для одной версии хватает CHANGELOG).

### 9. Tag

```bash
git tag -a vA.B.C -m "Release vA.B.C"
```

Annotated tag (`-a`), не lightweight — annotated теги несут метаданные (author, date) и попадают в `git log`.

### 10. Push (только если `--push`)

```bash
git push origin <current-branch>
git push origin vA.B.C
```

Если без `--push` — показать команды юзеру, чтобы он сам пушил когда готов.

После push — если в проекте есть `scripts/ci-status.sh`, дождаться исхода CI
релизного коммита: `bash scripts/ci-status.sh <sha>` (скрипт опрашивает прогон
СВОЕГО sha, не самый свежий). Красный — назвать юзеру немедленно, не молчать.
Локальный прогон тестов (pre-flight 6) этого не заменяет: macOS ≠ Linux CI.

### 11. Post-release report

Показать юзеру:
```
✓ Released vA.B.C
✓ Commit: <sha>
✓ Tag: vA.B.C
✓ CHANGELOG updated
[✓ Pushed to origin] | [→ Push manually: git push && git push origin vA.B.C]

Следующая версия начинается с пустым [Unreleased] блоком в CHANGELOG.
```

## Definition of Done

- [ ] Pre-flight checks все прошли
- [ ] Source of truth обновлён, остальные version sources синхронизированы
- [ ] CHANGELOG: новый блок `[A.B.C] - YYYY-MM-DD`, пустой `[Unreleased]` сверху
- [ ] README/CLAUDE.md sync — показан diff, юзер approve
- [ ] Commit `chore(release): vA.B.C` создан
- [ ] Annotated tag `vA.B.C` создан
- [ ] Если `--push` — pushed; иначе показаны команды для ручного push
- [ ] Если `--push` и в проекте есть `scripts/ci-status.sh` — CI релизного sha дождались, исход назван юзеру
- [ ] Юзер видел финальный отчёт

## Failure modes

- **Working tree dirty** → abort, попросить commit/stash.
- **Нет source of truth** → abort, попросить `/init-project` или создать VERSION.
- **Нет коммитов с прошлого тега** → abort, нечего релизить.
- **Auto-detect неоднозначен** (всё `chore:`/`docs:`) → попросить явный bump.
- **CHANGELOG конфликтует** (нет блока `[Unreleased]`) → создать его или попросить юзера привести в порядок.

## Edge cases

- **Первый релиз** (тегов нет): анализировать всю историю с первого коммита. Если CHANGELOG `[Unreleased]` пуст — генерировать большой черновик, юзер скорее всего захочет отредактировать.
- **Pre-1.0 (`0.X.Y`)**: `BREAKING CHANGE` мапится в minor, не major. Major (`1.0.0`) — отдельное событие, требует явного `/release major`.
- **Monorepo с разными package.json**: текущая реализация поддерживает только один version source на корень репо. Для monorepo нужен расширенный скилл `/release-monorepo` (не делаем сейчас).

**Version:** 1.2.0
**Last Updated:** 2026-09-12
