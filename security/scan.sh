#!/usr/bin/env bash
# scan.sh — единая обёртка над тремя сканерами: gitleaks (секреты), opengrep (SAST), trivy (SCA).
#
# Результат: одна команда даёт находки всех трёх слоёв, ЛОКАЛЬНО и БЕЗ СЕТИ.
# Проверка результата: bash security/test_scan.sh даёт 0
#
# У прибора ТРИ состояния, не два (правило «Хук зовёт инструмент»):
#   нет инструмента  → сказать один раз и продолжить остальными (это другая установка)
#   инструмент сломался (exit≥2, либо exit≠0 при пустом выводе) → СКАЗАТЬ: молчание тут
#                       читается как «чисто», а это ложно-зелёное
#   отработал, находок нет → тихо
# Повод: 9 сентября 2026 opengrep на полном наборе правил вернул «0 находок» с exit=7 —
# один битый yaml (stats/web_frameworks.yml) обрушил 2074 остальных. Вывод был
# неотличим от чистого прогона. Отсюда же правило ниже: exit сканера снимается ДО
# конвейера, иначе меряется exit последней команды в трубе, а не сканера.
#
# Переносимость: только POSIX + BSD-совместимые вызовы. Ни timeout, ни realpath,
# ни sha256sum — их нет в macOS по умолчанию (pattern-shell-portability).
#
# Usage: scan.sh [--fast|--full] [PATH]
#   --fast  секреты + SAST по языкам изменённых файлов (для commit-хука, ~5-20с)
#   --full  всё, включая SCA и полный набор правил (для скилла и CI, ~2-5мин)
set -uo pipefail

RULES="$HOME/.claude/security/rules"
MODE="--fast"
TARGET="."
for a in "$@"; do
  case "$a" in
    --fast|--full) MODE="$a" ;;
    *) TARGET="$a" ;;
  esac
done
[ -d "$TARGET" ] || { echo "scan.sh: нет такого пути: $TARGET" >&2; exit 2; }

FOUND=0      # число находок
BROKEN=""    # имена сломавшихся приборов — они отдельный класс от «чисто»
RAN=0        # сколько слоёв РЕАЛЬНО отработало: ноль слоёв ≠ «чисто»

say()  { printf '%s\n' "$*"; }
warn() { printf '%s\n' "$*" >&2; }

# --- слой 1: секреты (gitleaks) ---------------------------------------------
if command -v gitleaks >/dev/null 2>&1; then
  OUT=$(mktemp); ERR=$(mktemp)
  gitleaks dir "$TARGET" --no-banner --redact --report-format json --report-path "$OUT" >/dev/null 2>"$ERR"
  RC=$?                                   # exit ИМЕННО gitleaks, до всякой трубы
  if [ "$RC" -ge 2 ]; then
    BROKEN="$BROKEN gitleaks(exit=$RC)"
    warn "gitleaks сломался: $(head -3 "$ERR")"
  else
    N=$(python3 -c 'import json,sys
try:
    d=json.load(open(sys.argv[1]))
    print(len(d) if isinstance(d,list) else 0)
except Exception:
    print(-1)' "$OUT" 2>/dev/null || echo -1)
    if [ "$N" = "-1" ]; then
      BROKEN="$BROKEN gitleaks(нечитаемый отчёт)"
    else
      RAN=$((RAN + 1))
    fi
    if [ "$N" != "-1" ] && [ "$N" -gt 0 ]; then
      say "🔑 СЕКРЕТЫ: $N"
      python3 -c 'import json,sys
for f in json.load(open(sys.argv[1]))[:20]:
    print("   %s:%s  %s" % (f.get("File"), f.get("StartLine"), f.get("RuleID")))' "$OUT" 2>/dev/null
      FOUND=$((FOUND + N))
    fi
  fi
  rm -f "$OUT" "$ERR"
else
  warn "· gitleaks не установлен — слой секретов пропущен"
fi

# --- слой 2: SAST (opengrep) ------------------------------------------------
if command -v opengrep >/dev/null 2>&1 && [ -d "$RULES" ]; then
  if [ "$MODE" = "--full" ]; then
    CFG="$RULES"
  else
    # только языки, которые реально есть в цели — иначе платим за 2075 правил впустую
    CFG=""
    for lang in python javascript typescript go java ruby php bash generic; do
      [ -d "$RULES/$lang" ] || continue
      case "$lang" in
        python)     pat='*.py'  ;; javascript) pat='*.js' ;; typescript) pat='*.ts' ;;
        go)         pat='*.go'  ;; java)       pat='*.java' ;; ruby)     pat='*.rb' ;;
        php)        pat='*.php' ;; bash)       pat='*.sh' ;; generic)    pat='*'    ;;
      esac
      [ "$lang" = generic ] && continue
      if [ -n "$(find "$TARGET" -name "$pat" ! -path '*/.git/*' ! -path '*/node_modules/*' -print -quit 2>/dev/null)" ]; then
        CFG="$CFG --config $RULES/$lang"
      fi
    done
  fi
  if [ -n "$CFG" ]; then
    OUT=$(mktemp); ERR=$(mktemp)
    # shellcheck disable=SC2086
    # Только ERROR и WARNING. Замер на ClaudSoul: полный прогон дал 1331 находку,
    # из которых подавляющее большинство — INFO-правило detect-generic-ai-anthprop
    # на .md-документации. Отчёт из 1331 пункта не разбирают, его пролистывают, и
    # инструмент становится фоном. INFO вернуть флагом --info, когда он понадобится.
    SEV="--severity=ERROR --severity=WARNING"
    [ "${WITH_INFO:-0}" = "1" ] && SEV=""
    # shellcheck disable=SC2086
    opengrep scan $( [ "$MODE" = "--full" ] && printf -- '--config %s' "$CFG" || printf '%s' "$CFG" ) \
      --quiet --json $SEV \
      --exclude='*.json' --exclude='*.md' --exclude=node_modules --exclude=.git \
      "$TARGET" > "$OUT" 2>"$ERR"
    RC=$?
    if [ "$RC" -ne 0 ]; then
      BROKEN="$BROKEN opengrep(exit=$RC)"
      warn "opengrep сломался (exit=$RC): $(python3 -c 'import json,sys
