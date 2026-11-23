# Стек-специфичные правила — каталог паков для аудита

> Дополнение к `dev-rules-canon.md` (универсальные A–L). Здесь — **критичное по
> стекам**: что в данном языке/рантайме LLM ломает чаще всего и что закрывается
> механизмом (линтер/типчекер/CI/lock). При аудите: определить стек по сигналам,
> взять соответствующий пак, проверить каждое правило (механизмом ИЛИ правилом),
> в проект записать только **lean-строки** пака. Generic-пак применяется к любому
> стеку. Принцип над всеми тот же: где можно сделать механизмом — делать механизмом,
> текст в правилах проекта только для того, что не автоматизируется (канон D5).

## Определение стека

| Стек | Сигналы в корне проекта или части |
|------|-----------------------------------|
| **Python** | `pyproject.toml` · `setup.py`/`setup.cfg` · `requirements*.txt` · `Pipfile`(`.lock`) · `poetry.lock`/`uv.lock`/`pdm.lock` · `tox.ini` · `*.py` · директория с `__init__.py` |
| **Node / TypeScript** | `package.json` · `package-lock.json`/`yarn.lock`/`pnpm-lock.yaml`/`bun.lockb` · `tsconfig.json` (→ TS) · `node_modules/` · `.nvmrc`/`volta` · `*.ts`/`*.tsx`/`*.js`/`*.mjs` |
| **Go** | `go.mod` · `go.sum` · `go.work` · `vendor/` с `modules.txt` · `*.go` · `main.go`/`cmd/` |
| **Rust** | `Cargo.toml` · `Cargo.lock` · `rust-toolchain.toml`/`rust-toolchain` · `src/main.rs`/`src/lib.rs` · `target/` · `*.rs` |
| **Ruby** | `Gemfile` · `Gemfile.lock` · `*.gemspec` · `.ruby-version` · `config.ru`/`Rakefile` · `bin/rails` (→ Rails) · `*.rb` |
| **Java / Kotlin** | `pom.xml` (Maven) · `build.gradle(.kts)` (Gradle) · `settings.gradle(.kts)` · `gradlew`/`.mvn/` · `gradle.lockfile` · `*.java`/`*.kt`/`*.kts` · `src/main/java`\|`kotlin` |
| **PHP** | `composer.json` · `composer.lock` · `artisan` (→ Laravel) · `vendor/` с `autoload.php` · `*.php` |
| **.NET (C#/F#)** | `*.sln` · `*.csproj`/`*.fsproj`/`*.vbproj` · `Directory.Build.props`/`Directory.Packages.props` · `global.json` · `packages.lock.json` · `nuget.config` · `*.cs`/`*.fs` |

Сигналы искать не только в корне репозитория, но и в корнях частей из Phase 1
(monorepo: `apps/*`, `packages/*`, `services/*` — манифесты/локи часто там, а корень
пуст или содержит лишь оркестратор); при необходимости — рекурсивно по дереву частей.
Несколько наборов сигналов → проект многостековый: применять пак к каждой части
(см. Phase 1/3 — части по смыслу). Стека нет в таблице (Go/Rust/Ruby/Java/PHP/.NET) —
применять только Generic-пак; полный пак для этого стека добавится позже.

## Generic-пак (любой стек)

Кандидаты, инстанцирующие канон на уровне инфраструктуры проекта. Проверять для
каждого стека; в проект — только не покрытое механизмом и не самоочевидное.

- **G1. Точные команды.** Зафиксировать в правилах проекта дословные команды
  build/test/lint/run — те, что не угадать из дефолтов (флаги, env, директория
  запуска). «Работает» — только показав вывод этих команд. Инстанцирует A2/D2.
- **G2. Lockfile в репозитории.** Коммитить lockfile (`package-lock`/`yarn`/`pnpm`,
  `poetry`/`uv.lock`, `Cargo.lock`, `go.sum`, `Gemfile.lock`, `composer.lock`,
  `packages.lock.json`) и ставить из него (`ci`/`--frozen`/`--locked`), не из
  манифеста. Без него «работает у меня» ≠ CI (скрытый риск из Phase 3).
- **G3. Один конфиг форматтера/линтера.** Один источник правил стиля в репо,
  форматирование автоматическое. Стиль не описывать прозой — на конфиг ссылаться
  (канон D5 механизм > текст, D3 не дублировать выводимое).
- **G4. CI прогоняет проверки на PR.** На каждый PR/push CI запускает те же команды,
  что и G1 (test+lint+build), блокирует мёрж при красном. Локальные команды и CI
  совпадают. CI — единственная неотменяемая проверка pass/fail (A2 механизмом).
- **G5. Секреты вне репозитория.** `.gitignore` покрывает секреты и артефакты сборки
  (`.env`, ключи, токены, `target`/`build`/`dist`, `node_modules`, `__pycache__`).
  Конфиг — через env/секрет-стор, в репо только `.env.example`. Закоммиченный секрет =
  утечка навсегда (история git).
- **G6. Закреплённая версия тулчейна.** Версия языка/рантайма одним файлом (`.nvmrc`,
  `.ruby-version`, `rust-toolchain.toml`, go-директива в `go.mod`, `global.json`,
  `.python-version`) — один источник для людей и CI. Разные версии → невоспроизводимые
  баги (квирк среды, D2).

## Python

**Критичные правила (проверить каждое; механизм в скобках):**

- **PY1. Type hints + статический чекер.** Публичные функции/методы аннотированы;
  mypy или pyright проходит без ошибок на CI и перед коммитом. Hints без чекера —
  декорация, расходятся с реальностью. *Механизм:* mypy/pyright в CI + pre-commit,
  `[tool.mypy] strict=true` где возможно.
- **PY2. Форматтер + линтер обязательны.** ruff (или black+ruff/flake8) форматирует и
  линтует весь код; diff формата = провал CI. Стиль задаёт инструмент, не споры (A6).
  *Механизм:* `ruff format --check` + `ruff check` в CI/pre-commit, `[tool.ruff]` в
  pyproject.
- **PY3. Тесты pytest с явной командой.** Есть pytest-набор и зафиксированная команда
  (`pytest -q` / `uv run pytest`) в правилах; новый код с тестом, баг — с падающим
  тестом сперва (B4). Без явной команды Claude угадывает раннер и «проверяет глазами»
  (A2). *Механизм:* CI-job на каждый PR, `[tool.pytest.ini_options]`.
- **PY4. Зависимости и окружение под контролем.** Один манифест (pyproject) + lock
  (`uv.lock`/`poetry.lock`), версии запинены; работа в venv/uv, не системный Python.
  Новую зависимость — по явной необходимости (B2). *Механизм:* lock в git, CI ставит
  из lock (`uv sync --frozen`/`poetry install --no-update`), `pip install` в систему
  запрещён.
- **PY5. src-layout и импорт пакета.** Код в `src/<pkg>/`, тесты импортируют
  установленный пакет (`pip install -e .`), не относительные пути из корня. Flat-layout
  даёт ложно-зелёные тесты (импортируется локальная папка, не то, что установится).
  *Механизм:* `src/` + `[project]` в pyproject; CI прогоняет против установленного.
- **PY6. Никаких голых except.** Запрещён `except:` и `except Exception:` без
  ре-рейза/логирования; ловить конкретные исключения (A4 — корень, не симптом). Голый
  except глотает KeyboardInterrupt и маскирует баги. *Механизм:* ruff BLE001/E722.
- **PY7. Логирование вместо print.** В библиотечном/серверном коде — `logging` (logger
  на модуль), не `print` (тот допустим только в CLI-выводе пользователю). *Механизм:*
  ruff T20 (flake8-print), CI блокирует print в `src/`.
- **PY8. Никаких мутабельных дефолтов и valid на границах.** Не `[]`/`{}`/объекты как
  дефолтные аргументы (None + инициализация). Внешний вход (HTTP-body, query, env,
  файлы) валидировать через pydantic/схему на границе. *Механизм:* ruff B006; pydantic
  v2 / DRF-serializers / Flask-схемы в request-слое.

**lean-строки в проект (то, что не покрыто конфигом и не самоочевидно):**

- Тесты: `pytest -q` (или uv/poetry-вариант) — гонять перед «готово», баг = падающий тест сперва.
- Линт+формат: `ruff check` и `ruff format --check` проходят; стиль задаёт ruff, не споры.
- Типы: mypy/pyright без ошибок на публичном API перед коммитом.
- Зависимости: только pyproject + lock, версии запинены, работа в venv/uv (не системный Python); новую — по необходимости.
- Код пакета в `src/<pkg>/`; запрещены голый except, print в библиотечном коде (logging), мутабельные дефолты (`[]`/`{}` → None); внешний вход валидируется pydantic/схемой на границе.

## TypeScript/JavaScript (Node)

**Критичные правила (проверить каждое; механизм в скобках):**

- **TS1. Строгий tsconfig.** `compilerOptions.strict:true` ОБЯЗАТЕЛЕН; плюс
  `noUncheckedIndexedAccess`, `noImplicitOverride`, `exactOptionalPropertyTypes` (где
  проект готов). Без strict типы — украшение; `arr[i]` без noUncheckedIndexedAccess
  врёт о undefined. *Механизм:* `tsc --noEmit` в CI/pre-commit, typed-linting
  (`parserOptions.project`).
- **TS2. Запрет any, предпочесть unknown.** any вне типов запрещён: неизвестное —
  `unknown` с narrowing; библиотечные дыры — точечный `// @ts-expect-error` с
  причиной, не `// @ts-ignore`. Кастов `as` избегать. any выключает проверку
  транзитивно. *Механизм:* ESLint no-explicit-any, no-unsafe-*, ban-ts-comment.
- **TS3. Валидация на границах (runtime).** Внешние данные (HTTP body/query/params,
  env, ответы API, файлы) парсить схемой (zod и т. п.) на входе. Внутри — тип через
  `z.infer`, не объявлен руками параллельно. Типы стираются при компиляции — `as User`
  ничего не проверяет. *Механизм:* zod/valibot на каждом boundary.
- **TS4. Нет плавающих промисов.** Каждый Promise — `await`, `.catch` или явный `void`
  для fire-and-forget. Плавающий промис = необработанный rejection (теряется ошибка,
  падение процесса). *Механизм:* ESLint no-floating-promises, no-misused-promises
  (typed-linting); `process.on('unhandledRejection')` как сетка.
- **TS5. Тесты + единая команда запуска.** Vitest или Jest (один на проект), команда
  `npm test` в scripts. Новый код с тестом; баг — падающим тестом до фикса. Прогнать и
  показать вывод, не утверждать «работает» (A2). *Механизм:* scripts.test, прогон в
  CI/pre-push.
- **TS6. Менеджер пакетов + закоммиченный лок-файл.** Один менеджер (pnpm\|yarn\|npm),
  его lockfile закоммичен и не смешан с чужими. Установка `npm ci`/`pnpm install
  --frozen-lockfile` (детерминизм). Lockfile руками не править (B2). *Механизм:*
  `packageManager` (Corepack), CI на `--frozen-lockfile`, `only-allow` в preinstall.
- **TS7. ESLint + Prettier, разделение ролей.** ESLint — корректность (typed-rules),
  Prettier — формат; не дублировать (`eslint-config-prettier` гасит стилевые правила
  ESLint). Линт/формат-чек до коммита. Следовать конфигу проекта (B1/B5). *Механизм:*
  `eslint.config.*` + `.prettierrc`, lint-staged + husky, CI.
- **TS8. Валидация env при старте.** Переменные окружения — через одну типизированную
  схему, fail-fast при старте, не разбросанный `process.env.X`. Секреты не хардкодить
  и не коммитить; `.env.example` фиксирует ключи. `process.env.X` — `string |
  undefined`, всплывает глубоко случайным TypeError (A4). *Механизм:* zod-схема
  env-модуля, `.env` в `.gitignore`, секрет-сканер.
- **TS9. ESM и явные границы ошибок.** Единый модульный формат (ESM при
  `"type":"module"`), не мешать `require`/`import`; импорты с расширениями где требует
  NodeNext. Бросать `Error` (не строки); на границах ловить и преобразовывать; пустой
  catch запрещён (A3/A4). *Механизм:* `module:NodeNext` + `type:module`, ESLint
  no-throw-literal, no-empty (allowEmptyCatch:false), only-throw-error.

**lean-строки в проект (то, что не покрыто конфигом и не самоочевидно):**

- TS-строгость: tsconfig `strict:true` + `noUncheckedIndexedAccess`; any запрещён — unknown с narrowing (ESLint no-explicit-any/no-unsafe-*).
- Внешние данные (HTTP/env/API/файлы) валидировать схемой zod на границе; внутренний тип — `z.infer`, не дубль руками.
- Нет плавающих промисов: await/catch/void (ESLint no-floating-promises, no-misused-promises — typed-linting).
- Один менеджер пакетов + закоммиченный lockfile; установка frozen/ci. Один тест-раннер (vitest\|jest), команда `npm test` — прогнать и показать вывод, не «работает».
- ESLint (корректность) + Prettier (формат) без дублирования (eslint-config-prettier); линт/формат-чек до коммита, следовать конфигу проекта.
- env — типизированная схема с fail-fast при старте; секреты не коммитить (`.env` в `.gitignore`, `.env.example` в репо).
- Единый ESM-формат, не мешать require/import; бросать `Error` (не строки), пустой catch запрещён.

## Как пользоваться

1. **Определить стек** по таблице сигналов (Phase 1/3 — записать в карту).
2. Взять **Generic-пак** (всегда) + пак стека, если он есть (Python / Node-TS).
3. Для каждого правила пака проверить инстанцирование: механизмом (лучше) ИЛИ
   правилом ИЛИ пробел. Пробел — закрыть механизмом (линтер/CI/конфиг), а текстом в
   правила проекта — только то, что не автоматизируется и не самоочевидно (D3/D5).
4. В правила проекта добавить **lean-строки** пака (адаптивный выбор файла —
   `references/rules-output.md`). Не весь пак, не дословно критичные правила —
   только узкое ядро.
5. Стек без полного пака (Go/Rust/Ruby/Java/PHP/.NET) — Generic-пак + наблюдение, что
   stack-пак добавится позже; не выдумывать правила из памяти.
