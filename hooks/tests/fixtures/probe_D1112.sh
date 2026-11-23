#!/usr/bin/env bash
# СУДИТ: hooks/lib/write-target-lib.sh scripts/deny-target-precision.py hooks/root-cause-lib.sh
# probe_D1112 — «путь временный» отвечает ВЕРНО и одинаково на все написания одного места. Судится ответ, а не текст:
#   · страж записи (`_wt_outside`) — `/var/folders/…` и `/private/var/folders/…` внешние; проект во временном каталоге,
#     набранный в другом написании, регистре (ASCII и кириллица — где ФС к нему не чувствительна) или форме
#     нормализации, — внутри (скептики D1112, круги 1–3: H1, M1, M1); ссылка на файл проекта из временного каталога —
#     не внешняя (скептик четвёртого круга, H1); путь длиннее 1024 символов — не место (пятого, M1);
#   · замер точности (`classify` в deny-target-precision.py) — перенаправление в оба написания есть «песочница»; одно
#     место установки с `-…-scratchpad/` в пути — один класс через heredoc в `~/…` и через Write (пятого, M2);
#   · признак частного пути (`rc_path_is_private`) — `/var/tmp` частный, системный путь — нет.
# Проект — НАСТОЯЩИЙ каталог под mktemp (у несуществующего подменять собой нечего). Красная (1), пока хоть один ответ
# неверен. Контроль рамки: путь проекта временным не считается и перенаправление в него — «механизм». Рамка — 2.
R="${CLAUDSOUL_REPO:-$(cd "$(dirname "$0")/../../.." && pwd)}"
WT="$R/hooks/lib/write-target-lib.sh"; DP="$R/scripts/deny-target-precision.py"; RC="$R/hooks/root-cause-lib.sh"
[ -f "$WT" ] && [ -f "$DP" ] && [ -f "$RC" ] || exit 2
command -v python3 >/dev/null 2>&1 || exit 2
T=$(mktemp -d) || exit 2
trap 'rm -rf "$T"' EXIT
A="/var/folders/ab/cd/T/probe.txt"; B="/private/var/folders/ab/cd/T/probe.txt"; P="/Users/u/project/hooks/x.sh"
wt() { bash -c '. "$1" 2>/dev/null; _wt_outside "$2" "${3:-/Users/u/project}"' _ "$WT" "$@"; }
wt "$P" && exit 2
wt "$A" || { echo "write-target-lib: /var/folders не внешний" >&2; exit 1; }
wt "$B" || { echo "write-target-lib: /private/var/folders не внешний" >&2; exit 1; }
LAT="proj"; CYR="Проект"; CYRU="ПРОЕКТ"
mkdir -p "$T/${LAT}/hooks" "$T/${CYR}/hooks" || exit 2
Pc=$(cd -P "$T/${LAT}" && { /bin/pwd -P 2>/dev/null || pwd -P; })
case "$Pc" in /private/*) Pa="${Pc#/private}" ;; *) Pa="$Pc" ;; esac
wt "${Pa}/hooks/x.sh" "$Pc" && { echo "write-target-lib: цель в проекте в другом написании — внешняя" >&2; exit 1; }
wt "${Pc}/hooks/x.sh" "$Pa" && { echo "write-target-lib: проект в другом написании — цель внешняя" >&2; exit 1; }
wt "${T}/other/x.md" "$Pc" || { echo "write-target-lib: временный путь вне проекта не внешний" >&2; exit 1; }
echo x > "$T/${LAT}/hooks/f.sh" && ln -s "$T/${LAT}/hooks/f.sh" "$T/flink" || exit 2
wt "${T}/flink" "$Pc" && { echo "write-target-lib: ссылка на файл проекта из временного каталога — внешняя" >&2; exit 1; }
L=$(printf 'a%.0s' $(seq 1100))
wt "${T}/${L}" "$Pc" && { echo "write-target-lib: путь длиннее 1024 символов — внешний" >&2; exit 1; }
if [ -d "$T/PROJ" ]; then
    wt "${T}/PROJ/hooks/x.sh" "${T}/${LAT}" && { echo "write-target-lib: проект в другом регистре — цель внешняя" >&2; exit 1; }
    wt "${T}/${CYRU}/hooks/x.sh" "${T}/${CYR}" && { echo "write-target-lib: другой регистр кириллицы — цель внешняя" >&2; exit 1; }
fi
nfd=$(python3 -c "import unicodedata;print(unicodedata.normalize('NFD','Тайник'),end='')")
nfc=$(python3 -c "import unicodedata;print(unicodedata.normalize('NFC','Тайник'),end='')")
mkdir -p "${T}/${nfd}/hooks" || exit 2
if [ -d "${T}/${nfc}/hooks" ]; then
    wt "${T}/${nfc}/hooks/x.sh" "${T}/${nfd}" && { echo "write-target-lib: проект в NFD, цель в NFC — внешняя" >&2; exit 1; }
fi
rc() { bash -c '. "$1" 2>/dev/null; rc_path_is_private "$2"' _ "$RC" "$1"; }
rc /usr/bin/env && exit 2
rc /var/tmp/probe.txt || { echo "root-cause-lib: /var/tmp не частный" >&2; exit 1; }
dp=$(python3 - "$DP" "$A" "$B" "$P" <<'PY'
import importlib.util, sys
spec = importlib.util.spec_from_file_location("dtp", sys.argv[1])
m = importlib.util.module_from_spec(spec)
spec.loader.exec_module(m)
import os
w = "/.claude/projects/-probe-scratchpad/memory/MEMORY.md"
print("|".join(m.classify([("t", "Bash", {"command": "echo x > " + p}) for p in sys.argv[2:5]]
                          + [("t", "Bash", {"command": "cat >> ~" + w + " <<'EOF'\nx\nEOF"}),
                             ("t", "Write", {"file_path": os.path.expanduser("~") + w})])))
PY
) || exit 2
IFS='|' read -r ca cb cp ch cw <<EOF
$dp
EOF
[ "$cp" = "механизм" ] || exit 2
[ "$ca" = "песочница" ] && [ "$cb" = "песочница" ] \
    || { echo "deny-target-precision: /var/folders → ${ca}, /private/var/folders → ${cb} (ждём «песочница»)" >&2; exit 1; }
[ "$ch" = "$cw" ] && [ "$cw" != "песочница" ] \
    || { echo "deny-target-precision: одно место установки — heredoc ${ch}, Write ${cw}" >&2; exit 1; }
echo "временные корни: все написания места отвечают верно и одинаково"
exit 0
