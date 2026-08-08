#!/bin/bash
# ClaudSoul — установка системы самообучения для Claude Code
# Использование: bash install.sh [путь_к_репо]

set -euo pipefail

CLAUDSOUL_DIR="${1:-$(cd "$(dirname "$0")" && pwd)}"
CLAUDE_HOME="$HOME/.claude"
GLOBAL_LESSONS="$CLAUDE_HOME/global-lessons"
SKILLS_DIR="$CLAUDE_HOME/commands"

# Цвета
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

info()  { echo -e "${GREEN}[ClaudSoul]${NC} $1"; }
warn()  { echo -e "${YELLOW}[ClaudSoul]${NC} $1"; }
error() { echo -e "${RED}[ClaudSoul]${NC} $1" >&2; }

# --- Проверки ---

if [ ! -d "$CLAUDSOUL_DIR/skills" ]; then
    error "Не найдена директория skills/ в $CLAUDSOUL_DIR"
    error "Запустите скрипт из корня репозитория ClaudSoul или передайте путь: bash install.sh /path/to/ClaudSoul"
    exit 1
fi

if [ ! -d "$CLAUDE_HOME" ]; then
    error "Не найдена директория $CLAUDE_HOME"
    error "Установите Claude Code: https://docs.anthropic.com/en/docs/claude-code/overview"
    exit 1
fi

# v1.7.5: dependency check — fail fast при отсутствии обязательных tools.
# Раньше install.sh падал глубоко в pipeline с cryptic ошибками; теперь
# понятный сигнал в начале + один консолидированный список missing.
MISSING_DEPS=()
for cmd in jq python3 git; do
    command -v "$cmd" >/dev/null 2>&1 || MISSING_DEPS+=("$cmd")
done

