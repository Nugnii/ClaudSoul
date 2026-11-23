#!/usr/bin/env bash
# СУДИТ: scripts/defect-class-carriers.py
# probe_D1170 — реестр родов не отвечает кодом вердикта, не измерив: падение прибора (дерево без `install.sh`) — код 2
# со строкой «НЕ ИЗМЕРЕНО», а не 1 «носители есть»; чужой `GIT_DIR` с общим путём — не «0» кодом 0; путь не в UTF-8 в
# индексе не роняет прибор; код `--genus X` каждого рода согласован с числом его носителей. Второй круг (скептик D1170):
# унаследованные `GIT_INDEX_FILE`, `GIT_WORK_TREE`, `GIT_*PATHSPECS` не меняют ответ на живом дереве и не отравляют кэш
# (M1, M4); путь с суррогатом в ключе кэша, в выводе и в записи кэша не роняет прибор (M3); `-z` отдаёт имя с
# кириллицей и кавычкой настоящим путём, отказ git на втором вызове `tracked()` (из `_input_key()`) — «не измерено» (L4).
# Красная (1), пока хоть одна нога судит иначе; 2 — рамка не собралась.
R="${CLAUDSOUL_REPO:-$(cd "$(dirname "$0")/../../.." && pwd)}"
TOOL="$R/scripts/defect-class-carriers.py"
[ -f "$TOOL" ] && [ -f "$R/install.sh" ] || exit 2
command -v python3 >/dev/null 2>&1 && command -v git >/dev/null 2>&1 || exit 2
T=$(mktemp -d) || exit 2
trap 'rm -rf "$T"' EXIT
export STATE_DIR="$T/state"
mkdir -p "$T/state" || exit 2
bad=0
# 1. Git-репозиторий без install.sh: прибор падает — «не измерено» кодом 2.
A="$T/a"; mkdir -p "$A/scripts" && cp "$TOOL" "$A/scripts/" && printf 'x\n' > "$A/README.md" || exit 2
git -C "$A" init -q && git -C "$A" add -A || exit 2
out=$(DCC_NO_CACHE=1 python3 "$A/scripts/defect-class-carriers.py" 2>/dev/null); rc=$?
case "$rc:$out" in "2:НЕ ИЗМЕРЕНО"*) ;; *) echo "падение прибора — код $rc: ${out%%$'\n'*}"; bad=1 ;; esac
# 2. Чужой GIT_DIR с общим путём: снимок вне репозитория, индекс чужого репозитория знает README.md.
X="$T/x"; mkdir -p "$X" && printf 'x\n' > "$X/README.md" && git -C "$X" init -q && git -C "$X" add -A || exit 2
S="$T/snap"; mkdir -p "$S/scripts" && cp "$TOOL" "$S/scripts/" && cp "$R/install.sh" "$S/" && printf 'x\n' > "$S/README.md" || exit 2
git -C "$S" rev-parse --git-dir >/dev/null 2>&1 && exit 2   # рамка: снимок оказался внутри репозитория
(cd "$S" && GIT_DIR="$X/.git" DCC_NO_CACHE=1 python3 "$S/scripts/defect-class-carriers.py" >/dev/null 2>&1); rc=$?
[ "$rc" = 2 ] || { echo "чужой GIT_DIR — код $rc, а не «не измерено»"; bad=1; }
# 3. Путь не в UTF-8 в индексе: прибор мерит (0 или 1), без Traceback.
B="$T/b"; mkdir -p "$B/scripts" && cp "$TOOL" "$B/scripts/" && cp "$R/install.sh" "$B/" || exit 2
printf 'x\n' > "$B/кир ил'ица.txt" || exit 2
# Имя не в UTF-8 файловая система macOS не создаёт — оно кладётся прямо в индекс: прибор читает индекс, а не диск.
git -C "$B" init -q && git -C "$B" add -A || exit 2
blob=$(printf 'x\n' | git -C "$B" hash-object -w --stdin) || exit 2
git -C "$B" update-index --add --cacheinfo "100644,$blob,bad"$'\xff'".txt" || exit 2
err=$(DCC_NO_CACHE=1 python3 "$B/scripts/defect-class-carriers.py" 2>&1 >/dev/null); rc=$?
case "$rc" in 0|1) ;; *) echo "путь не в UTF-8 — код $rc"; bad=1 ;; esac
case "$err" in *Traceback*) echo "путь не в UTF-8 — Traceback"; bad=1 ;; esac
# 4. Подмены внутри прибора (M3, L4): модуль грузится из копии в B, функции подменяются, вердикт — по коду main().
cat > "$T/inner.py" <<'PY'
import importlib.util, io, os, sys
from pathlib import Path
tool, mode = sys.argv[1], sys.argv[2]
spec = importlib.util.spec_from_file_location("dcc", tool)
m = importlib.util.module_from_spec(spec); spec.loader.exec_module(m)
real = m.tracked
class Sur:                       # путь с суррогатом, существующий для stat (на Linux так выглядит имя не в UTF-8)
    def __init__(self, p): self.p = p
    def stat(self): return os.stat(tool)
    def exists(self): return True
    def __str__(self): return str(self.p) + "/bad\udcff.txt"
    def __fspath__(self): return str(self)
