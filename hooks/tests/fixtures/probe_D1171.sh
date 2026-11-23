#!/usr/bin/env bash
# СУДИТ: дерево
# (предмет словами: дерево hooks/ scripts/ lib/ bin/ install.sh uninstall.sh; в строке СУДИТ — только пути, иначе прибор свидетелей-атак читает слова путями — D1222)
# probe_D1171 — сравнение строк в awk (==, !=, <, >, <=, >=), у которого операнд — литерал с не-ASCII знаком либо
# переменная -v, несущая метку или не-ASCII, идёт под LC_ALL=C. /usr/bin/awk macOS в UTF-8-локали, отличной от C,
# сравнивает по правилам сортировки: «☐»=«◐», «x☐»=«x», «—»=«–» (замер 28 октября 2026, ru_RU и en_US).
# Безвредное перечислено ниже с доводом. Контроль внутри пробы: с мест, где LC_ALL=C стоит, он снимается на копии —
# сканер обязан их назвать (иначе «пусто» ничего не значит).
# Предел признака: сравнение данных с данными (поле с полем, слово с вершиной стека) без литерала и без -v он не видит.
# Красная (1), пока есть место без LC_ALL=C и без довода либо контроль не назван; 2 — рамка не собралась.
R="${CLAUDSOUL_REPO:-$(cd "$(dirname "$0")/../../.." && pwd)}"
command -v python3 >/dev/null 2>&1 && command -v git >/dev/null 2>&1 || exit 2
[ -f "$R/hooks/completion-gate.sh" ] || exit 2
T=$(mktemp -d) || exit 2
trap 'rm -rf "$T"' EXIT
cat > "$T/scan.py" <<'PY'
import re, shlex, sys
CMP = r"(?:==|!=|<=|>=|(?<![<>=!])<(?![<=])|(?<![-<>=!])>(?![>=]))"
def code_of(prog):
    """Программа без строковых литералов и комментариев: литералы — в отдельный список."""
    out, lits, i, n = [], [], 0, len(prog)
    while i < n:
        c = prog[i]
        if c == '"':
            j = i + 1
            while j < n and prog[j] != '"':
                j += 2 if prog[j] == "\\" else 1
            lits.append(prog[i + 1:j]); out.append('"L%d"' % (len(lits) - 1)); i = j + 1; continue
        if c == "#":
            while i < n and prog[i] != "\n":
                i += 1
            continue
        out.append(c); i += 1
    return "".join(out), lits
def scan(path):
    try:
        txt = open(path, encoding="utf-8").read()
    except (OSError, UnicodeDecodeError):
        return
    for m in re.finditer(r"(?<![\w./-])(?:/usr/bin/)?awk(?![\w.-])", txt):
        ls = txt.rfind("\n", 0, m.start()) + 1
        if txt[ls:m.start()].lstrip().startswith("#"):
            continue
        lex = shlex.shlex(txt[m.start():], posix=True, punctuation_chars=True)
        lex.whitespace_split = True
        try:
            lex.get_token()
            vs, prog = {}, None
            while prog is None:
                t = lex.get_token()
                if t is None or t in ("|", ";", "&&", "||", ")", "&", "\n"):
                    break
                if t == "-f":
                    break
                if t == "-F":
                    lex.get_token(); continue
                if t == "-v":
                    t = "-v" + (lex.get_token() or "")
                if t.startswith("-v") and "=" in t:
                    k, v = t[2:].split("=", 1); vs[k] = v; continue
                if t.startswith("-"):
                    continue
                prog = t
        except ValueError:
            continue
        if not prog:
            continue
        # Судится простой вызов самого awk: LC_ALL=C у соседа по трубе его не защищает, а локаль, объявленная в
        # вызове (LC_ALL=, LANG=, LC_COLLATE= — ноги-контроли нарочно зовут awk под ru_RU), — выбор, а не забытое.
        seg = re.split(r"[|;&(`]", txt[ls:m.start()])[-1]
        if re.search(r"(?<![\w])(?:LC_ALL|LC_COLLATE|LANG)=", seg):
            continue
        code, lits = code_of(prog)
        why = []
        for c in re.finditer(r'"L(\d+)"\s*' + CMP + r'|' + CMP + r'\s*"L(\d+)"', code):
            lit = lits[int(c.group(1) or c.group(2))]
            if re.search(r"[^\x00-\x7f]", lit):
                why.append("литерал «%s»" % lit[:24])
        for k, v in vs.items():
            if re.search(r"MARK|[^\x00-\x7f]", v) and re.search(
                    r"(?<![\w$])" + k + r"\s*" + CMP + r"|" + CMP + r"\s*" + k + r"(?![\w(])", code):
                why.append("-v %s=%s" % (k, v[:32]))
        if why:
            print("%s:%d\t%s" % (path, txt.count("\n", 0, m.start()) + 1, "; ".join(why)))
for p in sys.argv[1:]:
    scan(p)
PY
# Безвредное: место (путь:строка<TAB>довод). Пусто — признак на нынешнем дереве вне LC_ALL=C ничего не находит.
cat > "$T/allow.tsv" <<'TSV'
TSV
cd "$R" || exit 2
git ls-files -z -- hooks scripts lib bin install.sh uninstall.sh | tr '\0' '\n' \
    | grep -E '(\.sh|/[^./]+)$' > "$T/files" || exit 2
[ -s "$T/files" ] || exit 2
tr '\n' '\0' < "$T/files" | xargs -0 python3 "$T/scan.py" > "$T/hits" || exit 2
# Контроль: копии файлов с LC_ALL=C awk без префикса — сканер обязан назвать места обеих веток: метку в -v (хуки) и
# литерал с не-ASCII (`scripts/guard-edition-exposures.sh`, скептик D1171 M2).
mkdir -p "$T/ctl" || exit 2
for f in hooks/completion-gate.sh hooks/guarantee-map-guard.sh hooks/five-whys-gate.sh scripts/guard-edition-exposures.sh; do
    [ -f "$f" ] || exit 2
    sed 's/LC_ALL=C awk/awk/g' "$f" > "$T/ctl/${f##*/}" || exit 2
done
( cd "$T/ctl" && python3 "$T/scan.py" completion-gate.sh guarantee-map-guard.sh five-whys-gate.sh guard-edition-exposures.sh ) > "$T/ctl.hits" || exit 2
for want in "completion-gate.sh:3" "guarantee-map-guard.sh:1" "five-whys-gate.sh:1" "guard-edition-exposures.sh:4"; do
    f=${want%:*}; n=${want#*:}
    got=$(grep -c "^$f:" "$T/ctl.hits")
    [ "$got" -ge "$n" ] || { echo "контроль: в $f без LC_ALL=C названо мест: $got из $n — признак слеп"; exit 1; }
done
bad=0
while IFS=$'\t' read -r where why; do
    cut -f1 "$T/allow.tsv" | grep -qxF "$where" && continue
    echo "без LC_ALL=C: $where — $why"; bad=1
done < "$T/hits"
exit "$bad"