if [ ${#MISSING_DEPS[@]} -gt 0 ]; then
    error "Отсутствуют обязательные инструменты: ${MISSING_DEPS[*]}"
    error ""
    error "Установка на macOS:"
    error "  brew install ${MISSING_DEPS[*]}"
    error ""
    error "Установка на Debian/Ubuntu:"
    error "  sudo apt-get install ${MISSING_DEPS[*]}"
    exit 1
fi

# uv опционален — без него пропустим установку MCP-сервера, но базовая
# установка хуков и скиллов сработает. Предупреждаем сразу, не в середине.
if ! command -v uv >/dev/null 2>&1; then
    warn "uv не установлен — MCP-сервер (семантический поиск) будет пропущен."
    warn "Если нужен MCP, установите uv и перезапустите install.sh:"
    warn "  curl -LsSf https://astral.sh/uv/install.sh | sh"
fi

info "Установка ClaudSoul из $CLAUDSOUL_DIR"

# --- 0. Регистрация пути к репо ---
# Чтобы скиллы (/ingest, /entity, ...) находили mcp-server/.venv из любого проекта,
# а не только при cwd внутри ClaudSoul. См. Step 0 в skills/ingest/SKILL.md.

REPO_POINTER="$CLAUDE_HOME/claudsoul-repo"
echo "$CLAUDSOUL_DIR" > "$REPO_POINTER"
info "Путь к репо сохранён: $REPO_POINTER → $CLAUDSOUL_DIR"

# Общий резолвер репо для скиллов (вынесен из 4 inline-копий) — в известный ~/.claude/bin/.
mkdir -p "$CLAUDE_HOME/bin"
cp "$CLAUDSOUL_DIR/bin/resolve-claudsoul-repo.sh" "$CLAUDE_HOME/bin/resolve-claudsoul-repo.sh"
chmod +x "$CLAUDE_HOME/bin/resolve-claudsoul-repo.sh"
info "Резолвер репо установлен: $CLAUDE_HOME/bin/resolve-claudsoul-repo.sh"

# --- 1. Глобальные правила ---

info "Устанавливаю глобальные правила..."

GLOBAL_CLAUDE_MD="$CLAUDE_HOME/CLAUDE.md"
MASTER_RULES="$CLAUDSOUL_DIR/rules/CLAUDE.md"

# v1.7.4: marker-based merge заменил skip-on-existing/append-with-duplication.
# Старая логика «если есть Self-Learning — skip» означала что master changes
# никогда не доезжали до пользователя; альтернативная ветка append дублировала
# контент при повторных запусках. Логика merge извлечена в lib для тестов.
# shellcheck source=lib/claude-md-merge.sh
source "$CLAUDSOUL_DIR/lib/claude-md-merge.sh"

if [ -f "$GLOBAL_CLAUDE_MD" ]; then
    if grep -qF "$CLAUDE_MD_MARKER_START" "$GLOBAL_CLAUDE_MD" 2>/dev/null && \
       grep -qF "$CLAUDE_MD_MARKER_END" "$GLOBAL_CLAUDE_MD" 2>/dev/null; then
        sync_claude_md "$GLOBAL_CLAUDE_MD" "$MASTER_RULES"
        info "Правила обновлены между маркерами в $GLOBAL_CLAUDE_MD (бэкап создан)"
    elif grep -q "Self-Learning" "$GLOBAL_CLAUDE_MD" 2>/dev/null; then
        sync_claude_md "$GLOBAL_CLAUDE_MD" "$MASTER_RULES"
        info "Legacy CLAUDE.md без маркеров — переписан с маркерами (бэкап создан)"
    else
        sync_claude_md "$GLOBAL_CLAUDE_MD" "$MASTER_RULES"
        info "Правила добавлены в конец $GLOBAL_CLAUDE_MD с маркерами (бэкап создан)"
    fi
else
    sync_claude_md "$GLOBAL_CLAUDE_MD" "$MASTER_RULES"
    info "Создан $GLOBAL_CLAUDE_MD с маркерами"
fi

# --- 2. База знаний ---

info "Устанавливаю базу знаний..."

mkdir -p "$GLOBAL_LESSONS"

# Копируем META.md
cp "$CLAUDSOUL_DIR/knowledge/META.md" "$GLOBAL_LESSONS/META.md"
info "META.md установлен"

# Копируем знания (не перезаписываем существующие)
KNOWLEDGE_COUNT=0
for file in "$CLAUDSOUL_DIR"/knowledge/*.md; do
    filename=$(basename "$file")
    [ "$filename" = "META.md" ] && continue

    target="$GLOBAL_LESSONS/$filename"
    if [ -f "$target" ]; then
        warn "  $filename уже существует — пропускаю"
    else
        cp "$file" "$target"
        KNOWLEDGE_COUNT=$((KNOWLEDGE_COUNT + 1))
    fi
done
info "Установлено знаний: $KNOWLEDGE_COUNT"

# --- 3. Скиллы ---

info "Устанавливаю скиллы..."

mkdir -p "$SKILLS_DIR"

SKILLS_COUNT=0
for skill_dir in "$CLAUDSOUL_DIR"/skills/*/; do
    skill_name=$(basename "$skill_dir")
    target_dir="$SKILLS_DIR/$skill_name"

    if [ -d "$target_dir" ]; then
        # Обновляем существующий скилл
        cp "$skill_dir/SKILL.md" "$target_dir/SKILL.md"
        warn "  $skill_name — обновлён"
    else
        mkdir -p "$target_dir"
        cp "$skill_dir/SKILL.md" "$target_dir/SKILL.md"
        info "  $skill_name — установлен"
    fi

    # Copy references/ if present — нужно для `MANDATORY READ: Load references/...`
    if [ -d "$skill_dir/references" ]; then
        mkdir -p "$target_dir/references"
        cp -R "$skill_dir/references/." "$target_dir/references/"
    fi

    SKILLS_COUNT=$((SKILLS_COUNT + 1))

    # Check for duplicate in ~/.claude/skills/ (different path, also scanned by Claude Code)
    ALT_SKILLS_DIR="$CLAUDE_HOME/skills"
    if [ -d "$ALT_SKILLS_DIR/$skill_name" ]; then
        warn "  ⚠️  $skill_name также найден в $ALT_SKILLS_DIR/$skill_name"
        warn "     Это вызовет дубли в списке slash commands."
        warn "     Если это ваш скилл — удалите его вручную: rm -rf $ALT_SKILLS_DIR/$skill_name"
        warn "     Если это сторонний скилл — переименуйте один из них во избежание конфликта."
    fi
done
info "Установлено скиллов: $SKILLS_COUNT"

# Регенерация таблицы скиллов в README (единый источник правды — SKILL.md frontmatter).
# Маркеры SKILLS-TABLE живут в README.ru.md → передаём README_FILE явно, иначе скрипт
# целит README.md (без маркеров) и тихо падает. stderr НЕ глушим, чтобы WARN был виден.
REGEN_SCRIPT="$CLAUDSOUL_DIR/scripts/regen-readme-skills.sh"
if [ -x "$REGEN_SCRIPT" ]; then
    if README_FILE="$CLAUDSOUL_DIR/README.ru.md" bash "$REGEN_SCRIPT" "$CLAUDSOUL_DIR" >/dev/null; then
        info "README.ru.md: таблица скиллов регенерирована"
    else
        warn "README.ru.md: не удалось регенерировать таблицу скиллов (проверьте markers SKILLS-TABLE:START/END)"
    fi
fi

# --- 4. Хуки ---

info "Устанавливаю хуки..."

HOOKS_TARGET="$CLAUDE_HOME/hooks"
HOOKS_STATE="$HOOKS_TARGET/state"
mkdir -p "$HOOKS_STATE"

HOOKS_COUNT=0
for hook_script in "$CLAUDSOUL_DIR"/hooks/*.sh; do
    [ -f "$hook_script" ] || continue
    cp "$hook_script" "$HOOKS_TARGET/$(basename "$hook_script")"
    chmod +x "$HOOKS_TARGET/$(basename "$hook_script")"
    HOOKS_COUNT=$((HOOKS_COUNT + 1))
done
info "Установлено хуков: $HOOKS_COUNT"

# Sibling lib/ (detectors/helpers referenced by hooks by absolute path)
if [ -d "$CLAUDSOUL_DIR/hooks/lib" ]; then
    mkdir -p "$HOOKS_TARGET/lib"
    LIB_COUNT=0
    for lib_file in "$CLAUDSOUL_DIR"/hooks/lib/*; do
        [ -f "$lib_file" ] || continue
        cp "$lib_file" "$HOOKS_TARGET/lib/$(basename "$lib_file")"
        LIB_COUNT=$((LIB_COUNT + 1))
    done
    info "Установлено hook lib-файлов: $LIB_COUNT"
fi

# Baseline adaptive-stats.json (не перезаписывает существующий)
ADAPTIVE_STATS_SRC="$CLAUDSOUL_DIR/hooks/state/adaptive-stats.json"
ADAPTIVE_STATS_DST="$HOOKS_STATE/adaptive-stats.json"
if [ -f "$ADAPTIVE_STATS_SRC" ] && [ ! -f "$ADAPTIVE_STATS_DST" ]; then
    cp "$ADAPTIVE_STATS_SRC" "$ADAPTIVE_STATS_DST"
    info "Создан baseline: $ADAPTIVE_STATS_DST"
fi

# --- 5. Конфигурация хуков в settings.json ---

info "Настраиваю конфигурацию хуков..."

SETTINGS="$CLAUDE_HOME/settings.json"

# Конфигурация хуков
HOOKS_CONFIG='{
  "hooks": {
    "PostToolUse": [
      {
        "matcher": "Bash",
        "hooks": [
          {
            "type": "command",
            "command": "bash ~/.claude/hooks/knowledge-capture-reminder.sh"
          },
          {
            "type": "command",
            "command": "bash ~/.claude/hooks/ci-check-reminder.sh"
          }
        ]
      },
      {
        "matcher": "Bash|Edit|Write|Read|Grep|Glob",
        "hooks": [
          {
            "type": "command",
            "command": "bash ~/.claude/hooks/response-tracker.sh"
          }
        ]
      },
      {
        "matcher": "Bash|Edit|Write|MultiEdit",
        "hooks": [
          {
            "type": "command",
            "command": "bash ~/.claude/hooks/rework-detector.sh"
          }
        ]
      }
    ],
    "PreToolUse": [
      {
        "matcher": "Edit|Write|MultiEdit|NotebookEdit",
        "hooks": [
          {
            "type": "command",
            "command": "bash ~/.claude/hooks/budget-gate.sh"
          }
        ]
      },
      {
        "matcher": "Bash|Edit|Write|MultiEdit",
        "hooks": [
          {
            "type": "command",
            "command": "bash ~/.claude/hooks/ablation-phase-guard.sh"
          }
        ]
      },
      {
        "matcher": "Bash|Edit|Write",
        "hooks": [
          {
            "type": "command",
            "command": "bash ~/.claude/hooks/knowledge-activator.sh"
          },
          {
            "type": "command",
            "command": "bash ~/.claude/hooks/blocker-tier-check.sh"
          },
          {
            "type": "command",
            "command": "bash ~/.claude/hooks/internal-doc-leak-guard.sh"
          },
          {
            "type": "command",
            "command": "bash ~/.claude/hooks/playwright-cli-guard.sh"
          }
        ]
      },
      {
        "matcher": "Bash",
        "hooks": [
          {
            "type": "command",
            "command": "bash ~/.claude/hooks/error-tracker.sh"
          },
          {
            "type": "command",
            "command": "bash ~/.claude/hooks/bash-cost-detector.sh"
          },
          {
            "type": "command",
            "command": "bash ~/.claude/hooks/docs-family-check.sh"
          },
          {
            "type": "command",
            "command": "bash ~/.claude/hooks/changelog-reminder.sh"
          },
          {
            "type": "command",
            "command": "bash ~/.claude/hooks/module-doc-check.sh"
          },
          {
            "type": "command",
            "command": "bash ~/.claude/hooks/quality-gate-check.sh"
          },
          {
            "type": "command",
            "command": "bash ~/.claude/hooks/skill-review-check.sh"
          },
          {
            "type": "command",
            "command": "bash ~/.claude/hooks/trust-guard.sh"
          },
          {
            "type": "command",
            "command": "bash ~/.claude/hooks/bulk-copy-guard.sh"
          },
          {
            "type": "command",
            "command": "bash ~/.claude/hooks/code-review-reminder.sh"
          },
          {
            "type": "command",
            "command": "bash ~/.claude/hooks/claude-md-size-check.sh"
          }
        ]
      },
      {
        "matcher": "",
        "hooks": [
          {
            "type": "command",
            "command": "bash ~/.claude/hooks/output-language-check.sh"
          },
          {
            "type": "command",
            "command": "bash ~/.claude/hooks/fix-level-check.sh"
          }
        ]
      },
      {
        "hooks": [
          {
            "type": "command",
            "command": "bash ~/.claude/hooks/user-correction-guard.sh"
          }
        ]
      }
    ],
    "Stop": [
      {
        "matcher": "",
        "hooks": [
          {
            "type": "command",
            "command": "bash ~/.claude/hooks/session-collector.sh"
          },
          {
            "type": "command",
            "command": "bash ~/.claude/hooks/output-language-check.sh"
          },
          {
            "type": "command",
            "command": "bash ~/.claude/hooks/fix-level-check.sh"
          },
          {
            "type": "command",
            "command": "bash ~/.claude/hooks/accepted-alternative-gap.sh"
          },
          {
            "type": "command",
            "command": "bash ~/.claude/hooks/timestamp-canary-check.sh"
          }
        ]
      }
    ],
    "UserPromptSubmit": [
      {
        "matcher": "",
        "hooks": [
          {
            "type": "command",
            "command": "bash ~/.claude/hooks/reformulation-tracker.sh"
          },
          {
            "type": "command",
            "command": "bash ~/.claude/hooks/itr-event-detector.sh"
          },
          {
            "type": "command",
            "command": "bash ~/.claude/hooks/intrusiveness-tracker.sh"
          },
          {
            "type": "command",
            "command": "bash ~/.claude/hooks/decompose-detector.sh"
          },
          {
            "type": "command",
            "command": "bash ~/.claude/hooks/external-correction-gap.sh"
          },
          {
            "type": "command",
            "command": "bash ~/.claude/hooks/timestamp-inject.sh"
          },
          {
            "type": "command",
            "command": "bash ~/.claude/hooks/ablation-phase-guard.sh"
          },
          {
            "type": "command",
            "command": "bash ~/.claude/hooks/inquiry-gap.sh"
          },
          {
            "type": "command",
            "command": "bash ~/.claude/hooks/enrich-suggester.sh"
          },
          {
            "type": "command",
            "command": "bash ~/.claude/hooks/claudsoul-context-pointer.sh"
          },
          {
            "type": "command",
            "command": "bash ~/.claude/hooks/output-language-check.sh"
          },
          {
            "type": "command",
            "command": "bash ~/.claude/hooks/fix-level-check.sh"
          },
          {
            "type": "command",
            "command": "bash ~/.claude/hooks/pending-alerts-surface.sh"
          }
        ]
      }
    ],
    "SessionStart": [
      {
        "matcher": "",
        "hooks": [
          {
            "type": "command",
            "command": "bash ~/.claude/hooks/session-start.sh"
          }
        ]
      }
    ],
    "PreCompact": [
      {
        "matcher": "",
        "hooks": [
          {
            "type": "command",
            "command": "bash ~/.claude/hooks/pre-compact-finalizer.sh"
          },
          {
            "type": "command",
            "command": "bash ~/.claude/hooks/output-language-check.sh"
          },
          {
            "type": "command",
            "command": "bash ~/.claude/hooks/fix-level-check.sh"
          }
        ]
      },
      {
        "hooks": [
          {
            "type": "command",
            "command": "bash ~/.claude/hooks/pre-compact-handoff.sh"
          }
        ]
      }
    ],
    "SessionEnd": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "bash ~/.claude/hooks/session-end.sh"
          }
        ]
      }
    ]
  }
}'

if command -v jq &>/dev/null; then
    if [ -f "$SETTINGS" ] && jq -e '.hooks' "$SETTINGS" >/dev/null 2>&1; then
        # Merge: добавить отсутствующие команды, не затирая пользовательские.
        # Backup перед модификацией.
        cp "$SETTINGS" "${SETTINGS}.bak.$(date +%s)"
        jq --argjson cfg "$(echo "$HOOKS_CONFIG" | jq '.hooks')" '
            .hooks as $existing
            | .hooks = (
                reduce ($cfg | to_entries[]) as $event ($existing;
                    .[$event.key] = (
                        (.[$event.key] // []) as $cur
                        | reduce ($event.value[]) as $new_handler ($cur;
                            (map(.matcher == $new_handler.matcher) | index(true)) as $idx
                            | if $idx == null then
                                . + [$new_handler]
                              else
                                .[$idx].hooks = (
                                    (.[$idx].hooks // []) +
                                    (($new_handler.hooks // []) | map(
                                        . as $nh
                                        | select(([$nh.command] | inside([
                                            ($cur[$idx].hooks // []) | .[].command
                                          ])) | not)
                                    ))
                                )
                              end
                          )
                    )
                )
            )
        ' "$SETTINGS" > "${SETTINGS}.tmp" && mv "${SETTINGS}.tmp" "$SETTINGS"
        info "Хуки синхронизированы с $SETTINGS (merge, backup создан)"
    elif [ -f "$SETTINGS" ]; then
        jq --argjson hooks "$(echo "$HOOKS_CONFIG" | jq '.hooks')" '. + {hooks: $hooks}' "$SETTINGS" > "${SETTINGS}.tmp" && mv "${SETTINGS}.tmp" "$SETTINGS"
        info "Хуки добавлены в $SETTINGS"
    else
        echo "$HOOKS_CONFIG" | jq '.' > "$SETTINGS"
        info "Создан $SETTINGS с хуками"
    fi
else
    warn "jq не установлен — хуки скопированы, но конфигурация требует ручной настройки"
    warn "Установить jq: brew install jq"
    warn "Затем добавьте в $SETTINGS секцию 'hooks' (см. документацию ClaudSoul)"
fi

# --- 7. MCP-сервер ---

info "Устанавливаю MCP-сервер..."

MCP_SERVER_DIR="$CLAUDSOUL_DIR/mcp-server"

if [ -d "$MCP_SERVER_DIR" ]; then
    # Проверяем наличие uv
    if command -v uv &>/dev/null; then
        # Устанавливаем зависимости
        (cd "$MCP_SERVER_DIR" && uv sync --quiet 2>/dev/null) && \
            info "Зависимости MCP-сервера установлены" || \
            warn "Не удалось установить зависимости MCP-сервера (uv sync)"

        # Регистрируем MCP-сервер в Claude Code
        if command -v claude &>/dev/null; then
            # Проверяем, не зарегистрирован ли уже
            if claude mcp list 2>/dev/null | grep -q "claudsoul"; then
                warn "MCP-сервер claudsoul уже зарегистрирован — пропускаю"
            else
                claude mcp add claudsoul -s user -- uv --directory "$MCP_SERVER_DIR" run python3 server.py 2>/dev/null && \
                    info "MCP-сервер зарегистрирован: claudsoul (user scope)" || \
                    warn "Не удалось зарегистрировать MCP-сервер — зарегистрируйте вручную:"
                warn "  claude mcp add claudsoul -s user -- uv --directory $MCP_SERVER_DIR run python3 server.py"
            fi
        else
            warn "Claude Code CLI не найден — зарегистрируйте MCP-сервер вручную после установки:"
            warn "  claude mcp add claudsoul -s user -- uv --directory $MCP_SERVER_DIR run python3 server.py"
        fi
    else
        warn "uv не установлен — MCP-сервер требует uv для работы"
        warn "Установить: curl -LsSf https://astral.sh/uv/install.sh | sh"
        warn "Затем запустите install.sh повторно"
    fi
else
    warn "Директория mcp-server/ не найдена — MCP-сервер не установлен"
fi

# --- 8. Session Registry ---

info "Настраиваю Session Registry..."

SESSIONS_DIR="$CLAUDE_HOME/sessions"
SESSIONS_ACTIVE="$SESSIONS_DIR/active"
mkdir -p "$SESSIONS_ACTIVE"
info "Директория сессий: $SESSIONS_DIR"

# --- 8. launchd агенты (автосканер + periodic digests) ---

# launchd — только macOS. На других платформах явно сообщаем эквивалент через
# cron/systemd, а не даём launchctl молча падать в три warn'а.
if [ "$(uname -s)" = "Darwin" ]; then
    info "Устанавливаю launchd агентов..."

    install_launchd_agent() {
        local label="$1" desc="$2"
        local src="$CLAUDSOUL_DIR/launchd/${label}.plist"
        local tgt="$HOME/Library/LaunchAgents/${label}.plist"

        if [ ! -f "$src" ]; then
            warn "Файл $src не найден — пропускаю $label"
            return 1
        fi

        launchctl bootout "gui/$(id -u)/${label}" 2>/dev/null || true
        mkdir -p "$HOME/Library/LaunchAgents"
        sed "s|__HOME__|$HOME|g" "$src" > "$tgt"

        launchctl bootstrap "gui/$(id -u)" "$tgt" 2>/dev/null || \
            launchctl load "$tgt" 2>/dev/null || \
            warn "Не удалось загрузить $label — загрузите вручную: launchctl load $tgt"

        info "$label установлен: $desc"
    }

    install_launchd_agent com.claudsoul.scanner        "каждые 4 часа, read-only сканирование"
    install_launchd_agent com.claudsoul.knowledge-audit "еженедельно (вс 03:15), mechanical digest /knowledge-audit"
    install_launchd_agent com.claudsoul.bridge-health   "ежемесячно (1-е 03:30), mechanical digest /bridge-health"
else
    warn "Платформа $(uname -s) — launchd недоступен (только macOS). Периодические агенты НЕ установлены."
    warn "Для эквивалента настройте cron / systemd-timer (все read-only, безопасны):"
    warn "  каждые 4ч:  bash ~/.claude/hooks/auto-scanner.sh"
    warn "  вс 03:15:    bash ~/.claude/hooks/knowledge-audit-digest.sh"
    warn "  1-е 03:30:   bash ~/.claude/hooks/bridge-health-digest.sh"
fi

# --- 9. Шаблоны ---

info "Устанавливаю шаблоны..."

TEMPLATES_TARGET="$CLAUDE_HOME/templates"
mkdir -p "$TEMPLATES_TARGET"

TEMPLATES_COUNT=0
for tmpl in "$CLAUDSOUL_DIR"/templates/*.tmpl; do
    [ -f "$tmpl" ] || continue
    cp "$tmpl" "$TEMPLATES_TARGET/$(basename "$tmpl")"
    TEMPLATES_COUNT=$((TEMPLATES_COUNT + 1))
done
info "Установлено шаблонов: $TEMPLATES_COUNT"

# --- Итог ---

echo ""
echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${GREEN}  ClaudSoul установлен${NC}"
echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""
echo "  Правила:   $GLOBAL_CLAUDE_MD"
echo "  Знания:    $GLOBAL_LESSONS/ ($KNOWLEDGE_COUNT файлов)"
echo "  Скиллы:    $SKILLS_DIR/ ($SKILLS_COUNT скиллов)"
echo "  Хуки:      $HOOKS_TARGET/ ($HOOKS_COUNT скриптов)"
echo "  Сессии:    $SESSIONS_DIR/"
echo "  Шаблоны:   $TEMPLATES_TARGET/ ($TEMPLATES_COUNT файлов)"
echo "  MCP:       claudsoul (9 tools: search, reindex, stats, get, graph, dashboard, export, import)"
echo ""
echo "  Доступные скиллы ($SKILLS_COUNT штук):"
echo "    /ingest          — добавить документ/URL/картинку в базу знаний"
echo "    /entity          — посмотреть, что база знает о сущности"
echo "    /learn           — быстрая запись знания (auto-detect тип)"
echo "    /retro           — ретроспектива (ошибки, успехи, коммуникация)"
echo "    /knowledge-audit — аудит здоровья базы знаний"
echo "    /save            — сохранение прогресса сессии"
echo "    Полный список:     README.md → раздел «Скиллы»"
echo ""
echo "  Активные хуки:"
echo "    error-tracker      — 2+ упавших команды подряд: «стой» перед следующей попыткой"
echo "    ci-check-reminder  — после git push: проверять прогон СВОЕГО коммита"
echo "    knowledge-activator — инжект знаний + Пункт 0 при первом действии"
echo "    session-collector   — напоминание перед завершением сессии"
echo "    auto-scanner        — read-only сканирование проектов (каждые 4ч, launchd)"
echo ""
echo "  Начните новую сессию Claude Code — правила и хуки подхватятся автоматически."
echo ""

# v1.7.5: smoke test после установки. Не блокирует завершение, exit code
# отдельный — в случае проблем пользователь сам решает что делать.
SMOKE_TEST="$CLAUDSOUL_DIR/scripts/smoke-test.sh"
if [ -x "$SMOKE_TEST" ]; then
    info "Запускаю smoke test..."
    CLAUDSOUL_DIR="$CLAUDSOUL_DIR" bash "$SMOKE_TEST" || true
fi
