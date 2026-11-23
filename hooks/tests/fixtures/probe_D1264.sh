#!/usr/bin/env bash
set -u
# СУДИТ: hooks/lib/project_map.py
# probe_D1264 — связь Swift: слово после `.` — член чужого значения, а не имя верхнего уровня:
#   (п) `menu.delegate = self` при глобальной `delegate` в `main.swift` того же модуля — ребра нет;
#   (к) `Core.Engine()` при `import Core` — ребро к `Sources/Core/Engine.swift` есть; голое `Engine()` — тоже;
#   (д) `Helper.go()` — ребро к объявившему `Helper` (слово ДО точки) остаётся.
# Код: 0 — так; 1 — нет (названо); 2 — рамка не собралась.
R="${CLAUDSOUL_REPO:-$(cd "$(dirname "$0")/../../.." && pwd)}"
L="$R/hooks/lib/project_map.py"
[ -f "$L" ] && command -v python3 >/dev/null 2>&1 || exit 2
T=$(mktemp -d) || exit 2
trap 'rm -rf "$T"' EXIT
python3 - "$L" "$T" <<'PY'
import importlib.util, os, sys
s = importlib.util.spec_from_file_location("pm", sys.argv[1]); pm = importlib.util.module_from_spec(s); s.loader.exec_module(pm)
T = sys.argv[2]
files = {
    "Sources/App/main.swift": "var delegate = AppDelegate()\n",
    "Sources/App/AppDelegate.swift": "final class AppDelegate {\n    func go(menu: Menu) { menu.delegate = self }\n}\n",
    "Sources/App/Menu.swift": "final class Menu { var delegate: AnyObject? }\n",
    "Sources/App/use.swift": "import Core\nlet a = Core.Engine()\nlet b = Helper.go()\n",
    "Sources/Core/Engine.swift": "public struct Engine {}\n",
    "Sources/Core/Helper.swift": "public enum Helper { public static func go() {} }\n",
}
for p, t in files.items():
    os.makedirs(os.path.dirname(os.path.join(T, p)), exist_ok=True)
    open(os.path.join(T, p), "w", encoding="utf-8").write(t)
m = {"version": 1, "code": [{"glob": "**/*.swift", "lang": "swift"}], "tests": ["**/Tests/**"]}
uni = set(files)
ref = lambda p: pm.import_refs(m, T, p, files[p], uni)
bad = []
if "Sources/App/main.swift" in ref("Sources/App/AppDelegate.swift"):
    bad.append("menu.delegate дал ребро к глобальной delegate в main.swift")
u = ref("Sources/App/use.swift")
if "Sources/Core/Engine.swift" not in u:
    bad.append("Core.Engine() не дал ребра к Engine.swift")
if "Sources/Core/Helper.swift" not in u:
    bad.append("Helper.go() не дал ребра к Helper.swift")
if "Sources/App/AppDelegate.swift" not in ref("Sources/App/main.swift"):
    print("рамка: голое AppDelegate() не дало ребра", file=sys.stderr); sys.exit(2)
# (х) файл вне раскладки SwiftPM (раскладка Xcode `App/…`, модуль пуст): член без имени перед точкой — тоже член
#     (`center().delegate`, `.red`), иначе пустой модуль проводил его как полное имя (скептик opus D1264, M1).
X = {"App/Litara/main.swift": "var delegate = AppDelegate()\nfunc red() {}\n",
     "App/Litara/AppDelegate.swift": "final class AppDelegate {\n  func go() { center().delegate = self; let c: Color = .red }\n}\n"}
for p, t in X.items():
    os.makedirs(os.path.dirname(os.path.join(T, p)), exist_ok=True)
    open(os.path.join(T, p), "w", encoding="utf-8").write(t)
if "App/Litara/main.swift" in pm.import_refs(m, T, "App/Litara/AppDelegate.swift", X["App/Litara/AppDelegate.swift"], set(X)):
    bad.append("вне раскладки SwiftPM член без имени перед точкой дал ребро")
if bad:
    print("; ".join(bad)); sys.exit(1)
print("член после точки ребра не даёт; Модуль.Тип и Тип.член — дают")
PY