try:
    for e in json.load(open(sys.argv[1])).get("errors",[])[:2]:
        sp=(e.get("spans") or [{}])[0].get("file","?")
        print("%s — %s" % (sp, e.get("long_msg") or e.get("message")))
except Exception: pass' "$OUT" 2>/dev/null || head -2 "$ERR")"
    else
      N=$(python3 -c 'import json,sys
try: print(len(json.load(open(sys.argv[1]))["results"]))
except Exception: print(-1)' "$OUT" 2>/dev/null || echo -1)
      if [ "$N" = "-1" ]; then
        BROKEN="$BROKEN opengrep(нечитаемый отчёт)"
      else
        RAN=$((RAN + 1))
      fi
      if [ "$N" != "-1" ] && [ "$N" -gt 0 ]; then
        say "🐛 КОД (SAST): $N"
        python3 -c 'import json,sys
for r in json.load(open(sys.argv[1]))["results"][:20]:
    print("   %s:%s  [%s] %s" % (r["path"], r["start"]["line"],
          r["extra"].get("severity","?"), r["check_id"].split(".")[-1]))' "$OUT" 2>/dev/null
        FOUND=$((FOUND + N))
      fi
    fi
    rm -f "$OUT" "$ERR"
  fi
elif ! command -v opengrep >/dev/null 2>&1; then
  warn "· opengrep не установлен — слой SAST пропущен"
else
  warn "· набор правил отсутствует ($RULES) — слой SAST пропущен"
fi

# --- слой 3: зависимости (trivy) — только в --full, он самый медленный -------
if [ "$MODE" = "--full" ]; then
  if command -v trivy >/dev/null 2>&1; then
    OUT=$(mktemp); ERR=$(mktemp)
    trivy fs --scanners vuln,misconfig --skip-db-update --skip-check-update \
      --severity HIGH,CRITICAL --quiet --format json "$TARGET" > "$OUT" 2>"$ERR"
    RC=$?
    if [ "$RC" -ne 0 ]; then
      BROKEN="$BROKEN trivy(exit=$RC)"
      warn "trivy сломался (exit=$RC): $(head -3 "$ERR")"
    else
      N=$(python3 -c 'import json,sys
try:
    d=json.load(open(sys.argv[1])); t=0
    for r in (d.get("Results") or []):
        t += len(r.get("Vulnerabilities") or []) + len(r.get("Misconfigurations") or [])
    print(t)
except Exception: print(-1)' "$OUT" 2>/dev/null || echo -1)
      if [ "$N" = "-1" ]; then
        BROKEN="$BROKEN trivy(нечитаемый отчёт)"
      else
        RAN=$((RAN + 1))
      fi
      if [ "$N" != "-1" ] && [ "$N" -gt 0 ]; then
        say "📦 ЗАВИСИМОСТИ: $N (HIGH/CRITICAL)"
        python3 -c 'import json,sys
d=json.load(open(sys.argv[1])); n=0
for r in (d.get("Results") or []):
    for v in (r.get("Vulnerabilities") or []):
        if n>=15: break
        print("   %s  %s %s → %s  [%s]" % (r.get("Target"), v.get("PkgName"),
              v.get("InstalledVersion"), v.get("FixedVersion") or "нет фикса", v.get("Severity")))
        n+=1' "$OUT" 2>/dev/null
        FOUND=$((FOUND + N))
      fi
    fi
    rm -f "$OUT" "$ERR"
  else
    warn "· trivy не установлен — слой зависимостей пропущен"
  fi
fi

# --- исход: сломанный прибор НЕ равен чистому прогону -----------------------
if [ -n "$BROKEN" ]; then
  warn ""
  warn "⚠️  Приборы сломались:$BROKEN"
  warn "    Это НЕ «чисто» — эти слои не проверены."
  exit 2
fi
# Ноль отработавших слоёв — это НЕ чистый прогон, а отсутствие проверки.
# Дефект найден в этом же файле собственным тестом 4 при постройке: без единого
# сканера в PATH скрипт печатал «✓ чисто» с exit=0. Ровно тот класс, ради которого
# инструмент и строился (pattern-new-instrument-carries-its-own-defect).
if [ "$RAN" -eq 0 ]; then
  warn "⚠️  Ни один сканер не отработал — проверки НЕ БЫЛО."
  warn "    Проверь: command -v gitleaks opengrep trivy"
  exit 2
fi
[ "$FOUND" -eq 0 ] && say "✓ чисто ($MODE, слоёв отработало: $RAN)"
exit 0
