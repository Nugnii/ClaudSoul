#!/usr/bin/env bash
set -u
# СУДИТ: scripts/project-conformance.sh
# probe_D1263 — сверка проекта называет выключенную уборку бэклога: бэклог договора с закрытым пунктом, признака согласия
#   `CG_LOCAL_BACKLOG` нет — справка с числом закрытых и готовой строкой включения; с признаком в `.claude/settings.json`
#   проекта — молчит; закрытые не в форме договора — «сперва дописать строки»; битый файл настроек — «признак не проверен», а не «выключена»; без закрытых пунктов —
#   молчит (убирать нечего).
# Код: 0 — так; 1 — нет (названо); 2 — рамка не собралась.
R="${CLAUDSOUL_REPO:-$(cd "$(dirname "$0")/../../.." && pwd)}"
C="$R/scripts/project-conformance.sh"
[ -f "$C" ] && command -v python3 >/dev/null 2>&1 || exit 2
T=$(mktemp -d) || exit 2
trap 'rm -rf "$T"' EXIT
P="$T/proj"; mkdir -p "$P/.claude" "$T/home/.claude" || exit 2
printf '%s\n' '# Backlog' '' '- ☑ **B1** закрытый пункт' '  **Результат.** сделано' '  **Проверка.** `true` → 0' '' \
    '- ☐ **B2** открытый пункт' '  **Проверка.** `false` → 0' > "$P/BACKLOG.md"
run() { (cd "$T" && env -u CG_LOCAL_BACKLOG HOME="$T/home" CLAUDSOUL_ROOT="$R" bash "$C" "$P" 2>&1); }
out=$(run)
case "$out" in *"открытых пунктов: 1"*) ;; *) echo "рамка: сверка не увидела пунктов бэклога песочницы" >&2; exit 2 ;; esac
case "$out" in *CG_LOCAL_BACKLOG*"$P"*) ;; *) echo "закрытый пункт без признака — уборка не названа строкой включения"; exit 1 ;; esac
case "$out" in *"уехали бы 1 из 1"*"гейт"*) ;; *) echo "справка не назвала, что уедет, либо согласие без гейта (скептик M1, M3)"; exit 1 ;; esac
# (в) сверка из вложенного прогона («Проверка» под гейтом) — справка та же: маркер вложенности не глушит архиватор.
case "$(cd "$T" && env -u CG_LOCAL_BACKLOG BACKLOG_CHECKS_NESTED=1 HOME="$T/home" CLAUDSOUL_ROOT="$R" bash "$C" "$P" 2>&1)" in
    *"уехали бы 1 из 1"*) ;; *) echo "во вложенном прогоне справка пропала"; exit 1 ;; esac
# (ф) закрытый пункт не в форме договора (нет «Результата») — включать без пользы: справка зовёт дописать строки (M1).
cp "$P/BACKLOG.md" "$T/bl.keep"
printf '%s\n' '# Backlog' '' '- ☑ **B1** закрытый пункт' '  **Проверка.** `true` → 0' > "$P/BACKLOG.md"
case "$(run)" in *"не унесла бы ни одного"*) ;; *) echo "пункт не в форме — справка всё равно советует включить"; exit 1 ;; esac
cp "$T/bl.keep" "$P/BACKLOG.md"
printf '{"env":{"CG_LOCAL_BACKLOG":"%s"}}\n' "$(cd "$P" && pwd -P)/BACKLOG.md" > "$P/.claude/settings.json"
case "$(run)" in *CG_LOCAL_BACKLOG*) echo "с признаком в настройках проекта уборка всё ещё названа выключенной"; exit 1 ;; esac
printf '{"env":\n' > "$P/.claude/settings.json"   # битый JSON: «не смог прочитать», а не «признака нет» (род B)
case "$(run)" in *"выключена"*) echo "нечитаемые настройки названы выключенной уборкой"; exit 1 ;; *"не прочитан"*) ;;
    *) echo "нечитаемые настройки не названы"; exit 1 ;; esac
: > "$P/.claude/settings.json"; printf '%s\n' '# Backlog' '' '- ☐ **B2** открытый пункт' '  **Проверка.** `false` → 0' > "$P/BACKLOG.md"
case "$(run)" in *CG_LOCAL_BACKLOG*) echo "закрытых нет — убирать нечего, а уборка названа выключенной"; exit 1 ;; esac
echo "выключенная уборка названа числом и строкой включения; с признаком и без закрытых — молчит"
exit 0