if mode == "surrogate":
    # Поддельный путь — только ключу кэша: роды читают файлы и спотыкались бы о подделку, а не о суррогат.
    m.tracked = lambda *g: real(*g) + ([Sur(m.ROOT)] if not g and sys._getframe(1).f_code.co_name == "_input_key" else [])
    m.carriers_a = lambda: [(m.ROOT / "bad\udcff.sh", 1, 0)]
    sys.exit(m.main())
if mode == "z":
    names = [p.name for p in real()]
    sys.exit(0 if "кир ил'ица.txt" in names else 1)
if mode == "second":
    calls = []
    def flaky(*g):
        calls.append(g)
        if len(calls) == 2:
            m._GIT_FAILED.append("подменённый отказ второго вызова")
            return []
        return real(*g)
    m.tracked = flaky
    sys.exit(m.main())
PY
# Вывод — в строгом режиме кодировки, как у терминала под ru_RU/en_US (под C.UTF-8 Python сам берёт surrogateescape).
out=$(DCC_NO_CACHE=1 PYTHONIOENCODING=utf-8:strict python3 "$T/inner.py" "$B/scripts/defect-class-carriers.py" surrogate 2>&1); rc=$?
case "$rc:$out" in 0:*Traceback*|1:*Traceback*|[!01]:*) echo "суррогат в ключе, выводе или кэше — код $rc: $(printf '%s' "$out" | tail -1)"; bad=1 ;; esac
python3 "$T/inner.py" "$B/scripts/defect-class-carriers.py" z >/dev/null 2>&1 \
    || { echo "-z: имя с кириллицей и кавычкой не дошло настоящим путём"; bad=1; }
out=$(DCC_NO_CACHE=1 python3 "$T/inner.py" "$B/scripts/defect-class-carriers.py" second 2>/dev/null); rc=$?
case "$rc:$out" in "2:НЕ ИЗМЕРЕНО"*) ;; *) echo "отказ git на втором вызове — код $rc"; bad=1 ;; esac
# 5. Живое дерево: код каждого рода согласован с числом его носителей (L3), а унаследованные переменные git ответа
#    не меняют и кэш не отравляют (M1, M4). Кэш — во временном STATE_DIR: первый прогон его кладёт.
full=$(cd "$R" && python3 "$TOOL" 2>/dev/null); frc=$?
sum=$(printf '%s\n' "$full" | sed -n 's/^Прожарено механизмов: [0-9]*\. Носителей //p')
[ -n "$sum" ] || { echo "сводка носителей в выводе не найдена"; exit 1; }
for pair in $(printf '%s' "$sum" | tr -d ' .' | tr ',' '\n'); do
    g=${pair%%:*}; n=${pair#*:}
    (cd "$R" && python3 "$TOOL" --genus "$g" >/dev/null 2>&1); rc=$?
    want=0; [ "$n" -gt 0 ] && want=1
    [ "$rc" = "$want" ] || { echo "род $g: носителей $n, а --genus $g — код $rc"; bad=1; }
done
# Подменённый прогон считает без чтения кэша (иначе он попал бы в кэш чистого и совпал бы даром) и пишет кэш в своё
# пустое хранилище; чистый прогон из того же хранилища обязан ответить так же — кэш не отравлен.
i=0
for v in "GIT_INDEX_FILE=$X/.git/index" "GIT_WORK_TREE=$X" GIT_LITERAL_PATHSPECS=1 GIT_GLOB_PATHSPECS=1 GIT_NOGLOB_PATHSPECS=1; do
    i=$((i + 1)); mkdir -p "$T/st$i" || exit 2
    o=$(cd "$R" && STATE_DIR="$T/st$i" DCC_NO_CACHE=1 env "$v" python3 "$TOOL" 2>/dev/null); rc=$?
    [ "$rc" = "$frc" ] && [ "${o%%$'\n'*}" = "${full%%$'\n'*}" ] || { echo "${v%%=*}: код $rc вместо $frc"; bad=1; }
    (cd "$R" && STATE_DIR="$T/st$i" python3 "$TOOL" >/dev/null 2>&1); rc=$?
    [ "$rc" = "$frc" ] || { echo "${v%%=*}: чистый прогон после подменённого — код $rc вместо $frc, кэш отравлен"; bad=1; }
done
exit "$bad"
