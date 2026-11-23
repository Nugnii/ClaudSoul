#!/usr/bin/env bash
# СУДИТ: hooks/backlog-lib.sh scripts/defect-class-carriers.py
# test_backlog_green_side.sh — у «Проверки» КАЖДОГО открытого пункта долга предъявлена зелёная
#                              сторона: фикстура, в которой та же команда даёт 0 (D405).
# Результат: для каждого открытого пункта BACKLOG.md здесь есть фикстура green_<ID>, и под ней
#            «Проверка» пункта зелёная; открытый пункт без фикстуры — красная нога, то есть новый
#            пункт обязан принести свою зелёную сторону вместе с собой. Отрицательный контроль:
#            без фикстуры та же команда красна.
# Проверка результата: bash hooks/tests/test_backlog_green_side.sh даёт 0
#
# Зачем. Красная команда открытого пункта доказывает лишь, что мир сейчас не таков, как
# объявлено; она не доказывает, что позеленеет от починки, а не оттого, что перестала видеть
# предмет (D405, дробь родителя: 4 промаха из 4 без такого контроля против 0 из 14 с ним).
# Фикстура — тот же приём, что у мутанта в копии дерева: «Проверка» исполняется под окружением,
# где мир уже починен. Общий рычаг — CLAUDSOUL_REPO указывает на каталог-фикстуру, потому что
# каждая «Проверка» сама делает туда cd; иные рычаги — STATE_DIR, HOME.
#
# ЧТО ПОКАЗАЛ ПЕРВЫЙ ПРОХОД (13 сентября 2026). У шести пунктов зелёная сторона — заглушка с
# нужным именем файла или словом: их «Проверка» судит по ФОРМЕ, а не по делу. Это записано у
# каждого такого пункта, и закрывать его можно только прибором — файл с нужным именем позеленит
# команду, не решив ничего.
set -uo pipefail
# РАМКА ЗАДАЁТСЯ, А НЕ НАСЛЕДУЕТСЯ (D461, 18 сентября 2026). Гейт прогоняет «Проверку»
# пункта с BACKLOG_CHECKS_NESTED=1 (защита от кольца процессов), а предмет этого теста —
# сам гейт: под маркером он выходит молча, и тест краснел бы В РАМКЕ ЧЬЕГО-ТО ПУНКТА при
# зелёном прямом прогоне. Снимается здесь, а не у каждого вызова: вызовов в файле больше
# одного, и следующий добавленный унаследовал бы маркер молча.
unset BACKLOG_CHECKS_NESTED
DIR="$(cd "$(dirname "$0")" && pwd)"
REPO="$(cd "$DIR/../.." && pwd)"

# Предмет этого свидетеля в публичный снимок не входит (рабочий долг BACKLOG.md). В неполном дереве
# «файла нет» значит «изъят по решению», а не «пропал»: пропуск называется, дефект не
# объявляется — иначе один канал несёт два состояния мира (корень R6).
UNIVERSE_ROOT="$REPO"; . "$REPO/hooks/lib/universe-lib.sh" 2>/dev/null || true
if command -v universe_partial_tree >/dev/null 2>&1 && universe_partial_tree; then
    universe_skip_note "test_backlog_green_side" "рабочий долг BACKLOG.md"; exit 0
fi
# shellcheck source=../backlog-lib.sh
. "$REPO/hooks/backlog-lib.sh"
command -v backlog_open_items >/dev/null 2>&1 || { echo "FAIL: backlog_open_items недоступна"; exit 1; }
PASS=0; FAIL=0
ok()  { PASS=$((PASS + 1)); }
bad() { FAIL=$((FAIL + 1)); echo "FAIL [$1]: $2"; }
TMP=$(mktemp -d)   # временное уберёт система
mkfix() { local d="$TMP/$1"; mkdir -p "$d"; printf '%s' "$d"; }

# ОДИН ВЛАДЕЛЕЦ ВЫЗОВА ПАТЧЕРА (D464, 19 сентября 2026). Патчер, упавший ассертом — якорь
# уехал, механизм под ним изменился, — оставлял в фикстуре ЖИВОЙ файл, а нога всё равно
# отдавала каталог и код 0: её код есть код завершающего `echo`. «Проверка» тогда зеленела
# от живого дерева, а не от починки, и это наблюдалось на снятой ноге green_D445, которая
# патчила через `.new` + `mv`. Здесь отказ называется и возвращается наверх; вызывающая
# нога обязана нести `|| return 1`, иначе смысла в коде нет.
apply_patch() {  # apply_patch <патчер.py> <аргументы…> → 0 пропатчено, 1 патчер упал
    python3 "$@" && return 0
    echo "зелёная сторона: патчер упал: $(basename "$1")" >&2
    return 1
}

# Пробный git-репозиторий для реестра родов: ему хватает install.sh и каталога hooks/ (образец D360).
# Строится ОДИН раз и заранее: фикстуры исполняются в подстановке `$(…)`, где присваивание не
# переживает вызов, а повторный `git commit` печатал «nothing to commit» прямо в окружение.
TMP_PROBE="$TMP/probe"; mkdir -p "$TMP_PROBE/scripts" "$TMP_PROBE/hooks"
cp "$REPO/scripts/defect-class-carriers.py" "$TMP_PROBE/scripts/"; cp "$REPO/install.sh" "$TMP_PROBE/"
printf '#!/usr/bin/env bash\necho x\n' > "$TMP_PROBE/hooks/probe.sh"
git -C "$TMP_PROBE" init -q && git -C "$TMP_PROBE" add -A && { git -C "$TMP_PROBE" -c user.name=t -c user.email=t@t commit -qm x >/dev/null || { echo "подготовка мира не удалась: hooks/tests/test_backlog_green_side.sh:$LINENO" >&2; exit 1; }; }

# --- фикстуры: green_<ID> готовит мир и печатает строки ИМЯ=значение окружения ---------------
green_D307() { echo "CLAUDSOUL_REPO=$TMP_PROBE"; }          # род G в пробе пуст
green_D310() { echo "CLAUDSOUL_REPO=$TMP_PROBE"; }          # род F не называет test_docs_family_check
green_D1001() { echo "CLAUDSOUL_REPO=$REPO"; }              # дерево с починкой пары: режим записи входит в единицу сверки
green_D1002() { echo "CLAUDSOUL_REPO=$REPO"; }              # дерево с починкой: формы нет, страж на длинной команде быстр
# Зелёная сторона D1006 — ДОМ, в чьём каталоге состояния несколько мелких файлов: «Проверка» берёт каталог у HOME
# (не у STATE_DIR — его подставляет набор), и мир «уборка держит рост» собирается подменой дома.
green_D1006() { local d; d=$(mkfix D1006); mkdir -p "$d/.claude/hooks/state"
    : > "$d/.claude/hooks/session-collector.sh"          # признак установки: без него «Проверка» — 2, «предмета нет»
    printf '{}\n' > "$d/.claude/hooks/state/a.json"; printf 'x\n' > "$d/.claude/hooks/state/b.txt"
    echo "HOME=$d"; echo "CLAUDSOUL_REPO=$REPO"; }
# Зелёная сторона D1008 — ДОМ с установленным сборщиком, где у хранимых семейств не больше 60 сессий: «Проверка»
# берёт каталог у HOME, как у D1006.
green_D1008() { local d; d=$(mkfix D1008); mkdir -p "$d/.claude/hooks/state"
    : > "$d/.claude/hooks/session-collector.sh"
    : > "$d/.claude/hooks/state/blocker-fired-00000000-0000-4000-8000-000000000001.jsonl"
    : > "$d/.claude/hooks/state/blocker-fired-00000000-0000-4000-8000-000000000002.jsonl"
    echo "HOME=$d"; echo "CLAUDSOUL_REPO=$REPO"; }
# Зелёная сторона D1009 — ДЕРЕВО, где кэш карты связей новее учёта: «Проверка» сравнивает их время в CLAUDSOUL_REPO.
green_D1009() { local d; d=$(mkfix D1009); mkdir -p "$d/.claude-docs" "$d/mcp-server/visualization"
    : > "$d/.claude-docs/dep-index.tsv"; touch -t 202001010000 "$d/.claude-docs/dep-index.tsv"
    printf '{}\n' > "$d/mcp-server/visualization/project-graph-data.json"
    echo "CLAUDSOUL_REPO=$d"; }
# Зелёная сторона D1039 — ДЕРЕВО, чей вид `full` держит местный вызов, а `hbody_raw` пуст: «Проверка» подключает
# библиотеку из CLAUDSOUL_REPO. Имя инструмента собрано из частей — страж отсутствующего инструмента судит текст.
green_D1039() { local d; d=$(mkfix D1039); mkdir -p "$d/hooks"
    printf '%s\n' 'x=time' '_ds_view() { case "$1" in full) _DS_V="${x}out 5 true" ;; *) _DS_V="" ;; esac; }' \
        > "$d/hooks/detection-signals-lib.sh"
    echo "CLAUDSOUL_REPO=$d"; }
# Зелёная сторона D1046 — ДЕРЕВО, чей хук называет пункты раздела под уточнённым заголовком, под `- **Что …**` и с
# «Ничего не …»: «Проверка» исполняет хук из CLAUDSOUL_REPO с STATE_DIR пробы.
green_D1046() { local d; d=$(mkfix D1046); mkdir -p "$d/hooks"
    printf '%s\n' '#!/usr/bin/env bash' 'in=$(cat "$(jq -r .transcript_path)")' \
        'for w in "первая сирота" "вторая сирота" "третья сирота"; do case "$in" in *"$w"*) echo "$w" >> "$STATE_DIR/startup-signals-s1.txt" ;; esac; done' \
        > "$d/hooks/declared-problem-recorded.sh"
    echo "CLAUDSOUL_REPO=$d"; }
# Зелёная сторона D1047 — ДЕРЕВО, чей канал держит напоминание вне файла сигналов старта и отдаёт его любой следующей
# сессии: «Проверка» исполняет три хука из CLAUDSOUL_REPO с STATE_DIR и HOME пробы.
green_D1047() { local d; d=$(mkfix D1047); mkdir -p "$d/hooks"
    printf '%s\n' '#!/usr/bin/env bash' 'cat >/dev/null; echo "сирота канала без исхода" > "$STATE_DIR/stop-note.txt"' > "$d/hooks/declared-problem-recorded.sh"
    printf '%s\n' '#!/usr/bin/env bash' 'cat >/dev/null; : > "$STATE_DIR/startup-signals-s1.txt"' > "$d/hooks/session-start.sh"
    printf '%s\n' '#!/usr/bin/env bash' 'cat >/dev/null; cat "$STATE_DIR/stop-note.txt" 2>/dev/null' > "$d/hooks/pending-alerts-surface.sh"
    echo "CLAUDSOUL_REPO=$d"; }
# Зелёная сторона D1048 — ДЕРЕВО, чей хук называет пункты `•`, пункт после `- **Что …:**`, пункт «Находка …» и
# «Ничего нового, кроме …»: «Проверка» исполняет хук из CLAUDSOUL_REPO с STATE_DIR пробы.
green_D1048() { local d; d=$(mkfix D1048); mkdir -p "$d/hooks"
    printf '%s\n' '#!/usr/bin/env bash' 'in=$(cat "$(jq -r .transcript_path)")' \
        'for w in "вторая сирота точкой" "сирота после метки-пункта" "Находка в хуке без пометки" "сирота после ничего"; do case "$in" in *"$w"*) echo "$w" >> "$STATE_DIR/stop-signals-s1.txt" ;; esac; done' \
        > "$d/hooks/declared-problem-recorded.sh"
    echo "CLAUDSOUL_REPO=$d"; }
# Зелёная сторона D1055 — ДЕРЕВО, чей канал держит напоминание у вернувшейся сессии: своя реплика его получает,
# чужая — нет. Заглушки различают сессию по session_id входа.
green_D1055() { local d; d=$(mkfix D1055); mkdir -p "$d/hooks"
    printf '%s\n' '#!/usr/bin/env bash' 'cat >/dev/null; exit 0' > "$d/hooks/declared-problem-recorded.sh"
    printf '%s\n' '#!/usr/bin/env bash' 'cat >/dev/null; exit 0' > "$d/hooks/session-end.sh"
    printf '%s\n' '#!/usr/bin/env bash' 's=$(jq -r .session_id); [ "$s" = s1 ] && echo "вторая сирота"; exit 0' > "$d/hooks/pending-alerts-surface.sh"
    echo "CLAUDSOUL_REPO=$d"; }
# Зелёная сторона D1056 — ДЕРЕВО, чей хук называет четыре сироты и не называет шаг плана.
green_D1056() { local d; d=$(mkfix D1056); mkdir -p "$d/hooks"
    printf '%s\n' '#!/usr/bin/env bash' 'in=$(cat "$(jq -r .transcript_path)")' \
        'for w in "сирота после метки-префикса" "сирота голого списка" "сирота стрелки" "сирота после точки"; do case "$in" in *"$w"*) echo "$w" >> "$STATE_DIR/stop-signals-s1.txt" ;; esac; done' \
        > "$d/hooks/declared-problem-recorded.sh"
    echo "CLAUDSOUL_REPO=$d"; }
# Зелёная сторона D1064 — ДЕРЕВО, чей страж отказывает двум местным вызовам после тела и молчит на строке данных.
green_D1064() { local d; d=$(mkfix D1064); mkdir -p "$d/hooks"
    printf '%s\n' '#!/usr/bin/env bash' 'c=$(jq -r .tool_input.command); case "$c" in *"plain; timeout 5 x"*) exit 0 ;; *"timeout 5"*) echo deny ;; esac' > "$d/hooks/absent-tool-guard.sh"
    echo "CLAUDSOUL_REPO=$d"; }
# Зелёная сторона D1068 — ДЕРЕВО, чьи учёт и карта отбивают выход за проект и чужой каталог, а кэш носителем не зовут.
green_D1068() { local d; d=$(mkfix D1068); mkdir -p "$d/hooks/lib" "$d/scripts"
    : > "$d/hooks/lib/project_map.py"
    printf '%s\n' '#!/usr/bin/env python3' 'import sys' 'r = sys.argv[sys.argv.index("--repo") + 1] if "--repo" in sys.argv else ""' \
        'sys.exit(2 if r.endswith("/p") else 0)' > "$d/scripts/project-graph.py"
    printf '%s\n' '#!/usr/bin/env python3' 'import sys' 'r = sys.argv[sys.argv.index("--repo") + 1] if "--repo" in sys.argv else ""' \
        'sys.exit(2 if r.endswith("/nope") else 0)' > "$d/scripts/dep-index.py"
    echo "CLAUDSOUL_REPO=$d"; }
# Зелёная сторона D1075 — ДЕРЕВО, чья карточка архива бэклога называет его читателей, а карта даёт настоящих писателей
# (назначение `mv`, второй аргумент `os.replace`), писателя бэклога через программу — «читает» (предел) и не даёт ложного «читает».
# Пути записаны задом наперёд — учёт засчитал бы имена механизмов в тексте теста как «проверяет» (урок фикстуры D1067).
green_D1075() { local d; d=$(mkfix D1075); mkdir -p "$d/scripts" "$d/mcp-server/visualization"
    printf '%s\n' '#!/usr/bin/env python3' 'import json, sys' \
        'N = ["hs.rotcelloc-noisses/skooh", "hs.etag-noitelpmoc/skooh", "hs.kcehc-hsinav-golkcab/skooh"]' \
        'if "--node" in sys.argv:' '    print("\n".join("  " + s[::-1] for s in N)); sys.exit(0)' \
        'E = [("hs.evihcra-golkcab/stpircs", "dm.GOLKCAB", "читает"), ("hs.stats-tnuoc/stpircs", "dm.EDUALC", "записывает"),' \
        '     ("hs.slliks-emdaer-neger/stpircs", "dm.EMDAER", "записывает"), ("yp.xedni-ped/stpircs", "vst.xedni-ped/scod-edualc.", "записывает")]' \
        'if "--refresh" in sys.argv:' \
        '    E = [(s[::-1], t[::-1], r) for s, t, r in E]; keys = sorted({x for e in E for x in e[:2]}); ids = {k: i for i, k in enumerate(keys)}' \
        '    json.dump({"nodes": [{"id": ids[k], "key": k} for k in keys],' \
        '               "edges": [{"source": ids[s], "target": ids[t], "type": r} for s, t, r in E]},' \
        '              open("mcp-server/visualization/project-graph-data.json", "w"))' > "$d/scripts/project-graph.py"
    echo "CLAUDSOUL_REPO=$d"; }
# Зелёная сторона D1082 — ДЕРЕВО, чей свидетель хука коммита зелёный, а свидетель карты прошёл без падения C13 и C3b.
green_D1082() { local d; d=$(mkfix D1082); mkdir -p "$d/hooks/tests" "$d/scripts"
    printf '%s\n' '#!/usr/bin/env bash' '# T32б' 'exit 0' > "$d/hooks/tests/test_doc_impact_check.sh"
    printf '%s\n' '#!/usr/bin/env bash' '# C13' 'echo "test_project_map: прошло 2, упало 0"' > "$d/hooks/tests/test_project_map.sh"
    printf '%s\n' '#!/usr/bin/env python3' > "$d/scripts/dep-index.py"; : > "$d/hooks/doc-impact-check.sh"
    echo "CLAUDSOUL_REPO=$d"; }
# Зелёная сторона D1100 — ДЕРЕВО, чья копия бэклога различает отказ копии и запись.
green_D1100() { local d; d=$(mkfix D1100); mkdir -p "$d/hooks/tests"; : > "$d/hooks/backlog-lib.sh"
    printf '%s\n' '#!/usr/bin/env bash' '# нога T7: CAT_EMPTY=2' 'echo "backlog stable read: PASS=11 FAIL=0"' > "$d/hooks/tests/test_backlog_stable_read.sh"
    echo "CLAUDSOUL_REPO=$d"; }
# Зелёная сторона D1101 — ДЕРЕВО, чей счёт «открытых N» под писателем с усечением не ошибается.
green_D1101() { local d; d=$(mkfix D1101); mkdir -p "$d/hooks/tests/fixtures"; : > "$d/hooks/session-collector.sh"
    printf '%s\n' '#!/usr/bin/env bash' 'echo "чтений 600, неверных 0"' 'exit 0' > "$d/hooks/tests/fixtures/probe_D1101.sh"
    echo "CLAUDSOUL_REPO=$d"; }
# Зелёная сторона D1102 — ДЕРЕВО, чей установщик называет перенос META честно.
green_D1102() { local d; d=$(mkfix D1102)
    printf '%s\n' '#!/usr/bin/env bash' 'cmp -s "$CLAUDSOUL_DIR/knowledge/META.md" "$GLOBAL_LESSONS/META.md" && info "META.md установлен"' \
        'echo "  ~/.claude/global-lessons/    стартовые знания — ТОЛЬКО отсутствующие; META.md — через журнал переносов"' > "$d/install.sh"
    echo "CLAUDSOUL_REPO=$d"; }
# Зелёная сторона D1106 — ДЕРЕВО, чья команда исхода отвергает несвежую запись.
green_D1106() { local d; d=$(mkfix D1106); mkdir -p "$d/scripts" "$d/hooks/tests/fixtures"; : > "$d/scripts/outcome.sh"
    printf '%s\n' '#!/usr/bin/env bash' 'echo "несвежая запись отвергнута, свежая по цели принята"' 'exit 0' > "$d/hooks/tests/fixtures/probe_D1106.sh"
    echo "CLAUDSOUL_REPO=$d"; }
# Зелёные стороны D1108–D1111 — ДЕРЕВЬЯ, чьи пробы сверки исхода зелёные (предмет пробы — настоящий страж и команда
# исхода; здесь судится только связь «Проверки» с пробой).
green_probe_tree() { local d; d=$(mkfix "$1"); mkdir -p "$d/hooks/tests/fixtures"; : > "$d/hooks/$2"
    printf '%s\n' '#!/usr/bin/env bash' "echo \"$3\"" 'exit 0' > "$d/hooks/tests/fixtures/probe_$1.sh"
    echo "CLAUDSOUL_REPO=$d"; }
green_D1108() { green_probe_tree D1108 five-whys-gate.sh "свежесть по снимку"; }
green_D1109() { green_probe_tree D1109 five-whys-gate.sh "контекст — повод хода"; }
green_D1110() { green_probe_tree D1110 five-whys-gate.sh "формы — по устройству"; }
green_D1111() { green_probe_tree D1111 root-cause-lib.sh "последствия D1107 доведены"; }
green_D1112() { local d; d=$(mkfix D1112); mkdir -p "$d/hooks/lib" "$d/hooks/tests/fixtures"; : > "$d/hooks/lib/write-target-lib.sh"
    printf '%s\n' '#!/usr/bin/env bash' 'echo "временные корни согласованы"' 'exit 0' > "$d/hooks/tests/fixtures/probe_D1112.sh"
    echo "CLAUDSOUL_REPO=$d"; }
green_D1115() { green_probe_tree D1115 root-cause-lib.sh "снимок различает поводы"; }
green_D1116() { green_probe_tree D1116 five-whys-gate.sh "исход снимает свой повод"; }
green_D1117() { local d; d=$(mkfix D1117); mkdir -p "$d/scripts" "$d/hooks/tests/fixtures"; : > "$d/scripts/state-prune.sh"
    printf '%s\n' '#!/usr/bin/env bash' 'echo "снимки уходят с сессией"' 'exit 0' > "$d/hooks/tests/fixtures/probe_D1117.sh"
    echo "CLAUDSOUL_REPO=$d"; }
green_D1118() { green_probe_tree D1118 declared-problem-recorded.sh "счёт по строкам хода"; }
green_D1119() { green_probe_tree D1119 root-cause-lib.sh "переходы после touched целы"; }
green_D1120() { green_probe_tree D1120 root-cause-lib.sh "мутации краснят пробы"; }
green_D1121() { green_probe_tree D1121 backlog-lib.sh "нечитаемый бэклог — не пустой"; }
green_D1122() { green_probe_tree D1122 backlog-open-write-guard.sh "пункты не раскалывают чужой блок"; }
green_D1125() { green_probe_tree D1125 root-cause-lib.sh "позднейший отказ сохранён"; }
green_D1126() { green_probe_tree D1126 five-whys-gate.sh "отказ второй находки виден"; }
green_D1128() { green_probe_tree D1128 root-cause-lib.sh "пересматривается"; }
green_D1129() { green_probe_tree D1129 root-cause-lib.sh "экранирование в токене не открывает снятие"; }
green_D1130() { green_probe_tree D1130 root-cause-lib.sh "одинаковая реплика — разные ходы"; }
green_D1127() { local d; d=$(mkfix D1127); mkdir -p "$d/scripts" "$d/hooks/tests/fixtures"; : > "$d/scripts/outcome.sh"
    printf '%s\n' '#!/usr/bin/env bash' 'echo "«;» в пути повода не режет токен"' 'exit 0' > "$d/hooks/tests/fixtures/probe_D1127.sh"
    echo "CLAUDSOUL_REPO=$d"; }
green_D1131() { local d; d=$(mkfix D1131); mkdir -p "$d/hooks/tests/fixtures"; : > "$d/ROOTS.md"
    printf '%s\n' 'echo "«${last}»"' > "$d/hooks/tests/fixtures/probe_D1126.sh"
    echo "CLAUDSOUL_REPO=$d"; }
green_D1132() { green_probe_tree D1132 completion-gate.sh "«не проверена», а не красная"; }
green_D1133() { green_probe_tree D1133 five-whys-gate.sh "стоячий вид после снятия ложного отказа не получает"; }
green_D1134() { green_probe_tree D1134 backlog-open-write-guard.sh "раскол — по переезду строк"; }
green_D1135() { green_probe_tree D1135 root-cause-lib.sh "«не прочитан» пишется при смене состояния"; }
green_D1136() { local d; d=$(mkfix D1136); mkdir -p "$d/hooks/lib" "$d/hooks/tests/fixtures"; : > "$d/hooks/lib/write_targets.py"
    printf '%s\n' '#!/usr/bin/env bash' 'echo "ключ -A и операнд после -- разобраны"' 'exit 0' > "$d/hooks/tests/fixtures/probe_D1136.sh"
    echo "CLAUDSOUL_REPO=$d"; }
green_D1124() { green_probe_tree D1124 completion-gate.sh "нечитаемый бэклог назван"; }
green_D1137() { green_probe_tree D1137 backlog-open-write-guard.sh "закрытие защитного слоя без «Скептик.» отбито"; }
green_D1138() { green_probe_tree D1138 user-correction-guard.sh "вызов команды поправкой не записан"; }
green_D1140() { green_probe_tree D1140 backlog-vanish-check.sh "заявление о закрытии — глагол, метки знаками"; }
green_D1141() { green_probe_tree D1141 backlog-open-write-guard.sh "путь в другом регистре судится как BACKLOG.md"; }
green_D1142() { green_probe_tree D1142 user-correction-guard.sh "реплика посреди хода судится как реплика"; }
green_D1144() { green_probe_tree D1144 itr-event-detector.sh "вторая реплика не судится по уже отвеченному предложению"; }
green_D1145() { local d; d=$(mkfix D1145); mkdir -p "$d/hooks/lib" "$d/hooks/tests/fixtures" "$d/scripts"
    # Настоящая проба на дереве, где у единственного читателя строка есть (не заглушка — скептик D1145, L4).
    cp "$REPO/hooks/tests/fixtures/probe_D1145.sh" "$d/hooks/tests/fixtures/" || return 1
    printf 'def is_owner_reply(rec):\n    return True\n' > "$d/hooks/lib/transcript_window.py"
    printf 'x=$(transcript_user_texts "$T" 1)\n' > "$d/hooks/reader.sh"
    printf 'hooks/lib/transcript_window.py\tисточник\nhooks/reader.sh\tречь\n' > "$d/hooks/lib/reply-readers.tsv"
    echo "CLAUDSOUL_REPO=$d"; }
green_D1152() { local d; d=$(mkfix D1152); mkdir -p "$d/hooks/tests/fixtures"
    printf '%s\n' '#!/usr/bin/env bash' 'echo "реестр привязан к опознанию"' 'exit 0' > "$d/hooks/tests/fixtures/probe_D1152.sh"
    echo "CLAUDSOUL_REPO=$d"; }
green_D1153() { local d; d=$(mkfix D1153); mkdir -p "$d/hooks/tests/fixtures"
    printf '%s\n' '#!/usr/bin/env bash' 'echo "результат инструмента ход не делит"' 'exit 0' > "$d/hooks/tests/fixtures/probe_D1153.sh"
    echo "CLAUDSOUL_REPO=$d"; }
green_D1151() { local d; d=$(mkfix D1151); mkdir -p "$d/hooks/tests/fixtures"
    printf '%s\n' '#!/usr/bin/env bash' 'echo "запись при стоячем виде — отказ либо тишина"' 'exit 0' > "$d/hooks/tests/fixtures/probe_D1151.sh"
    echo "CLAUDSOUL_REPO=$d"; }
green_D1149() { local d; d=$(mkfix D1149); mkdir -p "$d/hooks/tests/fixtures"
    printf '%s\n' '#!/usr/bin/env bash' 'echo "подмена понятия краснит свидетеля"' 'exit 0' > "$d/hooks/tests/fixtures/probe_D1149.sh"
    echo "CLAUDSOUL_REPO=$d"; }
green_D1202() { local d; d=$(mkfix D1202); mkdir -p "$d/hooks/tests/fixtures"
    printf '%s\n' '#!/usr/bin/env bash' 'echo "свидетель видит оба пути и все поля"' 'exit 0' > "$d/hooks/tests/fixtures/probe_D1202.sh"
    echo "CLAUDSOUL_REPO=$d"; }
green_D1203() { local d; d=$(mkfix D1203); mkdir -p "$d/hooks/tests/fixtures"
    printf '%s\n' '#!/usr/bin/env bash' 'echo "правка реестра выбирает его тесты"' 'exit 0' > "$d/hooks/tests/fixtures/probe_D1203.sh"
    echo "CLAUDSOUL_REPO=$d"; }
green_D1204() { local d; d=$(mkfix D1204); mkdir -p "$d/hooks/tests/fixtures"
    printf '%s\n' '#!/usr/bin/env bash' 'echo "непроверенные по бюджету идут первыми на следующей границе"' 'exit 0' > "$d/hooks/tests/fixtures/probe_D1204.sh"
    echo "CLAUDSOUL_REPO=$d"; }
green_D1205() { local d; d=$(mkfix D1205); mkdir -p "$d/hooks/tests/fixtures"
    printf '%s\n' '#!/usr/bin/env bash' 'echo "авторизация в реплее переходит между ходами одной сессии"' 'exit 0' > "$d/hooks/tests/fixtures/probe_D1205.sh"
    echo "CLAUDSOUL_REPO=$d"; }
green_D1206() { local d; d=$(mkfix D1206); mkdir -p "$d/hooks/tests/fixtures"
    printf '%s\n' '#!/usr/bin/env bash' 'echo "проба D1151 судит виды и формы записи живых ходов"' 'exit 0' > "$d/hooks/tests/fixtures/probe_D1206.sh"
    echo "CLAUDSOUL_REPO=$d"; }
green_D1207() { local d; d=$(mkfix D1207); mkdir -p "$d/hooks/tests/fixtures"
    printf '%s\n' '#!/usr/bin/env bash' 'echo "ход субагента не судится речью владельца"' 'exit 0' > "$d/hooks/tests/fixtures/probe_D1207.sh"
    echo "CLAUDSOUL_REPO=$d"; }
green_D1208() { local d; d=$(mkfix D1208); mkdir -p "$d/hooks/tests/fixtures"
    printf '%s\n' '#!/usr/bin/env bash' 'echo "массовый реплей проходит путь с пробелом"' 'exit 0' > "$d/hooks/tests/fixtures/probe_D1208.sh"
    echo "CLAUDSOUL_REPO=$d"; }
green_D1209() { local d; d=$(mkfix D1209); mkdir -p "$d/hooks/tests/fixtures"
    printf '%s\n' '#!/usr/bin/env bash' 'echo "источник судит реплику правилом владельца"' 'exit 0' > "$d/hooks/tests/fixtures/probe_D1209.sh"
    echo "CLAUDSOUL_REPO=$d"; }
green_D1210() { local d; d=$(mkfix D1210); mkdir -p "$d/hooks/tests/fixtures"
    printf '%s\n' '#!/usr/bin/env bash' 'echo "читатели итога на Stop судят поле входа"' 'exit 0' > "$d/hooks/tests/fixtures/probe_D1210.sh"
    echo "CLAUDSOUL_REPO=$d"; }
green_D1211() { local d; d=$(mkfix D1211); mkdir -p "$d/hooks/tests/fixtures"
    printf '%s\n' '#!/usr/bin/env bash' 'echo "напоминание о дрейфе печатает исполнимые команды"' 'exit 0' > "$d/hooks/tests/fixtures/probe_D1211.sh"
    echo "CLAUDSOUL_REPO=$d"; }
green_D1212() { local d; d=$(mkfix D1212); mkdir -p "$d/hooks/tests/fixtures"
    printf '%s\n' '#!/usr/bin/env bash' 'echo "переход внутри подстановки засчитан"' 'exit 0' > "$d/hooks/tests/fixtures/probe_D1212.sh"
    echo "CLAUDSOUL_REPO=$d"; }
green_D1213() { local d; d=$(mkfix D1213); mkdir -p "$d/hooks/tests/fixtures"
    printf '%s\n' '#!/usr/bin/env bash' 'echo "архивный пункт назван архивным, совет исполним"' 'exit 0' > "$d/hooks/tests/fixtures/probe_D1213.sh"
    echo "CLAUDSOUL_REPO=$d"; }
green_D1214() { local d; d=$(mkfix D1214); mkdir -p "$d/hooks/tests/fixtures"
    printf '%s\n' '#!/usr/bin/env bash' 'echo "стоячий повод не назван причиной отказа"' 'exit 0' > "$d/hooks/tests/fixtures/probe_D1214.sh"
    echo "CLAUDSOUL_REPO=$d"; }
green_D1215() { local d; d=$(mkfix D1215); mkdir -p "$d/hooks/tests/fixtures"
    printf '%s\n' '#!/usr/bin/env bash' 'echo "формы записи вне перечня отбиваются"' 'exit 0' > "$d/hooks/tests/fixtures/probe_D1215.sh"
    echo "CLAUDSOUL_REPO=$d"; }
green_D1216() { local d; d=$(mkfix D1216); mkdir -p "$d/hooks/tests/fixtures"
    printf '%s\n' '#!/usr/bin/env bash' 'echo "присваивания — по общему лексеру"' 'exit 0' > "$d/hooks/tests/fixtures/probe_D1216.sh"
    echo "CLAUDSOUL_REPO=$d"; }
green_D1217() { local d; d=$(mkfix D1217); mkdir -p "$d/hooks/tests/fixtures"
    printf '%s\n' '#!/usr/bin/env bash' 'echo "конец подстановки — мимо комментария и heredoc"' 'exit 0' > "$d/hooks/tests/fixtures/probe_D1217.sh"
    echo "CLAUDSOUL_REPO=$d"; }
green_D1218() { local d; d=$(mkfix D1218); mkdir -p "$d/hooks/tests/fixtures"
    printf '%s\n' '#!/usr/bin/env bash' 'echo "набор под командой замера судит бегуна замеров"' 'exit 0' > "$d/hooks/tests/fixtures/probe_D1218.sh"
    echo "CLAUDSOUL_REPO=$d"; }
# Зелёная сторона D1219 — ДЕРЕВО, чья проба видит немой подготовительный вызов и после `X=…;` в той же строке.
green_D1219() { local d; d=$(mkfix D1219); mkdir -p "$d/hooks/tests/fixtures"
    printf '%s\n' '#!/usr/bin/env bash' 'echo "немых вызовов после присваивания в свидетелях нет"' 'exit 0' > "$d/hooks/tests/fixtures/probe_D1219.sh"
    echo "CLAUDSOUL_REPO=$d"; }
# Зелёная сторона D1220 — ДЕРЕВО, чей замер отказов судит `$VAR/…` по раскрытому пути, а не по расширению.
green_D1220() { local d; d=$(mkfix D1220); mkdir -p "$d/hooks/tests/fixtures"
    printf '%s\n' '#!/usr/bin/env bash' 'echo "один каталог — один класс при цели через переменную"' 'exit 0' > "$d/hooks/tests/fixtures/probe_D1220.sh"
    echo "CLAUDSOUL_REPO=$d"; }
# Зелёная сторона D1221 — ДЕРЕВО, чей гейт различает в составе напоминания пункты вне D-нумерации.
green_D1221() { local d; d=$(mkfix D1221); mkdir -p "$d/hooks/tests/fixtures"
    printf '%s\n' '#!/usr/bin/env bash' 'echo "составы о B541 и B542 различны"' 'exit 0' > "$d/hooks/tests/fixtures/probe_D1221.sh"
    echo "CLAUDSOUL_REPO=$d"; }
# Зелёная сторона D1222 — ДЕРЕВО, чей корпус свидетелей судим целиком: вердикт у каждого разрешимого, ложно-зелёных нет.
green_D1222() { local d; d=$(mkfix D1222); mkdir -p "$d/hooks/tests/fixtures"
    printf '%s\n' '#!/usr/bin/env bash' 'echo "judged = resolved, vacuous = 0"' 'exit 0' > "$d/hooks/tests/fixtures/probe_D1222.sh"
    echo "CLAUDSOUL_REPO=$d"; }
# Зелёная сторона D1223 — ДЕРЕВО, чьи писатели README кладут одно число хуков в обе строки.
green_D1223() { local d; d=$(mkfix D1223); mkdir -p "$d/hooks/tests/fixtures"
    printf '%s\n' '#!/usr/bin/env bash' 'echo "обе строки README — одно число хуков"' 'exit 0' > "$d/hooks/tests/fixtures/probe_D1223.sh"
    echo "CLAUDSOUL_REPO=$d"; }
# Зелёная сторона D1224 — ДЕРЕВО, чей враждебный свидетель, снятый по сроку, не оставляет фикстуры в HOME.
green_D1224() { local d; d=$(mkfix D1224); mkdir -p "$d/hooks/tests/fixtures"
    printf '%s\n' '#!/usr/bin/env bash' 'echo "убитый свидетель не оставил каталога в HOME"' 'exit 0' > "$d/hooks/tests/fixtures/probe_D1224.sh"
    echo "CLAUDSOUL_REPO=$d"; }
# Зелёная сторона D1225 — ДЕРЕВО, где каталог состояния под порогом при нынешних писателях.
green_D1225() { local d; d=$(mkfix D1225); mkdir -p "$d/hooks/tests/fixtures"
    printf '%s\n' '#!/usr/bin/env bash' 'echo "каталог состояния под порогом"' 'exit 0' > "$d/hooks/tests/fixtures/probe_D1225.sh"
    echo "CLAUDSOUL_REPO=$d"; }
# Зелёная сторона D1226 — ДЕРЕВО, где у сверяемого инструмента есть свидетель, красный на заглушке.
green_D1226() { local d; d=$(mkfix D1226); mkdir -p "$d/hooks/tests/fixtures"
    printf '%s\n' '#!/usr/bin/env bash' 'echo "guard-edition-exposures измерен"' 'exit 0' > "$d/hooks/tests/fixtures/probe_D1226.sh"
    echo "CLAUDSOUL_REPO=$d"; }
# Зелёная сторона D1227 — ДЕРЕВО, где признак рода H не называет личные пути и фикстуры.
green_D1227() { local d; d=$(mkfix D1227); mkdir -p "$d/hooks/tests/fixtures"
    printf '%s\n' '#!/usr/bin/env bash' 'echo "ложных носителей рода H нет"' 'exit 0' > "$d/hooks/tests/fixtures/probe_D1227.sh"
    echo "CLAUDSOUL_REPO=$d"; }
# Зелёная сторона D1228 — ДЕРЕВО, где сверщик читателей разрешает путь через вызов владельца пути.
green_D1228() { local d; d=$(mkfix D1228); mkdir -p "$d/hooks/tests/fixtures"
    printf '%s\n' '#!/usr/bin/env bash' 'echo "читатели сверены"' 'exit 0' > "$d/hooks/tests/fixtures/probe_D1228.sh"
    echo "CLAUDSOUL_REPO=$d"; }
# Зелёная сторона D1229 — ДЕРЕВО, где у журналов есть читатель, проба R2 не слепа к маске.
green_D1229() { local d; d=$(mkfix D1229); mkdir -p "$d/hooks/tests/fixtures"
    printf '%s\n' '#!/usr/bin/env bash' 'echo "журналов без читателя нет"' 'exit 0' > "$d/hooks/tests/fixtures/probe_D1229.sh"
    echo "CLAUDSOUL_REPO=$d"; }
# Зелёная сторона D1230 — ДЕРЕВО, где граф называет спайкой только достижимую рекурсию.
green_D1230() { local d; d=$(mkfix D1230); mkdir -p "$d/hooks/tests/fixtures"
    printf '%s\n' '#!/usr/bin/env bash' 'echo "ложных спаек нет"' 'exit 0' > "$d/hooks/tests/fixtures/probe_D1230.sh"
    echo "CLAUDSOUL_REPO=$d"; }
# Зелёная сторона D1231 — ДЕРЕВО, где свидетель гейта не краснеет от цены живых «Проверок».
green_D1231() { local d; d=$(mkfix D1231); mkdir -p "$d/hooks/tests/fixtures"
    printf '%s\n' '#!/usr/bin/env bash' 'echo "свидетель гейта судит фикстуру"' 'exit 0' > "$d/hooks/tests/fixtures/probe_D1231.sh"
    echo "CLAUDSOUL_REPO=$d"; }
# Зелёная сторона D1232 — ДЕРЕВО, где у дорогих тестов есть оправдание либо цена снижена.
green_D1232() { local d; d=$(mkfix D1232); mkdir -p "$d/hooks/tests/fixtures"
    printf '%s\n' '#!/usr/bin/env bash' 'echo "дорогих без оправдания нет"' 'exit 0' > "$d/hooks/tests/fixtures/probe_D1232.sh"
    echo "CLAUDSOUL_REPO=$d"; }
# Зелёная сторона D1233 — ДЕРЕВО, где прогон набора в контейнере зелен либо падения названы.
green_D1233() { local d; d=$(mkfix D1233); mkdir -p "$d/hooks/tests/fixtures"
    printf '%s\n' '#!/usr/bin/env bash' 'echo "контейнер зелен"' 'exit 0' > "$d/hooks/tests/fixtures/probe_D1233.sh"
    echo "CLAUDSOUL_REPO=$d"; }
# Зелёная сторона D1234 — ДЕРЕВО, где стенное время активатора мерит строка реестра.
green_D1234() { local d; d=$(mkfix D1234); mkdir -p "$d/hooks/tests/fixtures"
    printf '%s\n' '#!/usr/bin/env bash' 'echo "время активатора мерится"' 'exit 0' > "$d/hooks/tests/fixtures/probe_D1234.sh"
    echo "CLAUDSOUL_REPO=$d"; }
# Зелёная сторона D1235 — ДЕРЕВО, где синхронные хуки Stop укладываются в 10 с.
green_D1235() { local d; d=$(mkfix D1235); mkdir -p "$d/hooks/tests/fixtures"
    printf '%s\n' '#!/usr/bin/env bash' 'echo "хуки Stop укладываются в 10 с"' 'exit 0' > "$d/hooks/tests/fixtures/probe_D1235.sh"
    echo "CLAUDSOUL_REPO=$d"; }
# Зелёная сторона D1236 — ДЕРЕВО, где дроби карты корней сходятся с командами.
green_D1236() { local d; d=$(mkfix D1236); mkdir -p "$d/hooks/tests/fixtures"
    printf '%s\n' '#!/usr/bin/env bash' 'echo "дроби R1–R3 сходятся"' 'exit 0' > "$d/hooks/tests/fixtures/probe_D1236.sh"
    echo "CLAUDSOUL_REPO=$d"; }
# Зелёная сторона D1237 — ДЕРЕВО, чей замер харнесса показывает вывод сессии на пустом журнале пробы.
green_D1237() { local d; d=$(mkfix D1237); mkdir -p "$d/hooks/tests/fixtures"
    printf '%s\n' '#!/usr/bin/env bash' 'echo "вывод сессии показан"' 'exit 0' > "$d/hooks/tests/fixtures/probe_D1237.sh"
    echo "CLAUDSOUL_REPO=$d"; }
# Зелёная сторона D1238 — ДЕРЕВО, где питонские исполнители судят кольцо правилом владельца, а не своей копией.
green_D1238() { local d; d=$(mkfix D1238); mkdir -p "$d/hooks/tests/fixtures"
    printf '%s\n' '#!/usr/bin/env bash' 'echo "ограда кольца — правило владельца"' 'exit 0' > "$d/hooks/tests/fixtures/probe_D1238.sh"
    echo "CLAUDSOUL_REPO=$d"; }
# Зелёная сторона D1239 — ДЕРЕВО, где пробы корней и источники чисел снимаются по сроку вместе с потомками.
green_D1239() { local d; d=$(mkfix D1239); mkdir -p "$d/hooks/tests/fixtures"
    printf '%s\n' '#!/usr/bin/env bash' 'echo "пробы снимаются по сроку с потомками"' 'exit 0' > "$d/hooks/tests/fixtures/probe_D1239.sh"
    echo "CLAUDSOUL_REPO=$d"; }
# Зелёная сторона D1240 — ДЕРЕВО, где сканеры дерева видят и новый, ещё не добавленный в git файл.
green_D1240() { local d; d=$(mkfix D1240); mkdir -p "$d/hooks/tests/fixtures"
    printf '%s\n' '#!/usr/bin/env bash' 'echo "новый файл виден сканеру"' 'exit 0' > "$d/hooks/tests/fixtures/probe_D1240.sh"
    echo "CLAUDSOUL_REPO=$d"; }
# Зелёная сторона D1242 — ДЕРЕВО, где семь красных живого прогона архива разобраны (проба D1242 зелёная).
green_D1242() { local d; d=$(mkfix D1242); mkdir -p "$d/hooks/tests/fixtures"
    printf '%s\n' '#!/usr/bin/env bash' 'echo "семь красных архива разобраны"' 'exit 0' > "$d/hooks/tests/fixtures/probe_D1242.sh"
    echo "CLAUDSOUL_REPO=$d"; }
green_D1243() { local d; d=$(mkfix D1243); mkdir -p "$d/hooks/tests/fixtures"
    printf '%s\n' '#!/usr/bin/env bash' 'echo "отказ называет открытый повод и не называет снятый"' 'exit 0' > "$d/hooks/tests/fixtures/probe_D1243.sh"
    echo "CLAUDSOUL_REPO=$d"; }
green_D1244() { local d; d=$(mkfix D1244); mkdir -p "$d/hooks/tests/fixtures"
    printf '%s\n' '#!/usr/bin/env bash' 'echo "вызов из подкаталога снимка не стирает"' 'exit 0' > "$d/hooks/tests/fixtures/probe_D1244.sh"
    echo "CLAUDSOUL_REPO=$d"; }
green_D1245() { local d; d=$(mkfix D1245); mkdir -p "$d/hooks/tests/fixtures"
    printf '%s\n' '#!/usr/bin/env bash' 'echo "короткие поручения признаны авторизацией"' 'exit 0' > "$d/hooks/tests/fixtures/probe_D1245.sh"
    echo "CLAUDSOUL_REPO=$d"; }
green_D1246() { local d; d=$(mkfix D1246); mkdir -p "$d/hooks/tests/fixtures"
    printf '%s\n' '#!/usr/bin/env bash' 'echo "отказ воркера соответствия назван кодом"' 'exit 0' > "$d/hooks/tests/fixtures/probe_D1246.sh"
    echo "CLAUDSOUL_REPO=$d"; }
green_D1247() { local d; d=$(mkfix D1247); mkdir -p "$d/hooks/tests/fixtures"
    printf '%s\n' '#!/usr/bin/env bash' 'echo "ход побудки авторизацию не взводит"' 'exit 0' > "$d/hooks/tests/fixtures/probe_D1247.sh"
    echo "CLAUDSOUL_REPO=$d"; }
green_D1248() { local d; d=$(mkfix D1248); mkdir -p "$d/hooks/tests/fixtures"
    printf '%s\n' '#!/usr/bin/env bash' 'echo "служебный ход модель собеседника не двигает"' 'exit 0' > "$d/hooks/tests/fixtures/probe_D1248.sh"
    echo "CLAUDSOUL_REPO=$d"; }
green_D1249() { local d; d=$(mkfix D1249); mkdir -p "$d/hooks/tests/fixtures"
    printf '%s\n' '#!/usr/bin/env bash' 'echo "задетые правкой «Проверки» архива названы до коммита"' 'exit 0' > "$d/hooks/tests/fixtures/probe_D1249.sh"
    echo "CLAUDSOUL_REPO=$d"; }
green_D1250() { local d; d=$(mkfix D1250); mkdir -p "$d/hooks/tests/fixtures"
    printf '%s\n' '#!/usr/bin/env bash' 'echo "фоновый свод судит ход, закончившийся на своём Stop"' 'exit 0' > "$d/hooks/tests/fixtures/probe_D1250.sh"
    echo "CLAUDSOUL_REPO=$d"; }
green_D1251() { local d; d=$(mkfix D1251); mkdir -p "$d/hooks/tests/fixtures"
    printf '%s\n' '#!/usr/bin/env bash' 'echo "уехавшие адреса строк названы до коммита"' 'exit 0' > "$d/hooks/tests/fixtures/probe_D1251.sh"
    echo "CLAUDSOUL_REPO=$d"; }
green_D1252() { local d; d=$(mkfix D1252); mkdir -p "$d/hooks/tests/fixtures"
    printf '%s\n' '#!/usr/bin/env bash' 'echo "описание подстановки в кавычках сверено вызовом"' 'exit 0' > "$d/hooks/tests/fixtures/probe_D1252.sh"
    echo "CLAUDSOUL_REPO=$d"; }
green_D1253() { local d; d=$(mkfix D1253); mkdir -p "$d/hooks/tests/fixtures"
    printf '%s\n' '#!/usr/bin/env bash' 'echo "запуск внутри кавыченной подстановки найден"' 'exit 0' > "$d/hooks/tests/fixtures/probe_D1253.sh"
    echo "CLAUDSOUL_REPO=$d"; }
green_D1254() { local d; d=$(mkfix D1254); mkdir -p "$d/hooks/tests/fixtures"
    printf '%s\n' '#!/usr/bin/env bash' 'echo "решётка в обратной кавычке не прячет команду"' 'exit 0' > "$d/hooks/tests/fixtures/probe_D1254.sh"
    echo "CLAUDSOUL_REPO=$d"; }
green_D1255() { local d; d=$(mkfix D1255); mkdir -p "$d/hooks/tests/fixtures"
    printf '%s\n' '#!/usr/bin/env bash' 'echo "перенос в архив не отзывает свежий исход"' 'exit 0' > "$d/hooks/tests/fixtures/probe_D1255.sh"
    echo "CLAUDSOUL_REPO=$d"; }
green_D1256() { local d; d=$(mkfix D1256); mkdir -p "$d/hooks/tests/fixtures"
    printf '%s\n' '#!/usr/bin/env bash' 'echo "свод не зовёт исхода стоячим поводам"' 'exit 0' > "$d/hooks/tests/fixtures/probe_D1256.sh"
    echo "CLAUDSOUL_REPO=$d"; }
green_D1257() { local d; d=$(mkfix D1257); mkdir -p "$d/hooks/tests/fixtures"
    printf '%s\n' '#!/usr/bin/env bash' 'echo "T4a сравнивает отметку со своей же"' 'exit 0' > "$d/hooks/tests/fixtures/probe_D1257.sh"
    echo "CLAUDSOUL_REPO=$d"; }
green_D1258() { local d; d=$(mkfix D1258); mkdir -p "$d/hooks/tests/fixtures"
    printf '%s\n' '#!/usr/bin/env bash' 'echo "предел снят либо описывает нынешний мир"' 'exit 0' > "$d/hooks/tests/fixtures/probe_D1258.sh"
    echo "CLAUDSOUL_REPO=$d"; }
green_D1259() { local d; d=$(mkfix D1259); mkdir -p "$d/hooks/tests/fixtures"
    printf '%s\n' '#!/usr/bin/env bash' 'echo "подсказка судит свой предмет"' 'exit 0' > "$d/hooks/tests/fixtures/probe_D1259.sh"
    echo "CLAUDSOUL_REPO=$d"; }
green_D1260() { local d; d=$(mkfix D1260); mkdir -p "$d/hooks/tests/fixtures"
    printf '%s\n' '#!/usr/bin/env bash' 'echo "три формы лексера — данные, а не команды"' 'exit 0' > "$d/hooks/tests/fixtures/probe_D1260.sh"
    echo "CLAUDSOUL_REPO=$d"; }
green_D1261() { local d; d=$(mkfix D1261); mkdir -p "$d/hooks/tests/fixtures"
    printf '%s\n' '#!/usr/bin/env bash' 'echo "вызов за префиксом-присваиванием судится"' 'exit 0' > "$d/hooks/tests/fixtures/probe_D1261.sh"
    echo "CLAUDSOUL_REPO=$d"; }
green_D1262() { local d; d=$(mkfix D1262); mkdir -p "$d/hooks/tests/fixtures"
    printf '%s\n' '#!/usr/bin/env bash' 'echo "хвост списка судится своей командой"' 'exit 0' > "$d/hooks/tests/fixtures/probe_D1262.sh"
    echo "CLAUDSOUL_REPO=$d"; }
green_D1263() { local d; d=$(mkfix D1263); mkdir -p "$d/hooks/tests/fixtures"
    printf '%s\n' '#!/usr/bin/env bash' 'echo "выключенная уборка бэклога проекта названа"' 'exit 0' > "$d/hooks/tests/fixtures/probe_D1263.sh"
    echo "CLAUDSOUL_REPO=$d"; }
green_D1264() { local d; d=$(mkfix D1264); mkdir -p "$d/hooks/tests/fixtures"
    printf '%s\n' '#!/usr/bin/env bash' 'echo "обращение к члену не даёт ребра к имени верхнего уровня"' 'exit 0' > "$d/hooks/tests/fixtures/probe_D1264.sh"
    echo "CLAUDSOUL_REPO=$d"; }
green_D1265() { local d; d=$(mkfix D1265); mkdir -p "$d/hooks/tests/fixtures"
    printf '%s\n' '#!/usr/bin/env bash' 'echo "тест судится описанием проекта"' 'exit 0' > "$d/hooks/tests/fixtures/probe_D1265.sh"
    echo "CLAUDSOUL_REPO=$d"; }
green_D1269() { local d; d=$(mkfix D1269); mkdir -p "$d/hooks/tests/fixtures"
    printf '%s\n' '#!/usr/bin/env bash' 'echo "ранг отбора разложен по коммитам"' 'exit 0' > "$d/hooks/tests/fixtures/probe_D1269.sh"
    echo "CLAUDSOUL_REPO=$d"; }
green_D1270() { local d; d=$(mkfix D1270); mkdir -p "$d/hooks/tests/fixtures"
    printf '%s\n' '#!/usr/bin/env bash' 'echo "сверка карты называет непосчитанный корень"' 'exit 0' > "$d/hooks/tests/fixtures/probe_D1270.sh"
    echo "CLAUDSOUL_REPO=$d"; }
# Зелёная сторона D1273 — ДЕРЕВО, где у знаний с пятью подтверждениями есть признак либо вердикт.
green_D1273() { local d; d=$(mkfix D1273); mkdir -p "$d/hooks/tests/fixtures"
    printf '%s\n' '#!/usr/bin/env bash' 'echo "у знаний с пятью подтверждениями есть признак либо вердикт"' 'exit 0' > "$d/hooks/tests/fixtures/probe_D1273.sh"
    echo "CLAUDSOUL_REPO=$d"; }
# Зелёные стороны D1274 и D1275 — ДЕРЕВО, где проба закрытого пункта (D1225, D1232), чей откат они называют, зелёна.
green_D1274() { local d; d=$(mkfix D1274); mkdir -p "$d/hooks/tests/fixtures"
    printf '%s\n' '#!/usr/bin/env bash' 'echo "после уборки каталог состояния под порогами"' 'exit 0' > "$d/hooks/tests/fixtures/probe_D1225.sh"
    echo "CLAUDSOUL_REPO=$d"; }
# Зелёная сторона D1275 снята 21 ноября 2026 вместе с закрытием пункта: её место заняли показание и проба
# `probe_D1232.sh` на замере в покое.
green_D1276() { local d; d=$(mkfix D1276); mkdir -p "$d/hooks/tests/fixtures"
    printf '%s\n' '#!/usr/bin/env bash' 'echo "срок пробы корня растёт с нагрузкой"' 'exit 0' > "$d/hooks/tests/fixtures/probe_D1276.sh"
    echo "CLAUDSOUL_REPO=$d"; }
green_D1277() { local d; d=$(mkfix D1277); mkdir -p "$d/hooks/tests/fixtures"
    printf '%s\n' '#!/usr/bin/env bash' 'echo "запись в подстановке в кавычках видна"' 'exit 0' > "$d/hooks/tests/fixtures/probe_D1277.sh"
    echo "CLAUDSOUL_REPO=$d"; }
green_D1278() { local d; d=$(mkfix D1278); mkdir -p "$d/hooks/tests/fixtures"
    printf '%s\n' '#!/usr/bin/env bash' 'echo "коммит в другой репозиторий индекс сессии не трогает"' 'exit 0' > "$d/hooks/tests/fixtures/probe_D1278.sh"
    echo "CLAUDSOUL_REPO=$d"; }
green_D1279() { local d; d=$(mkfix D1279); mkdir -p "$d/hooks/tests/fixtures"
    printf '%s\n' '#!/usr/bin/env bash' 'echo "коммит в другой репозиторий судится там, куда идёт"' 'exit 0' > "$d/hooks/tests/fixtures/probe_D1279.sh"
    echo "CLAUDSOUL_REPO=$d"; }
green_D1280() { local d; d=$(mkfix D1280); mkdir -p "$d/hooks/tests/fixtures"
    printf '%s\n' '#!/usr/bin/env bash' 'echo "цель из обратных кавычек литеральной не считается"' 'exit 0' > "$d/hooks/tests/fixtures/probe_D1280.sh"
    echo "CLAUDSOUL_REPO=$d"; }
green_D1281() { local d; d=$(mkfix D1281); mkdir -p "$d/hooks/tests/fixtures"
    printf '%s\n' '#!/usr/bin/env bash' 'echo "правка разбора выбирает тест стража, зависящего через библиотеку"' 'exit 0' > "$d/hooks/tests/fixtures/probe_D1281.sh"
    echo "CLAUDSOUL_REPO=$d"; }
green_D1282() { local d; d=$(mkfix D1282); mkdir -p "$d/hooks/tests/fixtures"
    printf '%s\n' '#!/usr/bin/env bash' 'echo "пять стражей судят репозиторий, куда идёт коммит"' 'exit 0' > "$d/hooks/tests/fixtures/probe_D1282.sh"
    echo "CLAUDSOUL_REPO=$d"; }
# Зелёная сторона D1289 — ДЕРЕВО, где пакет правок одного файла судится как одна правка.
green_D1289() { local d; d=$(mkfix D1289); mkdir -p "$d/hooks/tests/fixtures"
    printf '%s\n' '#!/usr/bin/env bash' 'echo "пакет правок применён целиком"' 'exit 0' > "$d/hooks/tests/fixtures/probe_D1289.sh"
    echo "CLAUDSOUL_REPO=$d"; }
# Зелёная сторона D1292 — ДЕРЕВО, где исход не ложится на повод, закрытый в прошлом ходе.
green_D1292() { local d; d=$(mkfix D1292); mkdir -p "$d/hooks/tests/fixtures"
    printf '%s\n' '#!/usr/bin/env bash' 'echo "исход ложится только на поводы без исхода"' 'exit 0' > "$d/hooks/tests/fixtures/probe_D1292.sh"
    echo "CLAUDSOUL_REPO=$d"; }
# Зелёная сторона D1293 — ДЕРЕВО, где новая полоса той же длины — новый повод.
green_D1293() { local d; d=$(mkfix D1293); mkdir -p "$d/hooks/tests/fixtures"
    printf '%s\n' '#!/usr/bin/env bash' 'echo "новая полоса той же длины — новый повод"' 'exit 0' > "$d/hooks/tests/fixtures/probe_D1293.sh"
    echo "CLAUDSOUL_REPO=$d"; }
# Зелёная сторона D1298 — ДЕРЕВО, где прибор знаний печатает очередь, и знания об условии коммита в ней нет.
green_D1298() { local d; d=$(mkfix D1298); mkdir -p "$d/scripts"
    printf '%s\n' '#!/usr/bin/env bash' 'printf "## Очередь на производство\n\n| 0 | 9 | 0 дн. | pattern-other | о другом |\n\n## Оценены\n" > "$KIA_OUTPUT"' 'exit 0' > "$d/scripts/knowledge-instrument-audit.sh"
    echo "CLAUDSOUL_REPO=$d"; }
# Зелёная сторона D1305 — ДЕРЕВО, где свидетель «находка скептика закрывается с проверяемым происхождением» есть и зелен.
green_D1305() { local d; d=$(mkfix D1305); mkdir -p "$d/hooks/tests"
    printf '%s\n' '#!/usr/bin/env bash' 'echo "без происхождения ☑ отбит"' 'exit 0' > "$d/hooks/tests/test_skeptic_finding_needs_origin.sh"
    echo "CLAUDSOUL_REPO=$d"; }
# Зелёная сторона D1304 — ДЕРЕВО, где свидетель «сообщение доходит до своей сессии» есть и зелен.
green_D1304() { local d; d=$(mkfix D1304); mkdir -p "$d/hooks/tests"
    printf '%s\n' '#!/usr/bin/env bash' 'echo "чужая сессия сообщения не видит"' 'exit 0' > "$d/hooks/tests/test_alerts_reach_their_addressee.sh"
    echo "CLAUDSOUL_REPO=$d"; }
# Зелёная сторона D1354 — ДЕРЕВО, где проба «возобновлённый помощник, сдавший отчёт, тревоги об обрыве не даёт» отвечает 0.
green_D1354() { local d; d=$(mkfix D1354); mkdir -p "$d/hooks/tests/fixtures"
    printf '%s\n' '#!/usr/bin/env bash' 'echo "сдавший отчёт после возобновления оборвавшимся не назван"' 'exit 0' > "$d/hooks/tests/fixtures/probe_D1354.sh"
    echo "CLAUDSOUL_REPO=$d"; }
# Зелёная сторона D1353 — ДЕРЕВО, где проба «тест стартовой подсказки не пишет в файл сквозной линии каталога запуска» отвечает 0.
# Зелёная сторона D1355 — ДЕРЕВО, где проба «docker на другой машине — замер мерит потоком» отвечает 0.
green_D1355() { local d; d=$(mkfix D1355); mkdir -p "$d/hooks/tests/fixtures"
    printf '%s\n' '#!/usr/bin/env bash' 'echo "docker на другой машине: дерево ушло потоком"' 'exit 0' > "$d/hooks/tests/fixtures/probe_D1355.sh"
    echo "CLAUDSOUL_REPO=$d"; }
# Зелёная сторона D1356 — ДЕРЕВО, где проба «правка упавшей спеки до чтения снимка отказана, после чтения — пропущена» отвечает 0.
green_D1356() { local d; d=$(mkfix D1356); mkdir -p "$d/hooks/tests/fixtures"
    printf '%s\n' '#!/usr/bin/env bash' 'echo "правка спеки до чтения снимка отказана, после чтения пропущена"' 'exit 0' > "$d/hooks/tests/fixtures/probe_D1356.sh"
    echo "CLAUDSOUL_REPO=$d"; }
# Зелёная сторона D1357 — ДЕРЕВО, где проба «повод, закрытый разбором в прошлом ходе, напоминания «исхода не видно» не даёт» отвечает 0.
green_D1357() { local d; d=$(mkfix D1357); mkdir -p "$d/hooks/tests/fixtures"
    printf '%s\n' '#!/usr/bin/env bash' 'echo "закрытый в прошлом ходе повод напоминания не дал"' 'exit 0' > "$d/hooks/tests/fixtures/probe_D1357.sh"
    echo "CLAUDSOUL_REPO=$d"; }
# Зелёная сторона D1360 — ДЕРЕВО, где проба «повод, закрытый сверенной строкой manual-, напоминания не даёт» отвечает 0.
green_D1360() { local d; d=$(mkfix D1360); mkdir -p "$d/hooks/tests/fixtures"
    printf '%s\n' '#!/usr/bin/env bash' 'echo "закрытый строкой manual- повод напоминания не дал"' 'exit 0' > "$d/hooks/tests/fixtures/probe_D1360.sh"
    echo "CLAUDSOUL_REPO=$d"; }
# Зелёная сторона D1366 — ДЕРЕВО, где проба «„Проверки“ с песочницей держатся в рамке сверщика» отвечает 0.
green_D1366() { local d; d=$(mkfix D1366); mkdir -p "$d/hooks/tests/fixtures"
    printf '%s\n' '#!/usr/bin/env bash' 'echo "«Проверки» с песочницей держатся в рамке сверщика"' 'exit 0' > "$d/hooks/tests/fixtures/probe_D1366.sh"
    echo "CLAUDSOUL_REPO=$d"; }
# Зелёная сторона D1365 — ДЕРЕВО, где проба «гейт истории: имя знания не секрет, ключ — находка» отвечает 0.
green_D1365() { local d; d=$(mkfix D1365); mkdir -p "$d/hooks/tests/fixtures"
    printf '%s\n' '#!/usr/bin/env bash' 'echo "гейт истории: имя знания не секрет, ключ — находка"' 'exit 0' > "$d/hooks/tests/fixtures/probe_D1365.sh"
    echo "CLAUDSOUL_REPO=$d"; }
# Зелёная сторона D1364 — ДЕРЕВО, где проба «три свидетеля зелены в рамке открытого снимка» отвечает 0.
green_D1364() { local d; d=$(mkfix D1364); mkdir -p "$d/hooks/tests/fixtures"
    printf '%s\n' '#!/usr/bin/env bash' 'echo "три свидетеля зелены в рамке открытого снимка"' 'exit 0' > "$d/hooks/tests/fixtures/probe_D1364.sh"
    echo "CLAUDSOUL_REPO=$d"; }
# Зелёная сторона D1363 — ДЕРЕВО, где проба «образцы в тестах гейт открытого снимка пропускает» отвечает 0.
green_D1363() { local d; d=$(mkfix D1363); mkdir -p "$d/hooks/tests/fixtures"
    printf '%s\n' '#!/usr/bin/env bash' 'echo "образцы в тестах гейт снимка пропускает"' 'exit 0' > "$d/hooks/tests/fixtures/probe_D1363.sh"
    echo "CLAUDSOUL_REPO=$d"; }
# Зелёная сторона D1362 — ДЕРЕВО, где проба «адрес сети Tailscale не едет в открытый снимок» отвечает 0.
green_D1362() { local d; d=$(mkfix D1362); mkdir -p "$d/hooks/tests/fixtures"
    printf '%s\n' '#!/usr/bin/env bash' 'echo "дерево чисто, перечень гейта ловит адрес сети Tailscale"' 'exit 0' > "$d/hooks/tests/fixtures/probe_D1362.sh"
    echo "CLAUDSOUL_REPO=$d"; }
# Зелёная сторона D1361 — ДЕРЕВО, где проба D1319 «сверка отвечает на тексте больше 128 КБ в рамке Linux» отвечает 0.
green_D1361() { local d; d=$(mkfix D1361); mkdir -p "$d/hooks/tests/fixtures"
    printf '%s\n' '#!/usr/bin/env bash' 'echo "строка найдена и в большом тексте"' 'exit 0' > "$d/hooks/tests/fixtures/probe_D1319.sh"
    echo "CLAUDSOUL_REPO=$d"; }
# Зелёная сторона D1359 — ДЕРЕВО, где проба «обрезанный хвостом отчёт судится по error-context.md на диске» отвечает 0.
green_D1359() { local d; d=$(mkfix D1359); mkdir -p "$d/hooks/tests/fixtures"
    printf '%s\n' '#!/usr/bin/env bash' 'echo "обрезанный хвостом отчёт судится по снимку на диске"' 'exit 0' > "$d/hooks/tests/fixtures/probe_D1359.sh"
    echo "CLAUDSOUL_REPO=$d"; }
# Зелёная сторона D1358 — ДЕРЕВО, где проба «снимок «в файле» и обрезанный печатью не прочитаны» отвечает 0.
green_D1358() { local d; d=$(mkfix D1358); mkdir -p "$d/hooks/tests/fixtures"
    printf '%s\n' '#!/usr/bin/env bash' 'echo "снимок в файле и обрезанный печатью прочитанными не считаются"' 'exit 0' > "$d/hooks/tests/fixtures/probe_D1358.sh"
    echo "CLAUDSOUL_REPO=$d"; }
green_D1353() { local d; d=$(mkfix D1353); mkdir -p "$d/hooks/tests/fixtures"
    printf '%s\n' '#!/usr/bin/env bash' 'echo "файл сквозной линии каталога запуска не тронут"' 'exit 0' > "$d/hooks/tests/fixtures/probe_D1353.sh"
    echo "CLAUDSOUL_REPO=$d"; }
# Зелёная сторона D1303 — ДЕРЕВО, где проба «повод переработки правдив хотя бы в половине случаев» отвечает 0.
green_D1303() { local d; d=$(mkfix D1303); mkdir -p "$d/hooks/tests/fixtures"
    printf '%s\n' '#!/usr/bin/env bash' 'echo "«показалось» у переработки ниже половины"' 'exit 0' > "$d/hooks/tests/fixtures/probe_D1303.sh"
    echo "CLAUDSOUL_REPO=$d"; }
# Зелёная сторона D1302 — ДЕРЕВО, где свидетель «отказ на `timeout` спрашивает машину» есть и зелен.
green_D1302() { local d; d=$(mkfix D1302); mkdir -p "$d/hooks/tests"
    printf '%s\n' '#!/usr/bin/env bash' 'echo "отказ на timeout только там, где его нет"' 'exit 0' > "$d/hooks/tests/test_shell_portability_timeout_asks_machine.sh"
    echo "CLAUDSOUL_REPO=$d"; }
# Зелёная сторона D1301 (откат D1016) — ДЕРЕВО, где свидетель «части договора заводятся посреди сессии» есть и зелен.
green_D1301() { local d; d=$(mkfix D1301); mkdir -p "$d/hooks/tests"
    printf '%s\n' '#!/usr/bin/env bash' 'echo "части договора заведены в проекте, куда сессия вошла переходом"' 'exit 0' > "$d/hooks/tests/test_contract_parts_mid_session.sh"
    echo "CLAUDSOUL_REPO=$d"; }
# Зелёная сторона D1299 — ДЕРЕВО, где свидетель «правки другого исполнителя переработкой не считаются» есть и зелен.
green_D1299() { local d; d=$(mkfix D1299); mkdir -p "$d/hooks/tests"
    printf '%s\n' '#!/usr/bin/env bash' 'echo "правки фонового агента в цепочку оркестратора не легли"' 'exit 0' > "$d/hooks/tests/test_rework_detector_subagent_edits.sh"
    echo "CLAUDSOUL_REPO=$d"; }
# Зелёная сторона D1300 (откат D1225) — ДЕРЕВО, где проба D1225 зелёна (каталог состояния после уборки под порогом) и
# установленный хук подсказки связей равен репозиторному: починка действует в мире (скептик M1).
green_D1300() { local d; d=$(mkfix D1300); mkdir -p "$d/hooks/tests/fixtures" "$d/home/.claude/hooks"
    printf '%s\n' '#!/usr/bin/env bash' 'echo "после уборки под обоими порогами"' 'exit 0' > "$d/hooks/tests/fixtures/probe_D1225.sh"
    printf '%s\n' '#!/usr/bin/env bash' '# ключи строками' > "$d/hooks/impact-inject.sh"; cp "$d/hooks/impact-inject.sh" "$d/home/.claude/hooks/"
    printf '%s\n' "CLAUDSOUL_REPO=$d" "HOME=$d/home"; }
# Зелёная сторона D1297 (откат D1273) — ДЕРЕВО, где проба D1273 зелёна.
green_D1297() { local d; d=$(mkfix D1297); mkdir -p "$d/hooks/tests/fixtures"
    printf '%s\n' '#!/usr/bin/env bash' 'echo "у знаний с пятью подтверждениями есть признак либо вердикт"' 'exit 0' > "$d/hooks/tests/fixtures/probe_D1273.sh"
    echo "CLAUDSOUL_REPO=$d"; }
# Зелёная сторона D1296 — ДЕРЕВО, где скрипт выборки затронутых тестов есть, исполним и проходит свою самопроверку.
green_D1296() { local d; d=$(mkfix D1296); mkdir -p "$d/scripts"
    printf '%s\n' '#!/usr/bin/env bash' '[ "${1:-}" = --self-test ] && { echo "самопроверка: сканер и e2e-спека в наборе"; exit 0; }' 'exit 2' > "$d/scripts/affected-tests.sh"
    chmod +x "$d/scripts/affected-tests.sh"
    echo "CLAUDSOUL_REPO=$d"; }
# Зелёная сторона D1295 (откат D474) — та же «Проверка», та же фикстура: прибор судит каждого с разрешимым предметом.
green_D1295() { green_D474; }
# Зелёная сторона D1294 — ДЕРЕВО, где утверждение о строке D12 судит номер целиком.
green_D1294() { local d; d=$(mkfix D1294); mkdir -p "$d/hooks/tests/fixtures"
    printf '%s\n' '#!/usr/bin/env bash' 'echo "T3 судит номер D12 целиком"' 'exit 0' > "$d/hooks/tests/fixtures/probe_D1294.sh"
    echo "CLAUDSOUL_REPO=$d"; }
# Зелёная сторона D1291 — ДЕРЕВО, где stash/pop без правки правкой не засчитывается.
green_D1291() { local d; d=$(mkfix D1291); mkdir -p "$d/hooks/tests/fixtures"
    printf '%s\n' '#!/usr/bin/env bash' 'echo "stash и pop без правки не правка"' 'exit 0' > "$d/hooks/tests/fixtures/probe_D1291.sh"
    echo "CLAUDSOUL_REPO=$d"; }
# Зелёная сторона D1290 — ДЕРЕВО, где в разделе «уровень не помог» прибора знаний нет просроченных.
green_D1290() { local d; d=$(mkfix D1290); mkdir -p "$d/hooks/tests/fixtures"
    printf '%s\n' '#!/usr/bin/env bash' 'echo "просроченных гейтов без применения нет"' 'exit 0' > "$d/hooks/tests/fixtures/probe_D1290.sh"
    echo "CLAUDSOUL_REPO=$d"; }
# Зелёная сторона D1288 — ДЕРЕВО, где отмена коммита не засчитывается правкой нетронутого файла.
green_D1288() { local d; d=$(mkfix D1288); mkdir -p "$d/hooks/tests/fixtures"
    printf '%s\n' '#!/usr/bin/env bash' 'echo "отмена коммита правкой не засчитана"' 'exit 0' > "$d/hooks/tests/fixtures/probe_D1288.sh"
    echo "CLAUDSOUL_REPO=$d"; }
# Зелёная сторона D1287 — ДЕРЕВО, где снимок мира детектора переработки пишется и на чистом дереве.
green_D1287() { local d; d=$(mkfix D1287); mkdir -p "$d/hooks/tests/fixtures"
    printf '%s\n' '#!/usr/bin/env bash' 'echo "снимок на чистом дереве сохранён"' 'exit 0' > "$d/hooks/tests/fixtures/probe_D1287.sh"
    echo "CLAUDSOUL_REPO=$d"; }
# Зелёная сторона D1286 — ДЕРЕВО, где строки кода питона карты и учёта решает разборщик.
green_D1286() { local d; d=$(mkfix D1286); mkdir -p "$d/hooks/tests/fixtures"
    printf '%s\n' '#!/usr/bin/env bash' 'echo "код после закрывающей кавычки виден"' 'exit 0' > "$d/hooks/tests/fixtures/probe_D1286.sh"
    echo "CLAUDSOUL_REPO=$d"; }
# Зелёная сторона D1285 — ДЕРЕВО, где две редакции pad_words сверены и род K пуст.
green_D1285() { local d; d=$(mkfix D1285); mkdir -p "$d/hooks/tests/fixtures"
    printf '%s\n' '#!/usr/bin/env bash' 'echo "редакции pad_words сверены"' 'exit 0' > "$d/hooks/tests/fixtures/probe_D1285.sh"
    echo "CLAUDSOUL_REPO=$d"; }
# Зелёная сторона D1284 — ДЕРЕВО, где свидетель подсказки связей зелёный и в чистом клоне.
green_D1284() { local d; d=$(mkfix D1284); mkdir -p "$d/hooks/tests/fixtures"
    printf '%s\n' '#!/usr/bin/env bash' 'echo "свидетель зелёный и в чистом клоне"' 'exit 0' > "$d/hooks/tests/fixtures/probe_D1284.sh"
    echo "CLAUDSOUL_REPO=$d"; }
# Зелёная сторона D1283 — ДЕРЕВО, где отбор сверки архива режет пункты по той же границе, что исполнитель.
green_D1283() { local d; d=$(mkfix D1283); mkdir -p "$d/hooks/tests/fixtures"
    printf '%s\n' '#!/usr/bin/env bash' 'echo "D104 по путям старых пунктов не выбирается"' 'exit 0' > "$d/hooks/tests/fixtures/probe_D1283.sh"
    echo "CLAUDSOUL_REPO=$d"; }
# Зелёная сторона D1272 — ДЕРЕВО, где проба D1029 зелёна и запись в носитель исхода через оболочку не блокируется.
green_D1272() { local d; d=$(mkfix D1272); mkdir -p "$d/hooks/tests/fixtures"
    printf '%s\n' '#!/usr/bin/env bash' 'echo "носитель исхода пишется и через оболочку"' 'exit 0' > "$d/hooks/tests/fixtures/probe_D1272.sh"
    echo "CLAUDSOUL_REPO=$d"; }
# Зелёная сторона D1271 — ДЕРЕВО, где отказ архиватора старше суток доходит до владельца строкой «СКАЖИ».
green_D1271() { local d; d=$(mkfix D1271); mkdir -p "$d/hooks/tests/fixtures"
    printf '%s\n' '#!/usr/bin/env bash' 'echo "отказ архиватора доставлен владельцу"' 'exit 0' > "$d/hooks/tests/fixtures/probe_D1271.sh"
    echo "CLAUDSOUL_REPO=$d"; }
green_D1268() { local d; d=$(mkfix D1268); mkdir -p "$d/hooks/tests/fixtures"
    printf '%s\n' '#!/usr/bin/env bash' 'echo "фикстура детектора во временном каталоге"' 'exit 0' > "$d/hooks/tests/fixtures/probe_D1268.sh"
    echo "CLAUDSOUL_REPO=$d"; }
green_D1267() { local d; d=$(mkfix D1267); mkdir -p "$d/hooks/tests/fixtures"
    printf '%s\n' '#!/usr/bin/env bash' 'echo "точка входа видна разбору"' 'exit 0' > "$d/hooks/tests/fixtures/probe_D1267.sh"
    echo "CLAUDSOUL_REPO=$d"; }
# Зелёная сторона D1241 — ДЕРЕВО, чей тест задаёт сверщику исхода только читаемые им переменные.
green_D1241() { local d; d=$(mkfix D1241); mkdir -p "$d/hooks/tests"
    printf '%s\n' '#!/usr/bin/env bash' 'STATE_DIR="$STATE" DPR_LOCAL_BACKLOG="$BACKLOG" bash "$DPR"' 'exit 0' > "$d/hooks/tests/test_root_cause_lib.sh"
    echo "CLAUDSOUL_REPO=$d"; }
green_D1159() { local d; d=$(mkfix D1159); mkdir -p "$d/hooks/tests/fixtures"
    printf '%s\n' '#!/usr/bin/env bash' 'echo "канарейка не судит незаписанный итог"' 'exit 0' > "$d/hooks/tests/fixtures/probe_D1159.sh"
    echo "CLAUDSOUL_REPO=$d"; }
green_D1160() { local d; d=$(mkfix D1160); mkdir -p "$d/hooks/tests/fixtures"
    printf '%s\n' '#!/usr/bin/env bash' 'echo "запись, принятая за чтение, отбита"' 'exit 0' > "$d/hooks/tests/fixtures/probe_D1160.sh"
    echo "CLAUDSOUL_REPO=$d"; }
green_D1161() { local d; d=$(mkfix D1161); mkdir -p "$d/hooks/tests/fixtures"
    printf '%s\n' '#!/usr/bin/env bash' 'echo "мутанты D1105 красят пробу"' 'exit 0' > "$d/hooks/tests/fixtures/probe_D1161.sh"
    echo "CLAUDSOUL_REPO=$d"; }
green_D1162() { local d; d=$(mkfix D1162); mkdir -p "$d/hooks/tests/fixtures"
    printf '%s\n' '#!/usr/bin/env bash' 'echo "снятый xargs -r краснит запускаемый прибор"' 'exit 0' > "$d/hooks/tests/fixtures/probe_D1162.sh"
    echo "CLAUDSOUL_REPO=$d"; }
green_D1163() { local d; d=$(mkfix D1163); mkdir -p "$d/hooks/tests/fixtures"
    printf '%s\n' '#!/usr/bin/env bash' 'echo "без библиотеки текст хода не весь файл"' 'exit 0' > "$d/hooks/tests/fixtures/probe_D1163.sh"
    echo "CLAUDSOUL_REPO=$d"; }
green_D1164() { local d; d=$(mkfix D1164); mkdir -p "$d/hooks/tests/fixtures"
    printf '%s\n' '#!/usr/bin/env bash' 'echo "календарный фоллбек не зависит от часа суток"' 'exit 0' > "$d/hooks/tests/fixtures/probe_D1164.sh"
    echo "CLAUDSOUL_REPO=$d"; }
green_D1165() { local d; d=$(mkfix D1165); mkdir -p "$d/hooks/tests/fixtures"
    printf '%s\n' '#!/usr/bin/env bash' 'echo "исход в долг по новому пункту принят"' 'exit 0' > "$d/hooks/tests/fixtures/probe_D1165.sh"
    echo "CLAUDSOUL_REPO=$d"; }
green_D1166() { local d; d=$(mkfix D1166); mkdir -p "$d/hooks/tests/fixtures"
    printf '%s\n' '#!/usr/bin/env bash' 'echo "установка не оставляет новые хуки при старой библиотеке"' 'exit 0' > "$d/hooks/tests/fixtures/probe_D1166.sh"
    echo "CLAUDSOUL_REPO=$d"; }
green_D1167() { local d; d=$(mkfix D1167); mkdir -p "$d/hooks/tests/fixtures"
    printf '%s\n' '#!/usr/bin/env bash' 'echo "мутант охраны канарейки по ядру краснит пробу"' 'exit 0' > "$d/hooks/tests/fixtures/probe_D1167.sh"
    echo "CLAUDSOUL_REPO=$d"; }
green_D1180() { local d; d=$(mkfix D1180); mkdir -p "$d/hooks/tests/fixtures"
    printf '%s\n' '#!/usr/bin/env bash' 'echo "обрыв по сроку останавливает дерево «Проверки»"' 'exit 0' > "$d/hooks/tests/fixtures/probe_D1180.sh"
    echo "CLAUDSOUL_REPO=$d"; }
green_D1184() { local d; d=$(mkfix D1184); mkdir -p "$d/hooks" "$d/knowledge"
    printf '%s\n' '_ds_view() { case "$1" in live) _DS_V="" ;; shell) _DS_V="| wc -l marker-line" ;; full) _DS_V="marker-line" ;; esac; }' \
        'ds_evaluate() { echo bash_only_form_in_zsh; }' > "$d/hooks/detection-signals-lib.sh"
    : > "$d/knowledge/pattern-shell-portability.md"
    echo "CLAUDSOUL_REPO=$d"; }
# Зелёная сторона D1192 — ДЕРЕВО, чья проба классов замера зелёная: «Проверка» зовёт пробу из CLAUDSOUL_REPO.
green_D1192() { local d; d=$(mkfix D1192); mkdir -p "$d/scripts" "$d/hooks/tests/fixtures"; : > "$d/scripts/deny-target-precision.py"
    printf '%s\n' '#!/usr/bin/env bash' 'echo "одно место — один класс"' 'exit 0' > "$d/hooks/tests/fixtures/probe_D1192.sh"
    echo "CLAUDSOUL_REPO=$d"; }
green_D1193() { local d; d=$(mkfix D1193); mkdir -p "$d/hooks/tests/fixtures"
    printf '%s\n' '#!/usr/bin/env bash' 'echo "формы grep -c || echo в дереве нет"' 'exit 0' > "$d/hooks/tests/fixtures/probe_D1193.sh"  # grep-c-ok: текст подменной пробы
    echo "CLAUDSOUL_REPO=$d"; }
green_D1194() { local d; d=$(mkfix D1194); mkdir -p "$d/hooks/tests/fixtures"
    printf '%s\n' '#!/usr/bin/env bash' 'echo "подготовительных вызовов без стража 0"' 'exit 0' > "$d/hooks/tests/fixtures/probe_D1194.sh"
    echo "CLAUDSOUL_REPO=$d"; }
green_D1195() { local d; d=$(mkfix D1195); mkdir -p "$d/hooks/tests/fixtures"
    printf '%s\n' '#!/usr/bin/env bash' 'echo "тест вне набора боевой реестр не меняет"' 'exit 0' > "$d/hooks/tests/fixtures/probe_D1195.sh"
    echo "CLAUDSOUL_REPO=$d"; }
green_D1196() { local d; d=$(mkfix D1196); mkdir -p "$d/hooks/tests/fixtures"
    printf '%s\n' '#!/usr/bin/env bash' 'echo "«Проверки» 15 пунктов судят починку и зелены"' 'exit 0' > "$d/hooks/tests/fixtures/probe_D1196.sh"
    echo "CLAUDSOUL_REPO=$d"; }
green_D1197() { local d; d=$(mkfix D1197); mkdir -p "$d/hooks/tests/fixtures"
    printf '%s\n' '#!/usr/bin/env bash' 'echo "«Проверки» 20 пунктов судят починку, а не дрейф"' 'exit 0' > "$d/hooks/tests/fixtures/probe_D1197.sh"
    echo "CLAUDSOUL_REPO=$d"; }
green_D1199() { local d; d=$(mkfix D1199); mkdir -p "$d/hooks/tests/fixtures"
    printf '%s\n' '#!/usr/bin/env bash' 'echo "после срока потомков команды нет"' 'exit 0' > "$d/hooks/tests/fixtures/probe_D1199.sh"
    echo "CLAUDSOUL_REPO=$d"; }
green_D1200() { local d; d=$(mkfix D1200); mkdir -p "$d/hooks/tests/fixtures"
    printf '%s\n' '#!/usr/bin/env bash' 'echo "потребители убранного имени названы"' 'exit 0' > "$d/hooks/tests/fixtures/probe_D1200.sh"
    echo "CLAUDSOUL_REPO=$d"; }
green_D1201() { local d; d=$(mkfix D1201); mkdir -p "$d/hooks/tests/fixtures"
    printf '%s\n' '#!/usr/bin/env bash' 'echo "молчащих красных 0"' 'exit 0' > "$d/hooks/tests/fixtures/probe_D1201.sh"
    echo "CLAUDSOUL_REPO=$d"; }
# Зелёная сторона D1198 — ДЕРЕВО, чья проба исполнителей не находит оставленных каталогов.
green_D1198() { local d; d=$(mkfix D1198); mkdir -p "$d/hooks/tests/fixtures"
    printf '%s\n' '#!/usr/bin/env bash' 'echo "все шесть исполнителей убрали за командой"' 'exit 0' > "$d/hooks/tests/fixtures/probe_D1198.sh"
    echo "CLAUDSOUL_REPO=$d"; }
# Зелёная сторона D1191 — ДЕРЕВО, чей вид тел отдаёт телом строку ниже обеих форм (`#` во вложенной арифметике и после
# `;` внутри `$((`): «Проверка» подключает библиотеку из CLAUDSOUL_REPO.
green_D1191() { local d; d=$(mkfix D1191); mkdir -p "$d/hooks"
    printf '%s\n' '_ds_view() { _DS_V="z2"; }' > "$d/hooks/detection-signals-lib.sh"
    echo "CLAUDSOUL_REPO=$d"; }
# Зелёная сторона D1190 — ДЕРЕВО, чья карта даёт «записывает» обеим формам скептика (комментарий после назначения `mv`,
# `textwrap.dedent` выше присваивания пути). Пути записаны задом наперёд (урок фикстуры D1067).
green_D1190() { local d; d=$(mkfix D1190); mkdir -p "$d/scripts"; printf '%s\n' '#!/usr/bin/env python3' > "$d/scripts/dep-index.py"
    printf '%s\n' '#!/usr/bin/env python3' 'import json, sys' \
        'r = sys.argv[sys.argv.index("--repo") + 1] if "--repo" in sys.argv else "."' \
        'K = [s[::-1] for s in ("hs.1f/skooh", "yp.6f/skooh", "vst.w/atad")]' \
        'if "--refresh" in sys.argv:' \
        '    json.dump({"nodes": [{"id": i, "key": k} for i, k in enumerate(K)],' \
        '               "edges": [{"source": i, "target": 2, "type": "записывает"} for i in (0, 1)]},' \
        '              open(r + "/.claude-docs/project-graph.json", "w"))' > "$d/scripts/project-graph.py"
    echo "CLAUDSOUL_REPO=$d"; }
# Зелёная сторона D1189 — ДЕРЕВО, чей набор в строке «ПОД НАГРУЗКОЙ» называет первую упавшую ногу теста.
green_D1189() { local d; d=$(mkfix D1189); mkdir -p "$d/hooks/tests"; : > "$d/hooks/timeout-lib.sh"; : > "$d/hooks/portable-lib.sh"
    printf '%s\n' '#!/usr/bin/env bash' 'echo "УПАЛИ ТОЛЬКО ПОД НАГРУЗКОЙ (в одиночку зелёные):"' 'echo "  test_x.sh: код 1"' \
        'echo "      FAIL [L7 нога]: лишнее"' > "$d/hooks/tests/run_all.sh"
    echo "CLAUDSOUL_REPO=$d"; }
# Зелёная сторона D1188 — ДЕРЕВО, чей вид оболочки держит строку, которую bash исполняет кодом.
green_D1188() { local d; d=$(mkfix D1188); mkdir -p "$d/hooks"
    printf '%s\n' '_ds_view() { _DS_V="x=\$(cat <<EOF)
bodyz
EOF"; }' > "$d/hooks/detection-signals-lib.sh"
    echo "CLAUDSOUL_REPO=$d"; }
# Зелёная сторона D1187 — ДЕРЕВО, чьи учёт и карта дают ключ владельца для `..` через корень и для иного регистра.
green_D1187() { local d; d=$(mkfix D1187); mkdir -p "$d/scripts"
    printf '%s\n' '#!/usr/bin/env python3' 'import sys' 'if "--stale-by" in sys.argv: print("tools/a.sh")' > "$d/scripts/dep-index.py"
    printf '%s\n' '#!/usr/bin/env python3' 'import sys' 'if "--node" in sys.argv: print("=== tools/a.sh (script) ===")' > "$d/scripts/project-graph.py"
    echo "CLAUDSOUL_REPO=$d"; }
# Зелёная сторона D1186 — ДЕРЕВО, чья проба D1008 объявляет предмет.
green_D1186() { local d; d=$(mkfix D1186); mkdir -p "$d/hooks/tests/fixtures"
    printf '%s\n' '#!/usr/bin/env bash' '# СУДИТ: scripts/state-prune.sh' > "$d/hooks/tests/fixtures/probe_D1008.sh"
    echo "CLAUDSOUL_REPO=$d"; }
# Зелёная сторона D1185 — ДЕРЕВО, чей учёт ссылку на каталог файлом не читает: отчёт `--impact` полон, `--check` зелёный.
green_D1185() { local d; d=$(mkfix D1185); mkdir -p "$d/scripts"
    printf '%s\n' '#!/usr/bin/env python3' 'import sys' 'print("индекс собран" if "--all" in sys.argv else "")' > "$d/scripts/dep-index.py"
    echo "CLAUDSOUL_REPO=$d"; }
green_D1183() { local d; d=$(mkfix D1183); mkdir -p "$d/hooks/tests/fixtures"
    printf '%s\n' '#!/usr/bin/env bash' 'echo "долг каждого хода доходит до очереди"' 'exit 0' > "$d/hooks/tests/fixtures/probe_D1183.sh"
    echo "CLAUDSOUL_REPO=$d"; }
green_D1182() { local d; d=$(mkfix D1182); mkdir -p "$d/hooks/tests/fixtures"
    printf '%s\n' '#!/usr/bin/env bash' 'echo "ветки форм реестра держатся закреплёнными примерами «нет»"' 'exit 0' > "$d/hooks/tests/fixtures/probe_D1182.sh"
    echo "CLAUDSOUL_REPO=$d"; }
green_D1181() { local d; d=$(mkfix D1181); mkdir -p "$d/hooks/tests/fixtures"
    printf '%s\n' '#!/usr/bin/env bash' 'echo "ноги сверщика чисел судят при чужом корне и различают код"' 'exit 0' > "$d/hooks/tests/fixtures/probe_D1181.sh"
    echo "CLAUDSOUL_REPO=$d"; }
green_D1179() { local d; d=$(mkfix D1179); mkdir -p "$d/hooks/tests/fixtures"
    printf '%s\n' '#!/usr/bin/env bash' 'echo "тесты архиватора задают рамку сами"' 'exit 0' > "$d/hooks/tests/fixtures/probe_D1179.sh"
    echo "CLAUDSOUL_REPO=$d"; }
green_D1178() { local d; d=$(mkfix D1178); mkdir -p "$d/hooks/tests/fixtures"
    printf '%s\n' '#!/usr/bin/env bash' 'echo "мутанты пятого круга D1176 красят свои ноги"' 'exit 0' > "$d/hooks/tests/fixtures/probe_D1178.sh"
    echo "CLAUDSOUL_REPO=$d"; }
green_D1177() { local d; d=$(mkfix D1177); mkdir -p "$d/hooks/tests/fixtures"
    printf '%s\n' '#!/usr/bin/env bash' 'echo "тест многобайтной границы зелёный"' 'exit 0' > "$d/hooks/tests/fixtures/probe_D1177.sh"
    echo "CLAUDSOUL_REPO=$d"; }
green_D1176() { local d; d=$(mkfix D1176); mkdir -p "$d/hooks/tests/fixtures"
    printf '%s\n' '#!/usr/bin/env bash' 'echo "набор под ru_RU зелёный"' 'exit 0' > "$d/hooks/tests/fixtures/probe_D1176.sh"
    echo "CLAUDSOUL_REPO=$d"; }
green_D1175() { local d; d=$(mkfix D1175); mkdir -p "$d/hooks/tests/fixtures"
    printf '%s\n' '#!/usr/bin/env bash' 'echo "образцы сравнений судятся как объявлено"' 'exit 0' > "$d/hooks/tests/fixtures/probe_D1175.sh"
    echo "CLAUDSOUL_REPO=$d"; }
green_D1174() { local d; d=$(mkfix D1174); mkdir -p "$d/hooks/tests/fixtures"
    printf '%s\n' '#!/usr/bin/env bash' 'echo "страж разбора сортирует поводы байтами"' 'exit 0' > "$d/hooks/tests/fixtures/probe_D1174.sh"
    echo "CLAUDSOUL_REPO=$d"; }
green_D1173() { local d; d=$(mkfix D1173); mkdir -p "$d/hooks/tests/fixtures"
    printf '%s\n' '#!/usr/bin/env bash' 'echo "дорога install.sh судится поведением"' 'exit 0' > "$d/hooks/tests/fixtures/probe_D1173.sh"
    echo "CLAUDSOUL_REPO=$d"; }
green_D1172() { local d; d=$(mkfix D1172); mkdir -p "$d/hooks/tests/fixtures"
    printf '%s\n' '#!/usr/bin/env bash' 'echo "инжект и канарейка судят одно понятие хода"' 'exit 0' > "$d/hooks/tests/fixtures/probe_D1172.sh"
    echo "CLAUDSOUL_REPO=$d"; }
green_D1171() { local d; d=$(mkfix D1171); mkdir -p "$d/hooks/tests/fixtures"
    printf '%s\n' '#!/usr/bin/env bash' 'echo "сравнения меток в awk не зависят от локали"' 'exit 0' > "$d/hooks/tests/fixtures/probe_D1171.sh"
    echo "CLAUDSOUL_REPO=$d"; }
green_D1170() { local d; d=$(mkfix D1170); mkdir -p "$d/hooks/tests/fixtures"
    printf '%s\n' '#!/usr/bin/env bash' 'echo "сбой реестра родов — не измерено, а не носители есть"' 'exit 0' > "$d/hooks/tests/fixtures/probe_D1170.sh"
    echo "CLAUDSOUL_REPO=$d"; }
green_D1169() { local d; d=$(mkfix D1169); mkdir -p "$d/hooks/tests/fixtures"
    printf '%s\n' '#!/usr/bin/env bash' 'echo "формы находки и карты судятся как объявлено"' 'exit 0' > "$d/hooks/tests/fixtures/probe_D1169.sh"
    echo "CLAUDSOUL_REPO=$d"; }
green_D1168() { local d; d=$(mkfix D1168); mkdir -p "$d/hooks/tests/fixtures"
    printf '%s\n' '#!/usr/bin/env bash' 'echo "прибор родов без git не отвечает кодом «чисто»"' 'exit 0' > "$d/hooks/tests/fixtures/probe_D1168.sh"
    echo "CLAUDSOUL_REPO=$d"; }
green_D1158() { local d; d=$(mkfix D1158); mkdir -p "$d/hooks/tests/fixtures"
    printf '%s\n' '#!/usr/bin/env bash' 'echo "правка по находке без карты гарантий отбита"' 'exit 0' > "$d/hooks/tests/fixtures/probe_D1158.sh"
    echo "CLAUDSOUL_REPO=$d"; }
green_D1157() { local d; d=$(mkfix D1157); mkdir -p "$d/hooks/tests/fixtures"
    printf '%s\n' '#!/usr/bin/env bash' 'echo "замеры без владельца признака выходят кодом сбоя"' 'exit 0' > "$d/hooks/tests/fixtures/probe_D1157.sh"
    echo "CLAUDSOUL_REPO=$d"; }
green_D1156() { local d; d=$(mkfix D1156); mkdir -p "$d/hooks/tests/fixtures"
    printf '%s\n' '#!/usr/bin/env bash' 'echo "своя копия признака опознаётся по устройству"' 'exit 0' > "$d/hooks/tests/fixtures/probe_D1156.sh"
    echo "CLAUDSOUL_REPO=$d"; }
green_D1155() { local d; d=$(mkfix D1155); mkdir -p "$d/hooks/tests/fixtures"
    printf '%s\n' '#!/usr/bin/env bash' 'echo "ноги пробы D1150 держат обещания четвёртого круга"' 'exit 0' > "$d/hooks/tests/fixtures/probe_D1155.sh"
    echo "CLAUDSOUL_REPO=$d"; }
green_D1154() { local d; d=$(mkfix D1154); mkdir -p "$d/hooks/tests/fixtures"
    printf '%s\n' '#!/usr/bin/env bash' 'echo "реплей читает состояние там, куда его пишет детектор"' 'exit 0' > "$d/hooks/tests/fixtures/probe_D1154.sh"
    echo "CLAUDSOUL_REPO=$d"; }
green_D1150() { local d; d=$(mkfix D1150); mkdir -p "$d/hooks/tests/fixtures"
    printf '%s\n' '#!/usr/bin/env bash' 'echo "три копии судят реплику правилом авторства"' 'exit 0' > "$d/hooks/tests/fixtures/probe_D1150.sh"
    echo "CLAUDSOUL_REPO=$d"; }
green_D1148() { local d; d=$(mkfix D1148); mkdir -p "$d/scripts" "$d/hooks/tests/fixtures"; : > "$d/scripts/signal-precision-corpus.py"
    printf '%s\n' '#!/usr/bin/env bash' 'echo "реестр, названный в том же ходу после вызова инструмента, засчитан"' 'exit 0' > "$d/hooks/tests/fixtures/probe_D1148.sh"
    echo "CLAUDSOUL_REPO=$d"; }
green_D1147() { local d; d=$(mkfix D1147); mkdir -p "$d/scripts" "$d/hooks/tests/fixtures"; : > "$d/scripts/backlog-recheck.sh"
    printf '%s\n' '#!/usr/bin/env bash' 'echo "покрасневшая «Проверка» закрытого пункта названа"' 'exit 0' > "$d/hooks/tests/fixtures/probe_D1147.sh"
    echo "CLAUDSOUL_REPO=$d"; }
green_D1146() { local d; d=$(mkfix D1146); mkdir -p "$d/scripts" "$d/mcp-server/visualization"
    cp "$REPO/scripts/backlog-recheck.sh" "$d/scripts/" || return 1
    : > "$d/BACKLOG.md"; : > "$d/a.sh"; : > "$d/b.sh"
    # Спайка из двух файлов, история — одна правка одного из них: ответной правки нет.
    printf '{"nodes":[{"id":1,"key":"a.sh"},{"id":2,"key":"b.sh"}],"edges":[{"source":1,"target":2,"type":"зовёт"},{"source":2,"target":1,"type":"читает"}]}' > "$d/mcp-server/visualization/project-graph-data.json"
    ( cd "$d" && git init -q . && git add a.sh && git -c user.name=t -c user.email=t@t commit -qm a ) >/dev/null 2>&1 || return 1
    echo "CLAUDSOUL_REPO=$d"; }
green_D1143() { local d; d=$(mkfix D1143); mkdir -p "$d/scripts" "$d/hooks/tests/fixtures"; : > "$d/scripts/authorization-replay.py"
    printf '%s\n' '#!/usr/bin/env bash' 'echo "замеры по корпусу видят реплику посреди хода"' 'exit 0' > "$d/hooks/tests/fixtures/probe_D1143.sh"
    echo "CLAUDSOUL_REPO=$d"; }
green_D1139() { local d; d=$(mkfix D1139); mkdir -p "$d/scripts" "$d/hooks/tests/fixtures"; : > "$d/scripts/outcome.sh"
    printf '%s\n' '#!/usr/bin/env bash' 'echo "исход ложится только на находку без принятого исхода"' 'exit 0' > "$d/hooks/tests/fixtures/probe_D1139.sh"
    echo "CLAUDSOUL_REPO=$d"; }
green_D1123() { local d; d=$(mkfix D1123); mkdir -p "$d/hooks/lib" "$d/hooks/tests/fixtures"; : > "$d/hooks/lib/write_targets.py"
    printf '%s\n' '#!/usr/bin/env bash' 'echo "значения ключей — не цели"' 'exit 0' > "$d/hooks/tests/fixtures/probe_D1123.sh"
    echo "CLAUDSOUL_REPO=$d"; }
green_D1114() { local d; d=$(mkfix D1114); mkdir -p "$d/hooks/tests/fixtures"; : > "$d/hooks/impact-inject.sh"
    printf '%s\n' '#!/usr/bin/env bash' 'echo "код 3 без --touch"' 'exit 0' > "$d/hooks/tests/fixtures/probe_D439.sh"
    echo "CLAUDSOUL_REPO=$d"; }
green_D1113() { local d; d=$(mkfix D1113); mkdir -p "$d/hooks/tests"; : > "$d/hooks/impact-inject.sh"
    printf '%s\n' '#!/usr/bin/env bash' 'echo "подсказка о числах — по множествам владельца"' 'exit 0' > "$d/hooks/tests/test_impact_inject.sh"
    echo "CLAUDSOUL_REPO=$d"; }
# Зелёная сторона D1107 — ДЕРЕВО, чья проба меры исхода зелёная.
green_D1107() { local d; d=$(mkfix D1107); mkdir -p "$d/hooks/tests/fixtures"; : > "$d/hooks/declared-problem-recorded.sh"
    printf '%s\n' '#!/usr/bin/env bash' 'echo "правка без исхода — не recorded, сверенный исход — recorded"' 'exit 0' > "$d/hooks/tests/fixtures/probe_D1107.sh"
    echo "CLAUDSOUL_REPO=$d"; }
# Зелёная сторона D1105 — ДЕРЕВО, чей страж молчит на чтении и отбивает запись.
green_D1105() { local d; d=$(mkfix D1105); mkdir -p "$d/hooks/tests/fixtures"; : > "$d/hooks/five-whys-gate.sh"
    printf '%s\n' '#!/usr/bin/env bash' 'echo "чтение молчит, запись отбита"' 'exit 0' > "$d/hooks/tests/fixtures/probe_D1105.sh"
    echo "CLAUDSOUL_REPO=$d"; }
# Зелёная сторона D1104 — ДЕРЕВО, чья команда исхода отвергает заявление без цепочки.
green_D1104() { local d; d=$(mkfix D1104); mkdir -p "$d/scripts" "$d/hooks"; : > "$d/hooks/root-cause-lib.sh"
    printf '%s\n' '#!/usr/bin/env bash' 'echo "исход без цепочки не принимается" >&2' 'exit 2' > "$d/scripts/outcome.sh"
    echo "CLAUDSOUL_REPO=$d"; }
# Зелёная сторона D1103 — ДЕРЕВО, чей счёт опыта видит сессии дня отметки.
green_D1103() { local d; d=$(mkfix D1103); mkdir -p "$d/hooks/tests/fixtures"; : > "$d/hooks/fsrs-lib.sh"
    printf '%s\n' '#!/usr/bin/env bash' 'echo "опыт после отметки: 10"' 'exit 0' > "$d/hooks/tests/fixtures/probe_D1103.sh"
    echo "CLAUDSOUL_REPO=$d"; }
# Зелёная сторона D1099 — ДЕРЕВО, чей установщик кладёт META через журнал переносов.
green_D1099() { local d; d=$(mkfix D1099); mkdir -p "$d/hooks/tests"; : > "$d/install.sh"
    printf '%s\n' '#!/usr/bin/env bash' '# нога T11b' 'echo "carry-log: PASS=27 FAIL=0"' > "$d/hooks/tests/test_carry_log.sh"
    echo "CLAUDSOUL_REPO=$d"; }
# Зелёная сторона D1098 — ДЕРЕВО, чей свидетель сверщика различает направление расхождения META.
green_D1098() { local d; d=$(mkfix D1098); mkdir -p "$d/hooks/tests" "$d/scripts" "$d/lib"
    : > "$d/scripts/backlog-recheck.sh"; : > "$d/lib/carry-log.sh"
    printf '%s\n' '#!/usr/bin/env bash' '# нога «T8 отставание рабочей копии названо откатом»' \
        'echo "backlog recheck tests: 9/9 passed"' > "$d/hooks/tests/test_backlog_recheck.sh"
    echo "CLAUDSOUL_REPO=$d"; }
# Зелёная сторона D1097 — ДЕРЕВО, чей свидетель сверки не исполняет fsmonitor судимого дерева.
green_D1097() { local d; d=$(mkfix D1097); mkdir -p "$d/hooks/tests" "$d/scripts"
    : > "$d/scripts/project-conformance.sh"
    printf '%s\n' '#!/usr/bin/env bash' 'echo "project conformance tests: 19/19 passed"' 'exit 0' \
        > "$d/hooks/tests/test_project_conformance.sh"
    echo "CLAUDSOUL_REPO=$d"; }
# Зелёная сторона D1096 — ДЕРЕВО, чей свидетель заведения карты связей в проекте зелёный.
green_D1096() { local d; d=$(mkfix D1096); mkdir -p "$d/hooks/tests" "$d/hooks/lib" "$d/scripts"
    : > "$d/hooks/lib/project_map.py"; : > "$d/scripts/project-conformance.sh"
    printf '%s\n' '#!/usr/bin/env bash' 'exit 0' > "$d/hooks/tests/test_project_map_init.sh"
    echo "CLAUDSOUL_REPO=$d"; }
# Зелёная сторона D1095 — ДЕРЕВО, чей свидетель гасит фильтр подмодуля и при submodule.ignore=none.
green_D1095() { local d; d=$(mkfix D1095); mkdir -p "$d/hooks/tests"; : > "$d/hooks/paths-lib.sh"
    printf '%s\n' '#!/usr/bin/env bash' 'echo "  ✓ подмодуль: submodule.ignore=none в .git/config не включает фильтр"' \
        'echo "  ✓ подмодуль: submodule.ignore=none в .gitmodules не включает фильтр"' 'echo "test_project_git: PASS=20 FAIL=0"' \
        > "$d/hooks/tests/test_project_git.sh"
    echo "CLAUDSOUL_REPO=$d"; }
# Зелёная сторона D1094 — ДЕРЕВО, чей свидетель обёртки гасит фильтр из настроек подмодуля.
green_D1094() { local d; d=$(mkfix D1094); mkdir -p "$d/hooks/tests"; : > "$d/hooks/paths-lib.sh"
    printf '%s\n' '#!/usr/bin/env bash' 'echo "  ✓ status: фильтр из настроек подмодуля погашен"' \
        'echo "  ✓ diff HEAD: фильтр из настроек подмодуля погашен"' 'echo "test_project_git: PASS=18 FAIL=0"' \
        > "$d/hooks/tests/test_project_git.sh"
    echo "CLAUDSOUL_REPO=$d"; }
# Зелёная сторона D1092 — ДЕРЕВО, чья карточка документа с рёбрами называет стоящих, а не «не знает».
green_D1092() { local d; d=$(mkfix D1092); mkdir -p "$d/scripts" "$d/.claude-docs/modules"
    printf '%s\n' '#!/usr/bin/env python3' 'print("на нём стоят 2: doc 2 (project-graph.md, doc-impact-check.md)")' \
        > "$d/scripts/project-graph.py"
    : > "$d/.claude-docs/modules/project-map.md"
    printf '.claude-docs/modules/project-map.md\tx\t\t\t\t\n' > "$d/.claude-docs/dep-index.tsv"
    echo "CLAUDSOUL_REPO=$d"; }
# Зелёная сторона D1093 — ДЕРЕВО, чья проба хука коммита (решение по второму документу не требуется при staged первом) зелена.
green_D1093() { local d; d=$(mkfix D1093); mkdir -p "$d/hooks/tests/fixtures"
    : > "$d/hooks/doc-impact-check.sh"
    printf '%s\n' '#!/usr/bin/env bash' 'exit 0' > "$d/hooks/tests/fixtures/probe_D1093.sh"
    echo "CLAUDSOUL_REPO=$d"; }
# Зелёная сторона D1091 — ДЕРЕВО, чей свидетель обёртки безопасного git гасит фильтр с «=» в имени драйвера.
green_D1091() { local d; d=$(mkfix D1091); mkdir -p "$d/hooks/tests"; : > "$d/hooks/paths-lib.sh"
    printf '%s\n' '#!/usr/bin/env bash' 'echo "  ✓ diff: фильтр с «=» в имени погашен"' > "$d/hooks/tests/test_project_git.sh"
    echo "CLAUDSOUL_REPO=$d"; }
# Зелёная сторона D1090 — ДЕРЕВО, чей страж «файл исполняется» называет только ТОТ ЖЕ файл, а не одноимённый.
green_D1090() { local d; d=$(mkfix D1090); mkdir -p "$d/hooks"
    printf '%s\n' '#!/usr/bin/env bash' 'i=$(cat)' 'case "$i" in *"/b/x.sh"*) echo "исполняется";; esac' \
        > "$d/hooks/running-file-edit-guard.sh"
    echo "CLAUDSOUL_REPO=$d"; }
# Зелёная сторона D1089 — ДЕРЕВО, чей свидетель «любого проекта» (подсказка и хук коммита с прибором ClaudSoul, ничего
# из проекта не исполняется) зелёный.
green_D1089() { local d; d=$(mkfix D1089); mkdir -p "$d/hooks/tests" "$d/scripts"; : > "$d/hooks/impact-inject.sh"
    printf '%s\n' '#!/usr/bin/env bash' 'exit 0' > "$d/hooks/tests/test_project_map_any_project.sh"
    printf '%s\n' '#!/usr/bin/env python3' > "$d/scripts/dep-index.py"
    echo "CLAUDSOUL_REPO=$d"; }
# Зелёная сторона D1088 — ДЕРЕВО, чей разбор целей записи учитывает `cd` той же команды: абсолютный — путь целиком,
# относительный — приставкой к пути цели.
green_D1088() { local d; d=$(mkfix D1088); mkdir -p "$d/hooks/lib"
    printf '%s\n' 'import sys' 'c = sys.stdin.read()' \
        'print("/tmp/d1088/f.md" if "cd /tmp/d1088" in c else "sub/x" if "cd sub" in c else "")' > "$d/hooks/lib/write_targets.py"
    echo "CLAUDSOUL_REPO=$d"; }
# Зелёная сторона D1087 — ДЕРЕВО, где «добавит ли команда всё» — одна функция библиотеки разбора, четыре хука её зовут без
# своих выражений, эталон зелёный.
green_D1087() { local d h; d=$(mkfix D1087); mkdir -p "$d/hooks/tests"
    printf '%s\n' 'executable_commit_adds() { :; }' > "$d/hooks/command-scope-lib.sh"
    for h in doc-impact-check changelog-reminder backlog-vanish-check docs-family-check; do
        printf '%s\n' 'executable_commit_adds "$COMMAND"' > "$d/hooks/$h.sh"; done
    printf '%s\n' '#!/usr/bin/env bash' 'exit 0' > "$d/hooks/tests/test_commit_adds_oracle.sh"
    echo "CLAUDSOUL_REPO=$d"; }
# Зелёная сторона D1086 — ДЕРЕВО, чей свидетель хука коммита зелёный и несёт ноги T46 и T48.
green_D1086() { local d; d=$(mkfix D1086); mkdir -p "$d/hooks/tests"; : > "$d/hooks/doc-impact-check.sh"
    printf '%s\n' '#!/usr/bin/env bash' '# T46 T48' 'exit 0' > "$d/hooks/tests/test_doc_impact_check.sh"
    echo "CLAUDSOUL_REPO=$d"; }
# Зелёная сторона D1085 — ДЕРЕВО, чей свидетель хука коммита зелёный и несёт ноги T42 и T45.
green_D1085() { local d; d=$(mkfix D1085); mkdir -p "$d/hooks/tests"; : > "$d/hooks/doc-impact-check.sh"
    printf '%s\n' '#!/usr/bin/env bash' '# T42 T45' 'exit 0' > "$d/hooks/tests/test_doc_impact_check.sh"
    echo "CLAUDSOUL_REPO=$d"; }
# Зелёная сторона D1084 — ДЕРЕВО, чей свидетель хука коммита зелёный и несёт ноги T37, T41 и T40б.
green_D1084() { local d; d=$(mkfix D1084); mkdir -p "$d/hooks/tests"; : > "$d/hooks/doc-impact-check.sh"
    printf '%s\n' '#!/usr/bin/env bash' '# T37 T41 T40б' 'exit 0' > "$d/hooks/tests/test_doc_impact_check.sh"
    echo "CLAUDSOUL_REPO=$d"; }
# Зелёная сторона D1083 — ДЕРЕВО, чей свидетель хука коммита зелёный и несёт ноги T33б и T36.
green_D1083() { local d; d=$(mkfix D1083); mkdir -p "$d/scripts" "$d/hooks/tests"; : > "$d/hooks/doc-impact-check.sh"
    printf '%s\n' '#!/usr/bin/env python3' > "$d/scripts/dep-index.py"
    printf '%s\n' '#!/usr/bin/env bash' '# T33б T36' 'exit 0' > "$d/hooks/tests/test_doc_impact_check.sh"
    echo "CLAUDSOUL_REPO=$d"; }
# Зелёная сторона D1081 — ДЕРЕВО, чей свидетель контракта инструментов зелёный и внесён в реестр «дерево целиком».
green_D1081() { local d; d=$(mkfix D1081); mkdir -p "$d/hooks/tests"
    printf '%s\n' '#!/usr/bin/env bash' 'exit 0' > "$d/hooks/tests/test_instrument_contract.sh"
    printf 'test_instrument_contract.sh\tнаблюдение\n' > "$d/hooks/tests/always-run.tsv"
    echo "CLAUDSOUL_REPO=$d"; }
# Зелёная сторона D1080 — ДЕРЕВО, чей свидетель карты прошёл до конца без падения C14.
green_D1080() { local d; d=$(mkfix D1080); mkdir -p "$d/scripts" "$d/hooks/tests"
    printf '%s\n' '#!/usr/bin/env python3' > "$d/scripts/dep-index.py"
    printf '%s\n' '#!/usr/bin/env bash' '# C14' 'echo "test_project_map: прошло 1, упало 0"' > "$d/hooks/tests/test_project_map.sh"
    echo "CLAUDSOUL_REPO=$d"; }
# Зелёная сторона D1079 — ДЕРЕВО, чей свидетель импортов зелёный и у `brain.py` в учёте записан его тест.
green_D1079() { local d; d=$(mkfix D1079); mkdir -p "$d/hooks/tests" "$d/scripts" "$d/.claude-docs"
    printf '%s\n' '#!/usr/bin/env bash' 'exit 0' > "$d/hooks/tests/test_project_map_imports.sh"
    printf '%s\n' '#!/usr/bin/env python3' > "$d/scripts/dep-index.py"
    printf 'mcp-server/brain.py\tx\t\t\tmcp-server/tests/test_brain.py\t\n' > "$d/.claude-docs/dep-index.tsv"
    echo "CLAUDSOUL_REPO=$d"; }
# Зелёная сторона D1078 — ДЕРЕВО, чей свидетель петли несогласия зелёный в обоих поясах.
green_D1078() { local d; d=$(mkfix D1078); mkdir -p "$d/hooks/tests"
    printf '%s\n' '#!/usr/bin/env bash' 'exit 0' > "$d/hooks/tests/test_disagreement_loop.sh"
    printf '%s\n' '#!/usr/bin/env bash' > "$d/hooks/disagreement-lib.sh"
    echo "CLAUDSOUL_REPO=$d"; }
# Зелёная сторона D1077 — ДЕРЕВО, чей свидетель хука коммита зелёный.
green_D1077() { local d; d=$(mkfix D1077); mkdir -p "$d/hooks/tests" "$d/scripts"
    printf '%s\n' '#!/usr/bin/env bash' 'exit 0' > "$d/hooks/tests/test_doc_impact_check.sh"
    printf '%s\n' '#!/usr/bin/env bash' > "$d/hooks/doc-impact-check.sh"
    printf '%s\n' '#!/usr/bin/env python3' > "$d/scripts/dep-index.py"
    echo "CLAUDSOUL_REPO=$d"; }
# Зелёная сторона D1076 — ДЕРЕВО, чьи свидетели учёта (перечень `--stale-by` и хук коммита) зелёные.
green_D1076() { local d; d=$(mkfix D1076); mkdir -p "$d/hooks/tests" "$d/scripts"
    printf '%s\n' '#!/usr/bin/env bash' 'exit 0' > "$d/hooks/tests/test_project_map.sh"
    printf '%s\n' '#!/usr/bin/env bash' 'exit 0' > "$d/hooks/tests/test_doc_impact_check.sh"
    printf '%s\n' '#!/usr/bin/env python3' > "$d/scripts/dep-index.py"
    echo "CLAUDSOUL_REPO=$d"; }
# Зелёная сторона D1074 — ДЕРЕВО, чей свидетель сроков зелёный.
green_D1074() { local d; d=$(mkfix D1074); mkdir -p "$d/hooks/tests" "$d/scripts"
    printf '%s\n' '#!/usr/bin/env bash' 'exit 0' > "$d/hooks/tests/test_measurement_due.sh"
    printf '%s\n' '#!/usr/bin/env bash' 'exit 0' > "$d/scripts/measurement-due.sh"
    echo "CLAUDSOUL_REPO=$d"; }
# Зелёная сторона D1073 — ДЕРЕВО, чьи учёт и карта переводят путь одним правилом и не вносят `..` после ссылки,
# каталог и `.GIT/`, а учёт держит имя git своим ключом (`--stale-by` называет данные имена как есть — второй круг).
green_D1073() { local d; d=$(mkfix D1073); mkdir -p "$d/scripts"
    printf '%s\n' '#!/usr/bin/env python3' 'import sys, os' 'a = sys.argv' \
        'if "--impact" in a: print("новые механизмы без строки в учёте:\n  · " + a[-1])' \
        'if "--stale-by" in a:' '    r = a[a.index("--repo") + 1] if "--repo" in a else ""' \
        '    print("\n".join(os.path.normpath(x[len(r) + 1:] if r and x.startswith(r + "/") else x) for x in a[a.index("--stale-by") + 1:]))' \
        > "$d/scripts/dep-index.py"
    printf '%s\n' '#!/usr/bin/env python3' 'import sys' 'a = sys.argv' 'if "--touch" in a:' \
        '    x = a[a.index("--touch") + 1]' \
        '    bad = x.endswith("/") or ".." in x.split("/") or x.lower().startswith(".git/")' \
        '    print("карта не тронута: отказ" if bad else "в карте: " + x)' > "$d/scripts/project-graph.py"
    echo "CLAUDSOUL_REPO=$d"; }
# Зелёная сторона D1072 — ДЕРЕВО, чей хук подсказки не вносит в карту цель из чужого каталога.
green_D1072() { local d; d=$(mkfix D1072); mkdir -p "$d/hooks" "$d/scripts"
    printf '%s\n' '#!/usr/bin/env bash' \
        'i=$(cat); case "$i" in *"cd hooks "*) k=hooks/l1072.sh ;; *"cd "*) exit 0 ;; *) k=hooks/p1072.sh ;; esac' \
        'python3 -c "import json,os,sys; c=os.environ[\"CLAUDSOUL_ROOT\"]+\"/mcp-server/visualization/project-graph-data.json\"; g=json.load(open(c)); g[\"nodes\"].append({\"key\": sys.argv[1]}); json.dump(g, open(c, \"w\"))" "$k"' \
        > "$d/hooks/impact-inject.sh"
    printf '%s\n' '#!/usr/bin/env python3' 'import sys, os, json' 'if "--refresh" in sys.argv:' \
        '    r = os.environ["CLAUDSOUL_REPO"]; json.dump({"nodes": []}, open(r + "/mcp-server/visualization/project-graph-data.json", "w"))' \
        > "$d/scripts/project-graph.py"
    echo "CLAUDSOUL_REPO=$d"; }
# Зелёная сторона D1071 — ДЕРЕВО, чьи карта и учёт вносят новый файл, судят проект по ссылке и не идут по ссылке замка.
green_D1071() { local d; d=$(mkfix D1071); mkdir -p "$d/hooks/lib" "$d/scripts"
    : > "$d/hooks/lib/project_map.py"; printf '%s\n' '#!/usr/bin/env python3' > "$d/scripts/dep-index.py"
    printf '%s\n' '#!/usr/bin/env python3' 'import sys, os, json' 'r = sys.argv[sys.argv.index("--repo") + 1]' \
        'os.makedirs(r + "/.claude-docs", exist_ok=True)' \
        'json.dump({"nodes": [{"key": "x/new.sh"}]}, open(r + "/.claude-docs/project-graph.json", "w"))' \
        'print("в карте: x/a.sh") if "--touch" in sys.argv else None' > "$d/scripts/project-graph.py"
    echo "CLAUDSOUL_REPO=$d"; }
# Зелёная сторона D1070 — ДЕРЕВО, чьи учёт и карта не пишут наружу, а проект по ссылке судят и называют зависимого.
green_D1070() { local d; d=$(mkfix D1070); mkdir -p "$d/hooks/lib" "$d/scripts"
    : > "$d/hooks/lib/project_map.py"; printf '%s\n' '#!/usr/bin/env python3' > "$d/scripts/project-graph.py"
    printf '%s\n' '#!/usr/bin/env python3' 'import sys' 'if "--impact" in sys.argv: print("зависят от изменённого (1): main.sh")' > "$d/scripts/dep-index.py"
    echo "CLAUDSOUL_REPO=$d"; }
# Зелёная сторона D1069 — ДЕРЕВО, чья карта не вешает знание на чужой файл по хвосту имени.
green_D1069() { local d; d=$(mkfix D1069); mkdir -p "$d/scripts"
    printf '%s\n' '#!/usr/bin/env python3' 'import sys' 'if "--node" in sys.argv: print("=== tests/t.sh ===")' > "$d/scripts/project-graph.py"
    printf '%s\n' '#!/usr/bin/env python3' > "$d/scripts/dep-index.py"
    echo "CLAUDSOUL_REPO=$d"; }
# Зелёная сторона D1067 — ДЕРЕВО, чья карта называет у бэклога и у META.md достаточно стоящих на них.
green_D1067() { local d; d=$(mkfix D1067); mkdir -p "$d/scripts" "$d/mcp-server/visualization"
    # Карта, где у каждого договора из поимённого списка «Проверки» стоят его читатели, а ложных рёбер (F1/F3) нет.
    # Пары «договор:читатель» записаны ЗАДОМ НАПЕРЁД: имя механизма в тексте теста учёт засчитывает «проверяет»,
    # и фикстура дала бы этому свидетелю ложные рёбра к 21 механизму.
    printf '%s\n' '#!/usr/bin/env python3' 'import json, sys' \
        'P = ("hs.hserfer-gnidaer-golkcab/skooh:dm.GOLKCAB hs.kcehc-hcuot-golkcab/skooh:dm.GOLKCAB"' \
        '     " hs.kcehc-hsinav-golkcab/skooh:dm.GOLKCAB hs.etag-noitelpmoc/skooh:dm.GOLKCAB"' \
        '     " hs.dedrocer-melborp-deralced/skooh:dm.GOLKCAB hs.etag-toor-egrem/skooh:dm.GOLKCAB"' \
        '     " hs.rotcelloc-scirtem/skooh:dm.GOLKCAB hs.rotcelloc-noisses/skooh:dm.GOLKCAB"' \
        '     " hs.trats-noisses/skooh:dm.GOLKCAB hs.evihcra-golkcab/stpircs:dm.GOLKCAB"' \
        '     " hs.kcehcer-golkcab/stpircs:dm.GOLKCAB hs.sgnidaer-hserfer-golkcab/stpircs:dm.GOLKCAB"' \
        '     " hs.kcehc-nruter-golkcab/stpircs:dm.GOLKCAB hs.ecnamrofnoc-tcejorp/stpircs:dm.GOLKCAB"' \
        '     " hs.llatsni:dm.ATEM/egdelwonk hs.kcehcer-golkcab/stpircs:dm.ATEM/egdelwonk"' \
        '     " hs.detfird-cnys/stpircs:dm.ATEM/egdelwonk hs.remusnoc-sah-msinahcem/skooh:vst.stnemerusaem/stpircs"' \
        '     " hs.eud-tnemerusaem/stpircs:vst.stnemerusaem/stpircs hs.kcehc-ezis-dm-edualc/skooh:dm.EDUALC"' \
        '     " hs.stats-tnuoc/stpircs:dm.EDUALC")' \
        'if "--refresh" in sys.argv:' \
        '    pairs = [p[::-1].split(":") for p in P.split()]; keys = sorted({x for p in pairs for x in p}); ids = {k: i for i, k in enumerate(keys)}' \
        '    json.dump({"nodes": [{"id": ids[k], "key": k} for k in keys],' \
        '               "edges": [{"source": ids[r], "target": ids[c], "type": "читает"} for c, r in pairs]},' \
        '              open("mcp-server/visualization/project-graph-data.json", "w"))' > "$d/scripts/project-graph.py"
    echo "CLAUDSOUL_REPO=$d"; }
# Зелёная сторона D1066 — ДЕРЕВО, чей страж отказывает всякому вызову с `timeout 5`.
green_D1066() { local d; d=$(mkfix D1066); mkdir -p "$d/hooks"
    printf '%s\n' '#!/usr/bin/env bash' 'c=$(jq -r .tool_input.command); case "$c" in *"timeout 5"*) echo deny ;; esac' > "$d/hooks/absent-tool-guard.sh"
    echo "CLAUDSOUL_REPO=$d"; }
# Зелёная сторона D1065 — ДЕРЕВО, чья проба читателя бэклога под писателем с усечением не нашла неверных чтений.
green_D1065() { local d; d=$(mkfix D1065); mkdir -p "$d/hooks/tests/fixtures"; : > "$d/hooks/backlog-lib.sh"
    printf '%s\n' '#!/usr/bin/env bash' 'echo "чтений 6, неверных 0"' 'exit 0' > "$d/hooks/tests/fixtures/probe_D1065.sh"
    echo "CLAUDSOUL_REPO=$d"; }
# Зелёная сторона D1053 — ДЕРЕВО, чей страж отказывает двум местным вызовам и молчит на `echo {timeout 5}`.
green_D1053() { local d; d=$(mkfix D1053); mkdir -p "$d/hooks"
    printf '%s\n' '#!/usr/bin/env bash' 'c=$(jq -r .tool_input.command); case "$c" in *"{timeout 5}"*) exit 0 ;; *"timeout 5 true"*) echo deny ;; esac' > "$d/hooks/absent-tool-guard.sh"
    echo "CLAUDSOUL_REPO=$d"; }
# Зелёная сторона D1054 — ДЕРЕВО, чей страж отказывает и при сломанной библиотеке: «Проверка» копирует оба файла.
green_D1054() { local d; d=$(mkfix D1054); mkdir -p "$d/hooks"
    printf '%s\n' '#!/usr/bin/env bash' 'c=$(jq -r .tool_input.command); case "$c" in *"timeout 5 true"*) echo deny ;; esac' > "$d/hooks/absent-tool-guard.sh"
    printf '%s\n' '# библиотека видов (заглушка)' > "$d/hooks/detection-signals-lib.sh"
    echo "CLAUDSOUL_REPO=$d"; }
# Зелёная сторона D1052 — ДЕРЕВО, чей канал отдаёт сигнал старта без HOME и напоминание через ссылку на корень:
# «Проверка» исполняет хук из CLAUDSOUL_REPO.
green_D1052() { local d; d=$(mkfix D1052); mkdir -p "$d/hooks"
    printf '%s\n' '#!/usr/bin/env bash' 'cat >/dev/null; printf "%s\n" "сигнал старта d1052 сирота через ссылку"' > "$d/hooks/pending-alerts-surface.sh"
    echo "CLAUDSOUL_REPO=$d"; }
# Зелёная сторона D1050 — ДЕРЕВО, чья библиотека вырезает обе цитаты: «Проверка» подключает её из CLAUDSOUL_REPO.
green_D1050() { local d; d=$(mkfix D1050); mkdir -p "$d/hooks"
    printf '%s\n' 'user_own_speech() { printf "%s\n" "он ответил и но я согласен"; }' > "$d/hooks/hook-input-lib.sh"
    echo "CLAUDSOUL_REPO=$d"; }
# Зелёная сторона D1051 — ДЕРЕВО, чей хук называет только сироту-контроль: «Проверка» исполняет хук из CLAUDSOUL_REPO.
green_D1051() { local d; d=$(mkfix D1051); mkdir -p "$d/hooks"
    printf '%s\n' '#!/usr/bin/env bash' 'cat >/dev/null; echo "сирота-контроль без пометки" > "$STATE_DIR/stop-signals-s1.txt"' > "$d/hooks/declared-problem-recorded.sh"
    echo "CLAUDSOUL_REPO=$d"; }
# Зелёная сторона D1049 — ДЕРЕВО, чей канал держит напоминание у своей сессии и чужой не отдаёт: «Проверка» исполняет
# хуки из CLAUDSOUL_REPO с STATE_DIR и HOME пробы.
green_D1049() { local d; d=$(mkfix D1049); mkdir -p "$d/hooks"
    printf '%s\n' '#!/usr/bin/env bash' 'cat >/dev/null; echo "сирота молчащей вкладки" > "$STATE_DIR/stop-signals-sa.txt"' > "$d/hooks/declared-problem-recorded.sh"
    printf '%s\n' '#!/usr/bin/env bash' 'cat >/dev/null' > "$d/hooks/pending-alerts-surface.sh"
    echo "CLAUDSOUL_REPO=$d"; }
# Зелёная сторона D1045 — ДЕРЕВО, чей прибор сверки адресов называет уплывший адрес в комментарии кода: «Проверка»
# исполняет прибор из CLAUDSOUL_REPO в песочном репозитории.
green_D1045() { local d; d=$(mkfix D1045); mkdir -p "$d/scripts"
    printf '%s\n' 'print("  · a.sh → b.sh:2 — строка уехала на 3: TARGET_LINE_X")' > "$d/scripts/docs-address-drift.py"
    echo "CLAUDSOUL_REPO=$d"; }
# Зелёная сторона D1044 — ДЕРЕВО, чей хук пишет пункты без исхода в посессионный файл (не в общую очередь) и молчит на
# пунктах с исходом: «Проверка» исполняет хук из CLAUDSOUL_REPO с STATE_DIR пробы.
green_D1044() { local d; d=$(mkfix D1044); mkdir -p "$d/hooks"
    printf '%s\n' '#!/usr/bin/env bash' 'in=$(cat "$(jq -r .transcript_path)")' \
        'case "$in" in *"заголовка"*) echo "находка в строке заголовка" >> "$STATE_DIR/startup-signals-s1.txt" ;; esac' \
        'case "$in" in *"починю потом"*) echo "дефект в разборе, починю потом" >> "$STATE_DIR/startup-signals-s1.txt" ;; esac' \
        > "$d/hooks/declared-problem-recorded.sh"
    echo "CLAUDSOUL_REPO=$d"; }
# Зелёная сторона D1043 — ДЕРЕВО, чей движок отвечает кодом 2 на неизвестный предикат: «Проверка» подключает библиотеку
# из CLAUDSOUL_REPO.
green_D1043() { local d; d=$(mkfix D1043); mkdir -p "$d/hooks"
    printf '%s\n' 'ds_evaluate_node() { return 2; }' > "$d/hooks/detection-signals-lib.sh"
    echo "CLAUDSOUL_REPO=$d"; }
# Зелёная сторона D1042 — ДЕРЕВО, чей вид оболочки держит только хвост после тела (`echo after`), а вид `live` —
# подстановку: «Проверка» подключает библиотеку из CLAUDSOUL_REPO. Имя формы собрано из частей — признак переносимости
# судит текст команды.
green_D1042() { local d; d=$(mkfix D1042); mkdir -p "$d/hooks"
    printf '%s\n' '_ds_view() { case "$1" in live) _DS_V="x \${PIPE""STATUS[0]}" ;; shell) _DS_V="echo after; time""out 5 true" ;; full) _DS_V="time""out 5 true" ;; *) _DS_V="" ;; esac; }' \
        > "$d/hooks/detection-signals-lib.sh"
    echo "CLAUDSOUL_REPO=$d"; }
# Зелёная сторона D1041 — ДЕРЕВО, чей страж «записано» кладёт в очередь пункт итога без исхода и не кладёт пункты с
# исходом: «Проверка» исполняет хук из CLAUDSOUL_REPO с STATE_DIR пробы.
green_D1041() { local d; d=$(mkfix D1041); mkdir -p "$d/hooks"
    printf '%s\n' '#!/usr/bin/env bash' 'cat >/dev/null' 'echo "без исхода: черновики ждут разбора" >> "$STATE_DIR/pending-alerts.txt"' \
        > "$d/hooks/declared-problem-recorded.sh"
    echo "CLAUDSOUL_REPO=$d"; }
# Зелёная сторона D1040 — ДЕРЕВО, чей движок называет признак на живой форме (`… | grep -q x; echo "${…}"`) и молчит на
# той же форме внутри `'…'`: «Проверка» подключает библиотеку и знание из CLAUDSOUL_REPO.
green_D1040() { local d; d=$(mkfix D1040); mkdir -p "$d/hooks" "$d/knowledge"
    printf '%s\n' 'ds_evaluate() { case "$3" in *"grep -q x"*) echo bash_only_form_in_zsh ;; esac; }' \
        > "$d/hooks/detection-signals-lib.sh"
    : > "$d/knowledge/pattern-shell-portability.md"
    echo "CLAUDSOUL_REPO=$d"; }
# Зелёная сторона D1038 — ДЕРЕВО, чей страж неопределённых функций называет assert_eq: «Проверка» исполняет стража
# из CLAUDSOUL_REPO на файле, зовущем функцию, объявленную только в чужих тестах.
green_D1038() { local d; d=$(mkfix D1038); mkdir -p "$d/hooks"
    printf '%s\n' '#!/usr/bin/env bash' 'cat >/dev/null' 'echo "не определена: assert_eq"' > "$d/hooks/undefined-function-check.sh"
    echo "CLAUDSOUL_REPO=$d"; }
# Зелёная сторона D1037 — ДЕРЕВО, чей разбор целей отдаёт только литеральную цель: «Проверка» исполняет разбор из
# CLAUDSOUL_REPO и судит его выдачу на команде с переменной, подстановкой и литеральной целью.
green_D1037() { local d; d=$(mkfix D1037); mkdir -p "$d/hooks/lib"
    printf '%s\n' 'import sys' 'sys.stdin.read()' 'print("real.md")' > "$d/hooks/lib/write_targets.py"
    echo "CLAUDSOUL_REPO=$d"; }
# Зелёная сторона D1010 — ДЕРЕВО, чей throttle_file журналов не снимает: «Проверка» исполняет библиотеку из CLAUDSOUL_REPO.
green_D1010() { local d; d=$(mkfix D1010); mkdir -p "$d/hooks"
    printf 'throttle_file() { :; }\n' > "$d/hooks/throttle-lib.sh"
    echo "CLAUDSOUL_REPO=$d"; }
# Зелёная сторона D1011 — ДЕРЕВО, чьи три представителя утечки ничего не пишут: «Проверка» гонит их из CLAUDSOUL_REPO.
green_D1011() { local d t; d=$(mkfix D1011); mkdir -p "$d/hooks/tests"
    for t in test_adv6_archive_second_proverka_ignored.sh test_defect_registry_origin_forms.sh test_backlog_reading_refresh.sh test_instruments_honest.sh; do
        printf '#!/usr/bin/env bash\nexit 0\n' > "$d/hooks/tests/$t"; done
    echo "CLAUDSOUL_REPO=$d"; }
# Зелёная сторона D1012 — ДЕРЕВО, чей страж отказывает местному `timeout`, но молчит на скрипте для ssh: «Проверка»
# зовёт стража из CLAUDSOUL_REPO. Заглушка не спрашивает машину, поэтому сторона одинакова на macOS и под Linux.
green_D1012() { local d; d=$(mkfix D1012); mkdir -p "$d/hooks"
    printf '%s\n' '#!/usr/bin/env bash' 'c=$(jq -r ".tool_input.command // \"\"")' \
        'case "$c" in timeout*) echo deny ;; esac' 'exit 0' > "$d/hooks/absent-tool-guard.sh"
    echo "CLAUDSOUL_REPO=$d"; }
# Зелёная сторона D1013 — ДЕРЕВО, где у четырёх носителей защиты D1011 перечень временных корней только в комментарии:
# «Проверка» судит код. Сторона по ФОРМЕ — её позеленит и снятие защиты, поведение держат свидетели D1011.
green_D1013() { local d f; d=$(mkfix D1013); mkdir -p "$d/hooks" "$d/scripts"
    for f in hooks/backlog-reading-refresh.sh scripts/backlog-archive.sh scripts/calibrate.py scripts/defect-class-carriers.py; do
        printf '#!/usr/bin/env bash\n# корни (/tmp, /var/folders) — у владельца\n' > "$d/$f"; done
    echo "CLAUDSOUL_REPO=$d"; }
# Зелёная сторона D1020 — ДЕРЕВО, чей страж слияния на сухом прогоне отбивает ветку пункта с «нет — …» и пропускает
# ветку с «не дефект — …»: проба копируется из CLAUDSOUL_REPO и судит заглушку по теме последнего коммита ветки.
# Сторона по ПОВЕДЕНИЮ заглушки; настоящий признак держат ноги test_merge_root_gate.sh.
green_D1020() { local d; d=$(mkfix D1020); mkdir -p "$d/hooks/tests/fixtures"
    cp "$REPO/hooks/tests/fixtures/probe_D1020.sh" "$d/hooks/tests/fixtures/" || return 1
    printf '%s\n' '#!/usr/bin/env bash' '[ "${1:-}" = --check ] || exit 0' \
        'case "$(git -C "$2" log -1 --format=%s "$4")" in *"(X1)"*) exit 1 ;; *) exit 0 ;; esac' \
        > "$d/hooks/merge-root-gate.sh"
    echo "CLAUDSOUL_REPO=$d"; }
# Зелёная сторона D1019 — ДЕРЕВО, чей страж слияния отбивает коммит починки без пункта и пропускает коммит починки с
# пунктом и коммит не-починки: проба копируется из CLAUDSOUL_REPO и судит заглушку по тексту команды. Сторона по
# ПОВЕДЕНИЮ заглушки; настоящий признак держат ноги test_merge_root_gate.sh.
# Зелёная сторона D1021 — ДЕРЕВО, чей страж отбивает починку без пункта в любой форме команды: проба копируется из
# CLAUDSOUL_REPO, судит заглушку и исполняет неотбитое. Сторона по ПОВЕДЕНИЮ заглушки; законный коммит той же формы
# заглушка пропускает, и он обязан войти (контроль пробы).
# Зелёная сторона D1022 — ДЕРЕВО (репозиторий git: рамка пробы — его worktree на HEAD), чей страж автотаблиц судит
# репозиторий коммита: заглушка отбивает коммит в папке сессии и молчит на `git -C <другой> commit`. Сторона по
# ПОВЕДЕНИЮ заглушки; расхождение таблиц — правка шапки хука, его заглушка не читает.
# Зелёная сторона D1023 — ДЕРЕВО, чей страж не пускает в main коммит через псевдоним с обходом ловушки: заглушка
# отбивает `git ci …` и пропускает прочее; законный коммит через `-c alias.ok=commit` входит (контроль пробы). Сторона
# по ПОВЕДЕНИЮ заглушки.
# Зелёная сторона D1025 — ДЕРЕВО, чей страж отбивает обход `git commit --no-verify` в `bash -c` и молчит на `git grep`
# с теми же словами в образце. Сторона по ПОВЕДЕНИЮ заглушки; настоящий признак держат ноги P1g–P1i test_merge_root_gate.sh.
# Зелёная сторона D1028 — ДЕРЕВО, чей страж называет «файла нет» только у вызова несуществующего файла: проба копируется
# из CLAUDSOUL_REPO вместе с живым файлом-вызовом. Сторона по ПОВЕДЕНИЮ заглушки; настоящий признак держат ноги
# test_undefined_function_*.sh.
# Зелёная сторона D1033 — ДЕРЕВО, чей страж разбора снимает отказ только следом разбора в тексте хода (три «почему»),
# а чтения отказа не снимают; текст отказа речи не требует. Сторона по ПОВЕДЕНИЮ заглушки; настоящий признак держат
# ноги «след разбора» test_five_whys_gate.sh.
green_D1033() { local d; d=$(mkfix D1033); mkdir -p "$d/hooks/tests/fixtures"
    cp "$REPO/hooks/tests/fixtures/probe_D1033.sh" "$d/hooks/tests/fixtures/" || return 1
    printf '%s\n' '#!/usr/bin/env bash' 'i=$(cat); case "$i" in *Write*) ;; *) exit 0 ;; esac' \
        't=$(jq -r .transcript_path <<< "$i"); s=$(jq -r .session_id <<< "$i")' \
        '[ -f "$STATE_DIR/error_streak_fired_$s" ] || exit 0' \
        '[ "$(grep -o "Почему" "$t" | wc -l)" -ge 3 ] && exit 0' \
        'echo "{\"hookSpecificOutput\":{\"permissionDecision\":\"deny\",\"permissionDecisionReason\":\"rules/CLAUDE.md, Step 2\"}}"' \
        > "$d/hooks/five-whys-gate.sh"
    echo "CLAUDSOUL_REPO=$d"; }
# Зелёная сторона D1034 — ДЕРЕВО, чей страж при отказе пишет `deferred`, а после снятия того же хода — исход снятия
# (`chain-spoken` разбором, `recorded` названным исходом; до D1035 — `looked` тремя чтениями) той же пары «ход,
# сигнал». Сторона по ПОВЕДЕНИЮ заглушки; настоящий дедуп судит проба на дереве CLAUDSOUL_REPO.
green_D1034() { local d; d=$(mkfix D1034); mkdir -p "$d/hooks/tests/fixtures"
    cp "$REPO/hooks/tests/fixtures/probe_D1034.sh" "$d/hooks/tests/fixtures/" || return 1
    cat > "$d/hooks/five-whys-gate.sh" <<'STUB'
#!/usr/bin/env bash
i=$(cat); case "$i" in *Write*) ;; *) exit 0 ;; esac
t=$(jq -r .transcript_path <<< "$i"); s=$(jq -r .session_id <<< "$i"); j="$STATE_DIR/outcome-$s.jsonl"
[ -f "$STATE_DIR/error_streak_fired_$s" ] || exit 0
if [ "$(grep -o "Почему" "$t" | wc -l)" -ge 3 ]; then echo '{"key":"k","signal":"streak","outcome":"chain-spoken"}' >> "$j"; exit 0; fi
if grep -q '"key":"manual-[0-9]*","signal":"streak"' "$j" 2>/dev/null; then echo '{"key":"k","signal":"streak","outcome":"recorded"}' >> "$j"; exit 0; fi
echo '{"key":"k","signal":"streak","outcome":"deferred"}' >> "$j"
echo '{"hookSpecificOutput":{"permissionDecision":"deny"}}'
STUB
    echo "CLAUDSOUL_REPO=$d"; }
# Зелёная сторона D1035 — ДЕРЕВО, чей страж отказывает без исхода, чтения не считает и снимает отказ записью исхода
# повода (ключ manual-), дописывая паре хода `recorded`. Сторона по ПОВЕДЕНИЮ заглушки; настоящего стража судит проба на
# дереве CLAUDSOUL_REPO.
green_D1035() { local d; d=$(mkfix D1035); mkdir -p "$d/hooks/tests/fixtures"
    cp "$REPO/hooks/tests/fixtures/probe_D1035.sh" "$d/hooks/tests/fixtures/" || return 1
    cat > "$d/hooks/five-whys-gate.sh" <<'STUB'
#!/usr/bin/env bash
i=$(cat); case "$i" in *Write*) ;; *) exit 0 ;; esac
s=$(jq -r .session_id <<< "$i"); j="$STATE_DIR/outcome-$s.jsonl"
[ -f "$STATE_DIR/error_streak_fired_$s" ] || exit 0
if grep -q '"key":"manual-[0-9]*","signal":"streak"' "$j" 2>/dev/null; then echo '{"key":"k","signal":"streak","outcome":"recorded"}' >> "$j"; exit 0; fi
echo '{"key":"k","signal":"streak","outcome":"deferred"}' >> "$j"
echo '{"hookSpecificOutput":{"permissionDecision":"deny","permissionDecisionReason":"⛔ ОТКАЗ: у повода нет названного исхода — DIS_SESSION=k bash scripts/outcome.sh disproved streak \"чем\""}}'
STUB
    echo "CLAUDSOUL_REPO=$d"; }
# Зелёная сторона D1036 — ДЕРЕВО, чей страж при поводе отказывает коду и SKILL.md, а документ и одиночное дописывание
# с маркером в кавычках пропускает. Сторона по ПОВЕДЕНИЮ заглушки; настоящего стража судит проба на дереве CLAUDSOUL_REPO.
green_D1036() { local d; d=$(mkfix D1036); mkdir -p "$d/hooks/tests/fixtures"
    cp "$REPO/hooks/tests/fixtures/probe_D1036.sh" "$d/hooks/tests/fixtures/" || return 1
    cat > "$d/hooks/five-whys-gate.sh" <<'STUB'
#!/usr/bin/env bash
i=$(cat); s=$(jq -r .session_id <<< "$i"); [ -f "$STATE_DIR/error_streak_fired_$s" ] || exit 0
t=$(jq -r .tool_name <<< "$i"); f=$(jq -r '.tool_input.file_path // ""' <<< "$i"); c=$(jq -r '.tool_input.command // ""' <<< "$i")
deny() { echo '{"hookSpecificOutput":{"permissionDecision":"deny","permissionDecisionReason":"⛔ ОТКАЗ: у повода нет названного исхода"}}'; exit 0; }
case "$t" in
  Write|Edit|MultiEdit) case "$f" in *SKILL.md|*CLAUDE.md) deny ;; *.md|*.txt|*.log) exit 0 ;; *) deny ;; esac ;;
  Bash) first=${c%%$'\n'*}
        if [[ $first =~ ^(cd\ [^\&]*\&\&\ *)?cat\ *\>\>\ *[^\ ]+\.(md|txt|log)\ *\<\<\ *[\'\"]([A-Za-z_]+)[\'\"]\ *$ ]]; then
            m=${BASH_REMATCH[3]}; tail=$(printf '%s\n' "$c" | awk -v m="$m" 'f{print} !f && $0==m {f=1}')
            [ -z "$(printf '%s' "$tail" | tr -d '[:space:]')" ] && exit 0
        fi
        case "$c" in *">"*|*"sed -i"*|*tee*) deny ;; esac; exit 0 ;;
esac
exit 0
STUB
    echo "CLAUDSOUL_REPO=$d"; }
# Зелёная сторона D1032 — БАЗА, где ребро вверх записано парой «вид: цель»: разборщик видит его, проба → 0.
# Разборщик настоящий (копия `hooks/lib/link_symmetry.py`), подменяется только база.
green_D1032() { local d; d=$(mkfix D1032); mkdir -p "$d/hooks/tests/fixtures" "$d/hooks/lib" "$d/kb"
    cp "$REPO/hooks/tests/fixtures/probe_D1032.sh" "$d/hooks/tests/fixtures/" || return 1
    cp "$REPO/hooks/lib/link_symmetry.py" "$d/hooks/lib/" || return 1
    printf '%s\n' '---' 'name: x' 'edges:' '  - confirms: pattern-x.md' '---' 'тело' > "$d/kb/case-x.md"
    printf '%s\n' "CLAUDSOUL_REPO=$d" "LESSONS_DIR=$d/kb"; }
# Зелёная сторона D1030 — ДЕРЕВО, чей писатель переработки ставит время первым полем, а прибор исходов не
# одобряет стража по ярлыкам и называет, что действие миром не измерено. Сторона по ПОВЕДЕНИЮ заглушек;
# настоящие держат T1f test_rework_detector.sh и T16 test_outcome_journal.sh.
green_D1030() { local d; d=$(mkfix D1030); mkdir -p "$d/hooks/tests/fixtures" "$d/scripts"
    cp "$REPO/hooks/tests/fixtures/probe_D1030.sh" "$d/hooks/tests/fixtures/" || return 1
    printf '%s\n' '#!/usr/bin/env bash' 'case "$(cat)" in *Edit*)' \
        '  [ -f "$STATE_DIR/e" ] && printf "{\"ts\":\"2026-10-23T00:00:00Z\",\"path\":\"/repo/x.sh\",\"cycles\":2}\n" >> "$STATE_DIR/rework-fired-p1.jsonl"' \
        '  touch "$STATE_DIR/e" ;; esac' > "$d/hooks/rework-detector.sh"
    printf '%s\n' '#!/usr/bin/env bash' 'echo "  rework: срабатываний 3 — действие стража миром не измерено"' \
        > "$d/scripts/outcome-share.sh"
    echo "CLAUDSOUL_REPO=$d"; }
# Зелёная сторона D1029 — ДЕРЕВО, чей страж разбора в проекте с картой снимает отказ изменением карты либо новым
# пунктом, а не чтениями, и пропускает запись в носитель исхода, в том числе через Bash без других целей. Сторона по
# ПОВЕДЕНИЮ заглушки; настоящий признак держат ноги «карта» и «носитель» test_five_whys_gate.sh (ветка починки).
green_D1029() { local d; d=$(mkfix D1029); mkdir -p "$d/hooks/tests/fixtures"
    cp "$REPO/hooks/tests/fixtures/probe_D1029.sh" "$d/hooks/tests/fixtures/" || return 1
    printf '%s\n' '#!/usr/bin/env bash' 'i=$(cat); g() { jq -r "$1 // \"\"" <<< "$i"; }' \
        'd=$(g .cwd); s=$(g .session_id); f=$(g .tool_input.file_path); c=$(g .tool_input.command)' \
        'no() { echo "{\"hookSpecificOutput\":{\"permissionDecision\":\"deny\"}}"; exit 0; }' \
        'fp() { { cat "$d/ROOTS.md"; grep -c "^- " "$d/BACKLOG.md"; } 2>/dev/null | cksum; }' \
        'm="$STATE_DIR/fp-$s"; [ -f "$m" ] || fp > "$m"' \
        'case "$f" in */ROOTS.md|*/SESSION.md|*/BACKLOG.md) exit 0 ;; esac' \
        'if [ -n "$c" ]; then case "$c" in *hooks/*) no ;; esac; exit 0; fi' \
        'if [ -f "$d/ROOTS.md" ]; then [ "$(fp)" != "$(cat "$m")" ] && exit 0; no; fi' \
        '[ "$(grep -c "\"Read\"" "$(g .transcript_path)")" -ge 3 ] && exit 0; no' > "$d/hooks/five-whys-gate.sh"
    echo "CLAUDSOUL_REPO=$d"; }
green_D1028() { local d; d=$(mkfix D1028); mkdir -p "$d/hooks/tests/fixtures"
    cp "$REPO/hooks/tests/fixtures/probe_D1028.sh" "$d/hooks/tests/fixtures/" || return 1
    printf '#!/usr/bin/env bash\nexit 0\n' > "$d/hooks/tests/fixtures/probe_D1018.sh"
    printf '%s\n' '#!/usr/bin/env bash' 'case "$(cat)" in *probe_NONE*) echo "Запускается файл, которого нет" ;; esac' \
        > "$d/hooks/undefined-function-check.sh"
    echo "CLAUDSOUL_REPO=$d"; }
# Зелёная сторона D1027 — ДЕРЕВО, чей страж прироста носителей называет строку только с добавленным предметом (`c.sh`):
# проба копируется из CLAUDSOUL_REPO. Сторона по ПОВЕДЕНИЮ заглушки; настоящий признак держат ноги test_carrier_growth_check.sh.
green_D1027() { local d; d=$(mkfix D1027); mkdir -p "$d/hooks/tests/fixtures"
    cp "$REPO/hooks/tests/fixtures/probe_D1027.sh" "$d/hooks/tests/fixtures/" || return 1
    printf '%s\n' '#!/usr/bin/env bash' 'cat >/dev/null' 'case "$(eval "$CARRIER_CMD")" in *c.sh*) echo "прирост: test_x.sh" ;; esac' \
        > "$d/hooks/carrier-growth-check.sh"
    echo "CLAUDSOUL_REPO=$d"; }
# Зелёная сторона D1026 — ДЕРЕВО, чей страж записи отвечает разбираемым JSON с подсказкой, а диспетчер доносит находку
# контроля и называет стража с нечитаемым ответом: проба копируется из CLAUDSOUL_REPO. Сторона по ПОВЕДЕНИЮ заглушек;
# настоящий признак держат test_pipefail_grep_q_notice.sh и свидетели диспетчера.
green_D1026() { local d; d=$(mkfix D1026); mkdir -p "$d/hooks/tests/fixtures"
    cp "$REPO/hooks/tests/fixtures/probe_D1026.sh" "$d/hooks/tests/fixtures/" || return 1
    printf '%s\n' '#!/usr/bin/env bash' 'cat >/dev/null' \
        'jq -cn "{hookSpecificOutput:{hookEventName:\"PreToolUse\",additionalContext:\"Пайп в grep -q \\\\»\"}}"' \
        > "$d/hooks/pipefail-grep-q-notice.sh"
    # Имя диспетчера собрано из частей: здесь он заглушка, и признак рода M иначе счёл бы ногу ложным носителем.
    printf '%s\n' '#!/usr/bin/env bash' 'GUARDS="g1.sh g2.sh"' 'cat >/dev/null; echo "CTL-FOUND g1"' > "$d/hooks/bash-write-""dispatch.sh"
    : > "$d/hooks/paths-lib.sh"
    echo "CLAUDSOUL_REPO=$d"; }
# Зелёная сторона D1024 — ДЕРЕВО (копия хуков), чей страж семейства документов в ловушке читает документ here-string, а
# не конвейером в `grep -q`: проба копируется из CLAUDSOUL_REPO и судит настоящий страж. Сторона по ПОВЕДЕНИЮ; контроль
# пробы — документ без новой версии назван.
green_D1024() { local d e; d=$(mkfix D1024); mkdir -p "$d/hooks/tests/fixtures"
    cp "$REPO/hooks/tests/fixtures/probe_D1024.sh" "$d/hooks/tests/fixtures/" && cp "$REPO"/hooks/*.sh "$d/hooks/" || return 1
    e='s/project_git -C "\$CWD" show ":\$doc" 2>\/dev\/null | grep -Fq "\$VER_PLAIN"/grep -Fq "$VER_PLAIN" <<< "$(project_git -C "$CWD" show ":$doc" 2>\/dev\/null)"/'  # sigpipe-ok: образец дефектной строки в выражении sed
    sed -i.bak "$e" "$d/hooks/docs-family-check.sh" || return 1
    grep -qF '<<< "$(project_git -C "$CWD" show ":$doc"' "$d/hooks/docs-family-check.sh" || return 1
    echo "CLAUDSOUL_REPO=$d"; }
green_D1025() { local d; d=$(mkfix D1025); mkdir -p "$d/hooks/tests/fixtures"
    cp "$REPO/hooks/tests/fixtures/probe_D1025.sh" "$d/hooks/tests/fixtures/" || return 1
    printf '%s\n' '#!/usr/bin/env bash' 'in=$(cat)' \
        'case "$in" in *"git commit --no-verify"*) echo "{\"hookSpecificOutput\":{\"hookEventName\":\"PreToolUse\",\"permissionDecision\":\"deny\",\"permissionDecisionReason\":\"обход\"}}" ;; esac' \
        > "$d/hooks/merge-root-gate.sh"
    echo "CLAUDSOUL_REPO=$d"; }
green_D1023() { local d; d=$(mkfix D1023); mkdir -p "$d/hooks/tests/fixtures"
    cp "$REPO/hooks/tests/fixtures/probe_D1023.sh" "$d/hooks/tests/fixtures/" || return 1
    printf '%s\n' '#!/usr/bin/env bash' 'in=$(cat)' \
        'case "$in" in *"git ci "*) echo "{\"hookSpecificOutput\":{\"hookEventName\":\"PreToolUse\",\"permissionDecision\":\"deny\",\"permissionDecisionReason\":\"обход\"}}" ;; esac' \
        > "$d/hooks/merge-root-gate.sh"
    echo "CLAUDSOUL_REPO=$d"; }
green_D1022() { local d; d=$(mkfix D1022); mkdir -p "$d/hooks/tests/fixtures"
    cp "$REPO/hooks/tests/fixtures/probe_D1022.sh" "$d/hooks/tests/fixtures/" || return 1
    printf '%s\n' '#!/usr/bin/env bash' '# revert-signal.sh — заглушка' '# en: stub' > "$d/hooks/revert-signal.sh"
    printf '%s\n' '#!/usr/bin/env bash' 'in=$(cat)' \
        'case "$in" in *"git -C"*) ;; *) echo "{\"hookSpecificOutput\":{\"hookEventName\":\"PreToolUse\",\"permissionDecision\":\"deny\",\"permissionDecisionReason\":\"таблицы\"}}" ;; esac' \
        > "$d/hooks/docs-family-check.sh"
    ( cd "$d" && git init -q . && git add -A && git -c user.email=t@t -c user.name=t commit -qm init ) >/dev/null 2>&1 || return 1
    echo "CLAUDSOUL_REPO=$d"; }
green_D1021() { local d; d=$(mkfix D1021); mkdir -p "$d/hooks/tests/fixtures"
    cp "$REPO/hooks/tests/fixtures/probe_D1021.sh" "$d/hooks/tests/fixtures/" || return 1
    printf '%s\n' '#!/usr/bin/env bash' 'in=$(cat)' \
        'case "$in" in *"без пункта"*) echo "{\"hookSpecificOutput\":{\"hookEventName\":\"PreToolUse\",\"permissionDecision\":\"deny\",\"permissionDecisionReason\":\"нет пункта\"}}" ;; esac' \
        > "$d/hooks/merge-root-gate.sh"
    echo "CLAUDSOUL_REPO=$d"; }
green_D1019() { local d; d=$(mkfix D1019); mkdir -p "$d/hooks/tests/fixtures"
    cp "$REPO/hooks/tests/fixtures/probe_D1019.sh" "$d/hooks/tests/fixtures/" || return 1
    printf '%s\n' '#!/usr/bin/env bash' 'in=$(cat)' \
        'case "$in" in *"(X1)"*|*"chore:"*) exit 0 ;; *"git commit"*"fix:"*) echo "{\"hookSpecificOutput\":{\"hookEventName\":\"PreToolUse\",\"permissionDecision\":\"deny\",\"permissionDecisionReason\":\"нет пункта\"}}" ;; esac' \
        > "$d/hooks/merge-root-gate.sh"
    echo "CLAUDSOUL_REPO=$d"; }
# Зелёная сторона D1018 — ДЕРЕВО, чей страж поправок спрашивает родителя и молчит агенту: проба копируется из
# CLAUDSOUL_REPO и судит заглушку на двух вызовах. Сторона по ПОВЕДЕНИЮ заглушки; что починка не глушит родителя,
# держат проба D463 и свидетель стража.
green_D1018() { local d; d=$(mkfix D1018); mkdir -p "$d/hooks/tests/fixtures"
    cp "$REPO/hooks/tests/fixtures/probe_D1018.sh" "$d/hooks/tests/fixtures/" || return 1
    printf '%s\n' '#!/usr/bin/env bash' 'in=$(cat)' 'case "$in" in *"\"agent_id\""*) exit 0 ;; esac' \
        'echo "{\"hookSpecificOutput\":{\"hookEventName\":\"PreToolUse\",\"permissionDecision\":\"ask\",\"permissionDecisionReason\":\"x\"}}"' \
        > "$d/hooks/user-correction-guard.sh"
    echo "CLAUDSOUL_REPO=$d"; }
# Зелёная сторона D1017 — ДЕРЕВО, чей шаблон бэклога называет исполнителя архивирования. Сторона по ФОРМЕ шаблона,
# и это законно: шаблон и есть предмет — что в нём написано, то и рождается в проекте.
green_D1017() { local d; d=$(mkfix D1017); mkdir -p "$d/templates"
    printf '%s\n' '# BACKLOG — долг проекта' '> Закрытое уносит `scripts/backlog-archive.sh run` на границе хода.' > "$d/templates/BACKLOG.md.tmpl"
    echo "CLAUDSOUL_REPO=$d"; }
# Зелёная сторона D1016 — МИР, где у каждого инициированного проекта (есть SESSION.md) лежат части нынешнего
# договора — бэклог, называющий исполнителя архивирования, и ROOTS.md, — а папка без SESSION.md не в счёте: проба
# копируется из CLAUDSOUL_REPO, каталог проектов — под HOME фикстуры. Сторона по МИРУ: её позеленят и части,
# вписанные руками.
green_D1016() { local d p; d=$(mkfix D1016); mkdir -p "$d/hooks/tests/fixtures" "$d/My Project/c/.claude-docs"
    cp "$REPO/hooks/tests/fixtures/probe_D1016.sh" "$d/hooks/tests/fixtures/" || return 1
    for p in a b; do mkdir -p "$d/My Project/$p"; printf 'x\n' > "$d/My Project/$p/SESSION.md"
        printf 'Закрытое уносит `scripts/backlog-archive.sh run`\n' > "$d/My Project/$p/BACKLOG.md"
        printf '# ROOTS\n' > "$d/My Project/$p/ROOTS.md"; done
    # Заброшенный проект без частей договора (SESSION.md старше 30 дней) не в счёте.
    mkdir -p "$d/My Project/old"; printf 'x\n' > "$d/My Project/old/SESSION.md"; touch -t 202001010000 "$d/My Project/old/SESSION.md"
    printf '%s\n' "CLAUDSOUL_REPO=$d" "HOME=$d"; }
# Зелёная сторона D1015 — ДЕРЕВО, чей вид «только оболочка» ничего не снимает: проба копируется из CLAUDSOUL_REPO и
# судит одну сторону — местный вызов не теряется. Сторона по ФОРМЕ: такую «починку» отобьют свидетели детекции.
green_D1015() { local d; d=$(mkfix D1015); mkdir -p "$d/hooks/tests/fixtures"
    cp "$REPO/hooks/tests/fixtures/probe_D1015.sh" "$d/hooks/tests/fixtures/" || return 1
    printf '%s\n' 'ds_shell_only() { printf "%s" "$1"; }' 'ds_unquoted_command() { printf "%s" "$1"; }' \
        > "$d/hooks/detection-signals-lib.sh"
    echo "CLAUDSOUL_REPO=$d"; }
# Зелёная сторона D1014 — ДЕРЕВО, где сверка показаний спит 10 с, а хук касания возвращается сразу, оставив фоном
# держателя замка полосы в своей группе процессов: проба копируется из CLAUDSOUL_REPO, мерит обоих и снимает
# держателя. Нога идёт 5 с — столько проба ждёт, чтобы предъявить, что сверка дольше срока. Сторона по ФОРМЕ
# запуска: работу фона судят ноги T17–T30 свидетеля хука.
green_D1014() { local d; d=$(mkfix D1014); mkdir -p "$d/scripts" "$d/hooks/tests/fixtures"
    cp "$REPO/hooks/tests/fixtures/probe_D1014.sh" "$d/hooks/tests/fixtures/" || return 1
    cp "$REPO/hooks/timeout-lib.sh" "$d/hooks/" || return 1
    printf '# BACKLOG\n' > "$d/BACKLOG.md"
    printf '#!/usr/bin/env bash\nsleep 10\n' > "$d/scripts/backlog-refresh-readings.sh"
    printf '%s\n' '#!/usr/bin/env bash' 'cat >/dev/null' 'l="$STATE_DIR/backlog-reading-refresh-check.lock"' \
        'set -m' 'sleep 30 </dev/null >/dev/null 2>&1 &' \
        'mkdir -p "$l" && printf "%s x\n" "$!" > "$l/owner"' 'exit 0' > "$d/hooks/backlog-reading-refresh.sh"
    echo "CLAUDSOUL_REPO=$d"; }
# Зелёная сторона D1005 — ДЕРЕВО, где у реестра замеров есть исполнитель по расписанию (задание launchd зовёт
# measurement-due.sh), а прибор отвечает «просроченных нет»: «Проверка» читает оба факта из CLAUDSOUL_REPO.
green_D1005() { local d; d=$(mkfix D1005); mkdir -p "$d/launchd" "$d/scripts"
    printf '<string>bash scripts/measurement-due.sh run</string>\n' > "$d/launchd/com.claudsoul.measurements.plist"
    printf '#!/usr/bin/env bash\necho "Замеры по расписанию: просроченных нет (по событию: 5)."\n' > "$d/scripts/measurement-due.sh"
    echo "CLAUDSOUL_REPO=$d"; }
# Зелёная сторона D1003 — ДЕРЕВО, чей прибор карты отдаёт ребро «пишет» и для прямой записи, и для записи
# через переменную: проба копирует приборы из CLAUDSOUL_REPO, и мир «запись видна» собирается подменой прибора.
green_D1003() { local d; d=$(mkfix D1003); mkdir -p "$d/scripts" "$d/hooks/tests/fixtures"
    cp "$REPO/hooks/tests/fixtures/probe_D1003.sh" "$d/hooks/tests/fixtures/" || return 1
    printf 'import sys\nsys.exit(0)\n' > "$d/scripts/dep-index.py"
    printf '%s\n' 'import json, os' \
        'n = [{"id": 1, "key": "hooks/direct.sh"}, {"id": 2, "key": "журнал:direct.jsonl"}, {"id": 3, "key": "hooks/viavar.sh"}, {"id": 4, "key": "журнал:events.jsonl"}]' \
        'e = [{"source": 1, "target": 2, "type": "пишет"}, {"source": 3, "target": 4, "type": "пишет"}]' \
        'json.dump({"nodes": n, "edges": e}, open(os.path.join("mcp-server", "visualization", "project-graph-data.json"), "w"), ensure_ascii=False)' \
        > "$d/scripts/project-graph.py"
    echo "CLAUDSOUL_REPO=$d"; }
# Зелёная сторона D1004 — ДЕРЕВО, чей диспетчер подаёт находку тем же порядком, но сообщение не называет её
# правкой команды и не велит откатывать: проба копирует диспетчер из CLAUDSOUL_REPO, и мир «авторство не
# утверждается» собирается подменой текста сообщения. Имя диспетчера собрано из частей — как у green_D487.
green_D1004() { local d _disp="bash-write-""dispatch.sh"; d=$(mkfix D1004); mkdir -p "$d/hooks/tests/fixtures"
    cp "$REPO/hooks/tests/fixtures/probe_D1004.sh" "$d/hooks/tests/fixtures/" || return 1
    cp "$REPO/hooks/paths-lib.sh" "$d/hooks/" || return 1
    cp "$REPO/hooks/state-lock-lib.sh" "$d/hooks/" 2>/dev/null || true
    sed -e 's/⛔ Правка сделана КОМАНДОЙ, и стражи записи её не видели/Файл тронут после прошлого события, автор не установлен/' \
        -e 's/Почини или откати ПРЕЖДЕ, чем коммитить\./Сверь, твоя ли это правка, прежде чем коммитить./' \
        "$REPO/hooks/$_disp" > "$d/hooks/$_disp" || return 1
    echo "CLAUDSOUL_REPO=$d"; }
# Зелёная сторона D1000 — ДОМ, где последняя расшифровка несёт пять быстрых границ хода: «Проверка» читает
# `~/.claude/projects/*/*.jsonl` через HOME, и мир «владелец не ждёт» собирается подменой дома.
green_D1000() { local d i; d=$(mkfix D1000); mkdir -p "$d/.claude/projects/p"
    for i in 1 2 3 4 5; do
        # Форма живой записи после переноса (18 октября 2026): у фонового хука поля `durationMs` нет.
        printf '{"type":"system","subtype":"stop_hook_summary","hookInfos":[{"command":"bash ~/.claude/hooks/x.sh","durationMs":1200},{"command":"bash ~/.claude/hooks/session-collector.sh"}]}\n'
    done > "$d/.claude/projects/p/s.jsonl"
    echo "HOME=$d"; echo "CLAUDSOUL_REPO=$REPO"; }
green_D331() { local d; d=$(mkfix D331); printf '{"ts":"2026-09-01T10:00:00Z","session":"s","sha":"%040d","tag":"v1.0.0","critic":"rounds","evidence":7,"since":"x..HEAD"}\n' 0 > "$d/publications.jsonl"; echo "STATE_DIR=$d"; }
# Отрицательный контроль T0 ниже берёт D307: его «Проверка» судит МИР (носители рода G по реестру), без
# фикстуры красна. До 13 сентября 2026 предметом был D335 — закрыт вердиктом «признака нет».
# Зелёная сторона D342 — ДЕРЕВО, где у каждого свидетеля-атаки предмет назван и нога
# краснеет на выхолощенном предмете. Прежняя фикстура клала пустой файл с подходящим ИМЕНЕМ
# и тем зеленила команду, судившую имя; с поведенческим прибором такая заглушка не проходит.
green_D342() { local d; d=$(mkfix D342); mkdir -p "$d/hooks/tests"
    printf '#!/usr/bin/env bash\necho MARKER\nexit 0\n' > "$d/hooks/subject.sh"
    { printf '#!/usr/bin/env bash\n'
      printf 'REPO="$(cd "$(dirname "$0")/../.." && pwd)"\n'
      printf 'out=$(bash "$REPO/hooks/subject.sh" 2>&1)\n'
      printf 'case "$out" in *MARKER*) exit 0 ;; *) exit 1 ;; esac\n'
    } > "$d/hooks/tests/test_adv_honest.sh"
    mkdir -p "$d/scripts" "$d/.claude-docs"; cp "$REPO/scripts/behavior-condition-probe.sh" "$d/scripts/"
    # ВХОД ПРИБОРА СМЕНИЛСЯ 20 сентября 2026: предмет свидетеля он спрашивает у индекса
    # зависимостей, а не выводит регуляркой. Фикстура обязана дать ему этот вход, иначе
    # «не позеленела» значит «рамка не собралась», а не «починка не работает».
    printf '# path\tsha\tdeps\tdocs\ttests\tnames\n' > "$d/.claude-docs/dep-index.tsv"
    printf 'hooks/subject.sh\tx\t\t\thooks/tests/test_adv_honest.sh\t\n' >> "$d/.claude-docs/dep-index.tsv"
    chmod +x "$d/hooks/subject.sh" "$d/hooks/tests/test_adv_honest.sh" "$d/scripts/behavior-condition-probe.sh"
    ( cd "$d" && git init -q . && git add -A \
        && git -c user.email=t@t -c user.name=t commit -qm init ) >/dev/null 2>&1 || { echo "подготовка мира не удалась: hooks/tests/test_backlog_green_side.sh:$LINENO" >&2; exit 1; }
    # «Проверка» D342 читает СЛЕД прибора, а не гоняет его (прогон идёт минутами и в срок
    # пересчёта показаний не укладывается). Значит зелёная сторона обязана этот след
    # ПОСТАВИТЬ: прогнать прибор в своём дереве со СВОИМ состоянием, иначе она предъявляет
    # зелень по следу рабочего дерева — то есть не предъявляет ничего.
    # Поймано 21 сентября 2026 прогоном: после смены «Проверки» на чтение следа фикстура
    # осталась от прежней редакции и покраснела.
    mkdir -p "$d/.state"
    ( cd "$d" && STATE_DIR="$d/.state" CLAUDSOUL_REPO="$d" CLAUDSOUL_ROOT="$d" \
        bash scripts/behavior-condition-probe.sh ) > "$d/.probe.log" 2>&1
    printf 'код прибора: %s\n' "$?" >> "$d/.probe.log"
    echo "CLAUDSOUL_REPO=$d"; echo "STATE_DIR=$d/.state"; }
# Зелёная сторона D474 — ДЕРЕВО, где у КАЖДОГО свидетеля-атаки предмет объявлен строкой
# шапки `# СУДИТ:`, поэтому перечень `--unresolved` пуст и команда даёт 0. Предмет пункта —
# именно перечень, а не ложная зелень: прибор судит лишь тех, чей предмет он знает.
# Зелёная сторона D476 — СВИДЕТЕЛЬ, в котором есть живая пара «нога + патчер», патчащая файл
# НА МЕСТЕ: проба выводит ногу по свойству, собирает рамку и различает исправный патчер от
# упавшего. Фикстура судит именно это: не имя ноги (его проба больше не знает), а наличие
# ноги, чей патч виден сравнением. В рабочем дереве такой ноги сейчас нет — потому «Проверка»
# пункта красна, а здесь зелена.
# D478 — класс «рамка» ловит гонку за общее состояние. Дерево со своим STATE_DIR, где журнал
# прибора несёт framed=0: показание пункта читает последнюю строку журнала.
green_D478() { local d; d=$(mkfix D478); mkdir -p "$d/state"
    printf '{"ts":"2026-09-24T00:00:00Z","repo":"%s","total":1,"resolved":1,"judged":1,"vacuous":0,"skipped":0,"framed":0,"bound":0,"slow":0,"selfjudge":0,"stale":0,"tree":0,"realtree":0,"unresolved":0}\n' "$d" > "$d/state/behavior-condition-probe.jsonl"
    # ПО СТРОКЕ НА ПЕРЕМЕННУЮ: драйвер читает окружение построчно (`while IFS= read -r`,
    # :421), и обе в одной строке склеились бы в одно значение с пробелом внутри. Формат
    # нигде не был объявлен, а все прежние фикстуры отдавали ОДНУ переменную — поэтому
    # дефект ждал первой многопеременной (24 сентября 2026).
    printf '%s\n' "CLAUDSOUL_REPO=$d" "STATE_DIR=$d/state"; }

# D498 — цена события хука не растёт с накопленным. Дерево, где хуки читают только последний ход
# и не обходят каталог состояния: та же проба, разности около нуля, контроли сходятся → 0.
green_D498() { local d; d=$(mkfix D498); mkdir -p "$d/hooks"
    cat > "$d/hooks/user-correction-guard.sh" <<'EOF'
#!/usr/bin/env bash
cat >/dev/null
echo '{"systemMessage":"поправка к объявленному"}'
EOF
    printf '#!/usr/bin/env bash\ncat >/dev/null\nexit 0\n' > "$d/hooks/five-whys-gate.sh"
    cat > "$d/hooks/output-language-check.sh" <<'EOF'
#!/usr/bin/env bash
S=$(jq -r '.session_id')
echo '{}' >> "$STATE_DIR/output-violations-${S}.jsonl"
EOF
    printf 'throttle_file() { printf "%%s/%%s-fired-%%s.jsonl\\n" "$1" "$2" "$3"; }\n' > "$d/hooks/throttle-lib.sh"
    # Сводки по сессии (нога L4): журнал активности пишется, цена от истории не зависит.
    cat > "$d/hooks/activity-flush-lib.sh" <<'EOF'
activity_flush() { mkdir -p "$3/.claude-docs" && echo x > "$3/.claude-docs/session-activity.md"; }
EOF
    printf 'shlang_candidates() { :; }\n' > "$d/hooks/shared-language-lib.sh"
    echo "CLAUDSOUL_REPO=$d"; }

# D510 — сдача отчёта вызовом инструмента не объявляется обрывом. Дерево, где страж молчит на
# расшифровке, кончающейся вызовом SubagentHandback без строки результата: команда пункта даёт 0.
green_D510() { local d; d=$(mkfix D510); mkdir -p "$d/hooks"
    printf '#!/usr/bin/env bash\ncat >/dev/null\nexit 0\n' > "$d/hooks/subagent-outcome.sh"
    echo "CLAUDSOUL_REPO=$d"; }

# D511 — признак повторной правки судит только пишущий инструмент. Дерево, где страж поправок
# отвечает на Edit и молчит на Read: контроль «Проверки» жив, команда пункта даёт 0.
green_D511() { local d; d=$(mkfix D511); mkdir -p "$d/hooks"
    printf '%s\n' '#!/usr/bin/env bash' 'grep -q "\"tool_name\":\"Edit\"" && echo permissionDecision' 'exit 0' > "$d/hooks/user-correction-guard.sh"
    echo "CLAUDSOUL_REPO=$d"; }

# D513 — отказ стража разбора не требует речи модели и снимается осмотром. Дерево, где страж
# отказывает записи без слова «произнес…» и пропускает её после трёх читающих вызовов Bash:
# контроль «Проверки» жив, команда пункта даёт 0.
green_D513() { local d; d=$(mkfix D513); mkdir -p "$d/hooks"
    printf '%s\n' '#!/usr/bin/env bash' 'i=$(cat); c="$STATE_DIR/looks"' \
        'if grep -q "\"tool_name\":\"Bash\"" <<< "$i"; then echo x >> "$c"; exit 0; fi' \
        '[ "$(grep -c "" "$c" 2>/dev/null || true)" -ge 3 ] 2>/dev/null || echo "{\"hookSpecificOutput\":{\"permissionDecision\":\"deny\"}}"' \
        'exit 0' > "$d/hooks/five-whys-gate.sh"
    echo "CLAUDSOUL_REPO=$d"; }

# D512 — закрытые пункты бэклога проекта уезжают в архив на Stop по признаку согласия.
# «Проверка» пункта зовёт свидетеля поведения хука; дерево, где свидетель есть и зелёный, → 0.
# Красная сторона — дерево без свидетеля либо с красным (хук до починки: 4 провала из 9).
green_D512() { local d; d=$(mkfix D512); mkdir -p "$d/hooks/tests"
    printf '%s\n' '#!/usr/bin/env bash' 'exit 0' > "$d/hooks/tests/test_session_collector_local_archive.sh"
    echo "CLAUDSOUL_REPO=$d"; }

# D514 — код из папки сессии на Stop не исполняется. Дерево, где сборщик называет долг проекта,
# не исполняя его скриптов, а гейт исполняет «Проверку» только по абсолютному пути: оба контроля
# пробы живы, оба носителя молчат → 0. Красная сторона — живое дерево 4 октября 2026: код 1, A и B.
green_D514() { local d; d=$(mkfix D514); mkdir -p "$d/hooks/tests/fixtures"
    cp "$REPO/hooks/tests/fixtures/probe_D514.sh" "$d/hooks/tests/fixtures/"
    cp "$REPO/hooks/tests/alerts-read.sh" "$d/hooks/tests/"   # сосед пробы — D1309 (скептик, L3)
    printf '%s\n' '#!/usr/bin/env bash' 'cat >/dev/null' \
        'echo "1 открытых пункт(ов) в BACKLOG.md этого проекта" >> "$STATE_DIR/pending-alerts.txt"' \
        ': > "$STATE_DIR/transcript-fold-activity-stats-stub"' \
        'exit 0' > "$d/hooks/session-collector.sh"
    printf '%s\n' '#!/usr/bin/env bash' 'cat >/dev/null' \
        'case "${CG_LOCAL_BACKLOG:-}" in /*) touch "${CG_LOCAL_BACKLOG%/proj/BACKLOG.md}/ran" ;; esac' \
        'exit 0' > "$d/hooks/completion-gate.sh"
    echo "CLAUDSOUL_REPO=$d"; }

# D515 — хуки, срабатывающие сами, не исполняют программ из настроек чужого репозитория. Дерево,
# где каждый носитель зовёт git своей подкомандой с погашенными fsmonitor, подписью и фильтром
# песочного репозитория: контроли пробы видят вызов, метки программ не появляются, → 0.
# Имена заглушек собраны из частей: настоящие хуки фикстура не судит, и буквальное имя сделало бы
# её ложным носителем рода M (песочница голым mktemp рядом с хуком, отбрасывающим временные пути).
green_D515() { local d g; d=$(mkfix D515); mkdir -p "$d/hooks/tests/fixtures"
    cp "$REPO/hooks/tests/fixtures/probe_D515.sh" "$d/hooks/tests/fixtures/"
    g='git -c core.fsmonitor=false -c log.showSignature=false -c filter.evil.clean='
    _stub() { printf '%s\n' '#!/usr/bin/env bash' 'cat >/dev/null' "$2" 'exit 0' > "$d/hooks/$1.sh"; }
    _stub rework-detector "$g status --porcelain >/dev/null 2>&1"
    _stub impact-inject "$g diff --name-only HEAD >/dev/null 2>&1; $g ls-files >/dev/null 2>&1"
    _stub bash-write-dispatch "$g diff -z --name-only HEAD >/dev/null 2>&1"
    _stub revert-signal "$g log -n 1 >/dev/null 2>&1"
    _stub auto-scanner "$g status --porcelain >/dev/null 2>&1; $g log -1 >/dev/null 2>&1"
    printf '%s\n' "narrative_compose() { $g -C \"\$1\" log --oneline; }" > "$d/hooks/narrative-compose-lib.sh"
    echo "CLAUDSOUL_REPO=$d"; }

# D516 — impact-inject не исполняет прибор карты из папки сессии. Дерево, где хук исполняет
# прибор только в рабочих копиях владельца — по списку worktree его репозитория, со снятыми
# переменными GIT_*: контроли пробы (главная копия, worktree) видят исполнение, предметы — нет, → 0.
green_D516() { local d; d=$(mkfix D516); mkdir -p "$d/hooks/tests/fixtures"
    cp "$REPO/hooks/tests/fixtures/probe_D516.sh" "$d/hooks/tests/fixtures/"
    printf '%s\n' '#!/usr/bin/env bash' 'cat >/dev/null' 'p=$(pwd -P)' \
        'env -u GIT_DIR -u GIT_COMMON_DIR -u GIT_WORK_TREE git -C "${CLAUDSOUL_ROOT:-/nonexistent}" worktree list --porcelain 2>/dev/null \' \
        '  | while IFS= read -r w; do case "$w" in "worktree "*) ;; *) continue ;; esac' \
        '      [ "$(cd "${w#worktree }" 2>/dev/null && pwd -P)" = "$p" ] && { python3 scripts/project-graph.py; break; }; done' \
        'exit 0' > "$d/hooks/impact-inject.sh"
    echo "CLAUDSOUL_REPO=$d"; }

# D517 — docs-family-check не исполняет скрипты из чужой папки сессии. Дерево, где страж зовёт
# генератор и сверщик только когда папка сессии — копия, названная владельцем: контроль пробы
# видит оба исполнения, предмет — ни одного, → 0.
green_D517() { local d; d=$(mkfix D517); mkdir -p "$d/hooks/tests/fixtures"
    cp "$REPO/hooks/tests/fixtures/probe_D517.sh" "$d/hooks/tests/fixtures/"
    printf '%s\n' '#!/usr/bin/env bash' 'cat >/dev/null' \
        '[ "$(pwd -P)" = "$(cd "${CLAUDSOUL_ROOT:-/nonexistent}" 2>/dev/null && pwd -P)" ] || exit 0' \
        'bash scripts/regen-readme-skills.sh' \
        'git diff --quiet -- VERSION 2>/dev/null || bash scripts/docs-refresh-claims.sh --check' \
        'exit 0' > "$d/hooks/docs-family-check.sh"
    echo "CLAUDSOUL_REPO=$d"; }

# D518 — doc-impact-check не исполняет прибор индекса из чужой папки сессии. Дерево, где страж
# зовёт прибор только из копии владельца — той же сверкой, что живой хук (paths-lib копируется в
# фикстуру): контроли пробы (копия, подкаталог, worktree) видят исполнение, предметы — ни одного, → 0.
green_D518() { local d; d=$(mkfix D518); mkdir -p "$d/hooks/tests/fixtures"
    cp "$REPO/hooks/tests/fixtures/probe_D518.sh" "$d/hooks/tests/fixtures/"
    cp "$REPO/hooks/paths-lib.sh" "$d/hooks/"
    printf '%s\n' '#!/usr/bin/env bash' 'cat >/dev/null; . "$PATHS_LIB" || exit 0' \
        'R=$(git rev-parse --show-toplevel 2>/dev/null) && project_owner_copy "$R" "$PWD" || exit 0' \
        'cd "$R" && python3 scripts/dep-index.py' 'exit 0' > "$d/hooks/doc-impact-check.sh"
    echo "CLAUDSOUL_REPO=$d"; }

# D527 — владелец маркера отказа узнаёт отказ с префиксом харнесса. Дерево, где выражение допускает
# `PreToolUse:<инструмент> hook error:` перед маркером и по-прежнему якорится на начало, → 0.
green_D527() { local d; d=$(mkfix D527); mkdir -p "$d/hooks"
    printf '%s\n' 'DENY_MARK_RE="\\A\\s*(PreToolUse:[A-Za-z_]+ hook error:\\s*)?(⛔|🛑|🚫)"' \
        'deny_mark_is_denial() { jq -e -n --arg t "${1-}" --arg re "$DENY_MARK_RE" '"'"'$t | test($re)'"'"' >/dev/null 2>&1; }' \
        > "$d/hooks/deny-mark-lib.sh"
    echo "CLAUDSOUL_REPO=$d"; }

# D526 — страж коммита после отклонённого `git switch -c`. «Проверка» с 11 октября 2026 — прогон теста
# стража (ноги T12 повод с `-q`, T13 Л1 после скептика). Фикстура — тест, дающий 0: заглушка ФОРМЫ,
# закрывать пункт по делу (тест настоящего стража), а не по этой ноге.
green_D526() { local d; d=$(mkfix D526); mkdir -p "$d/hooks/tests"
    printf '#!/usr/bin/env bash\nexit 0\n' > "$d/hooks/tests/test_denied_branch_commit_guard.sh"
    echo "CLAUDSOUL_REPO=$d"; }

# D525 — страж `git stash`. Дерево, где страж отвечает решением на команду с `git stash -q`, → 0;
# заглушка судит одну команду — поведение на list/show держит тест стража.
green_D525() { local d; d=$(mkfix D525); mkdir -p "$d/hooks"
    printf '%s\n' '#!/usr/bin/env bash' 'grep -q "git stash" && printf "%s\n" '"'"'{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny"}}'"'"'' \
        > "$d/hooks/git-stash-guard.sh"; chmod +x "$d/hooks/git-stash-guard.sh"
    echo "CLAUDSOUL_REPO=$d"; }

# D523 — у скептика есть вид атаки rule_choice. «Проверка» судит СЛОВО в SKILL.md, то есть форму:
# фикстура со словом зеленит её, не решив ничего, — закрывать пункт по делу, а не по этой ноге.
green_D523() { local d; d=$(mkfix D523); mkdir -p "$d/skills/adversary"
    printf 'rule_choice\n' > "$d/skills/adversary/SKILL.md"
    echo "CLAUDSOUL_REPO=$d"; }

# D520 — сигналы переработки не горят на свидетеле зелёной стороны. Дерево, где перечни исключений
# обоих детекторов называют свидетеля: на нём сигналы молчат, на обычном файле горят, → 0.
green_D520() { local d; d=$(mkfix D520); mkdir -p "$d/hooks/tests/fixtures"
    cp "$REPO/hooks/tests/fixtures/probe_D520.sh" "$d/hooks/tests/fixtures/"
    cp "$REPO"/hooks/*.sh "$d/hooks/"
    apply_patch -c 'import sys
for p,o,n in ((sys.argv[1], r"|README|README\.ru)", r"|README|README\.ru|test_backlog_green_side)"),
              (sys.argv[2], r"|ROOTS)\.md$", r"|ROOTS)\.md$|/test_backlog_green_side\.sh$")):
    s=open(p,encoding="utf-8").read(); assert s.count(o)==1, p
    open(p,"w",encoding="utf-8").write(s.replace(o,n))' "$d/hooks/revert-signal.sh" "$d/hooks/rework-detector.sh" || return 1
    echo "CLAUDSOUL_REPO=$d"; }

# D519 — стражи на собственном commit/add агента не исполняют программ из настроек чужого
# репозитория. Дерево, где девять стражей зовут git через обёртку с той же сверкой, что project_git
# (fsmonitor, подпись и фильтры из настроек репозитория погашены): проба не видит меток, → 0.
green_D519() { local d; d=$(mkfix D519); mkdir -p "$d/hooks/tests/fixtures"
    cp "$REPO/hooks/tests/fixtures/probe_D519.sh" "$d/hooks/tests/fixtures/"
    cp "$REPO"/hooks/*.sh "$d/hooks/"; cp -R "$REPO/hooks/lib" "$d/hooks/"   # code-review-reminder берёт функцию из hooks/lib
    printf '%s\n' 'git() { local _a=() _o=(-c core.fsmonitor=false -c log.showSignature=false) _s _k _r' \
        '    while [ "${1:-}" = "-C" ] && [ $# -ge 2 ]; do _a+=(-C "$2"); shift 2; done' \
        '    while read -r _s _k _r; do case "$_s" in global|system|command) ;; *) _o+=(-c "$_k=") ;; esac' \
        '    done < <(command git ${_a[@]+"${_a[@]}"} config --show-scope --get-regexp "^filter\..*\.(clean|smudge|process)$" 2>/dev/null)' \
        '    command git ${_a[@]+"${_a[@]}"} "${_o[@]}" "$@"; }' > "$d/hooks/_git_wrap.sh"
    apply_patch -c 'import sys
for p in sys.argv[1:]:
    s=open(p,encoding="utf-8").read(); i=s.index("\n")+1
    open(p,"w",encoding="utf-8").write(s[:i]+". \"$(dirname \"${BASH_SOURCE[0]}\")/_git_wrap.sh\"\n"+s[i:])' \
        "$d"/hooks/{backlog-vanish-check,skill-review-check,quality-gate-check,mechanism-has-consumer,git-add-sweep-guard,code-review-reminder,skill-name-ascii-guard,module-doc-check,changelog-reminder}.sh \
        || return 1
    echo "CLAUDSOUL_REPO=$d"; }

# D521 — тревога «не тот носитель» судит по записанному пункту. Дерево, где функция читает строки,
# добавленные в бэклог проекта (через project_git — бэклог в чужой папке), а не текст ответа, → 0.
green_D521() { local d; d=$(mkfix D521); mkdir -p "$d/hooks/tests/fixtures"
    cp "$REPO/hooks/tests/fixtures/probe_D521.sh" "$d/hooks/tests/fixtures/"
    cp "$REPO/hooks/paths-lib.sh" "$d/hooks/"
    printf '%s\n' 'dpr_foreign_carrier() {' \
        '    [ -n "${CLAUDSOUL_ROOT:-}" ] && [ -n "${LOCAL_BACKLOG:-}" ] || return 1' \
        '    [ "$LOCAL_BACKLOG" = "$CLAUDSOUL_ROOT/BACKLOG.md" ] && return 1' \
        '    _d=$(project_git -C "$(dirname "$LOCAL_BACKLOG")" diff --no-ext-diff --no-textconv -U0 -- "$(basename "$LOCAL_BACKLOG")" 2>/dev/null)' \
        '    grep -qE "^\+[^+].*(hooks/[a-z0-9_-]+\.sh|ClaudSoul|\.claude/hooks)" <<< "$_d"' \
        '}' > "$d/hooks/declared-problem-recorded.sh"
    echo "CLAUDSOUL_REPO=$d"; }

# D488 — срабатывание knowledge-activator укладывается в секунды. Дерево, где хук отвечает
# сразу: «Проверка» судит хук РЕПОЗИТОРИЯ с пределом 5 с и даёт 0 (D499, 1 октября 2026).
# База знаний — предмет замера (предусловие «Проверки», 2 октября 2026): фикстура несёт свою,
# иначе на машине без базы (CI) нога получила бы код 2, а не 0.
# D509 — интерпретатор сигналов без jq на каждый узел. Дерево, где страж разбирает вход
# одним jq: счётчик показывает один запуск, команда пункта даёт 0.
green_D509() { local d; d=$(mkfix D509); mkdir -p "$d/hooks" "$d/home/.claude/global-lessons"
    printf '%s\n' '#!/usr/bin/env bash' 'jq -c . >/dev/null 2>&1' > "$d/hooks/blocker-tier-check.sh"
    printf '%s\n' "CLAUDSOUL_REPO=$d" "HOME=$d/home"; }

# D508 — каталог состояния берётся из STATE_DIR. Дерево, где страж и счёт говорящего пишут в
# STATE_DIR, а частных умолчаний мимо него нет: под подменённым HOME пусто, в песочнице файлы.
green_D508() { local d; d=$(mkfix D508); mkdir -p "$d/hooks/lib" "$d/home/.claude/global-lessons"
    printf '%s\n' '#!/usr/bin/env bash' 'cat >/dev/null; : > "$STATE_DIR/blocker-fired-x.jsonl"' > "$d/hooks/blocker-tier-check.sh"
    printf '%s\n' 'score_speaker() { echo primary > "$STATE_DIR/session-speaker_$1"; }' > "$d/hooks/adaptive-stats-lib.sh"
    printf '%s\n' "CLAUDSOUL_REPO=$d" "HOME=$d/home"; }

# D507 — каждый родитель домена раскрывается своей строкой. Дерево, где раскрытие отдаёт
# обоих родителей shell-scripting отдельными строками: команда пункта даёт 0.
green_D507() { local d; d=$(mkfix D507); mkdir -p "$d/hooks" "$d/domains"
    printf '%s\n' 'expand_domains_from_context() { printf "%s\n" "shell_scripting 30" "software-development 20" "devops 20"; }' \
        > "$d/hooks/domain-graph-lib.sh"
    : > "$d/domains/shell-scripting.md"
    echo "CLAUDSOUL_REPO=$d"; }

# D506 — страж находит файлы с флагом blocker без awk на каждый файл. Дерево, где страж
# отвечает без единого запуска awk: счётчик пуст, команда пункта даёт 0.
green_D506() { local d; d=$(mkfix D506); mkdir -p "$d/hooks" "$d/home/.claude/global-lessons"
    printf '#!/usr/bin/env bash\nexit 0\n' > "$d/hooks/blocker-tier-check.sh"
    printf '%s\n' "CLAUDSOUL_REPO=$d" "HOME=$d/home"; }

green_D488() { local d; d=$(mkfix D488); mkdir -p "$d/hooks" "$d/home/.claude/global-lessons"
    printf '#!/usr/bin/env bash\nexit 0\n' > "$d/hooks/knowledge-activator.sh"
    printf '%s\n' "CLAUDSOUL_REPO=$d" "HOME=$d/home"; }

# D486 — ребро «Держит» берётся из явной формы поля. Дерево, где разбора прозы поля
# регулярным `R\d+` нет: команда пункта приёма не находит и даёт 0.
green_D486() { local d; d=$(mkfix D486); mkdir -p "$d/scripts"
    printf '%s\n' 'print("── ПОРЯДОК РЕМОНТА ──")' 'print("  1. R1 — 1 носителей, держит R2")' > "$d/scripts/root-map.py"
    echo "CLAUDSOUL_REPO=$d"; }

# D485 — многоагентный цикл противника исполняет шаги скилла: цикл лежит в поставке скилла,
# скилл велит звать его, сверка копий и поведения зелёная. Такое дерево даёт 0.
green_D485() { local d; d=$(mkfix D485); mkdir -p "$d/skills/adversary/references" "$d/hooks/tests"
    printf 'export const meta = { name: "adversary-rounds" }\n' > "$d/skills/adversary/references/adversary-rounds.js"
    printf 'Workflow scriptPath: references/adversary-rounds.js\n' > "$d/skills/adversary/SKILL.md"
    printf '#!/usr/bin/env bash\nexit 0\n' > "$d/hooks/tests/test_adversary_rounds_parity.sh"
    echo "CLAUDSOUL_REPO=$d"; }

# D484 — цепочка, переданная вызовом `: <<'CHAIN' … CHAIN`, засчитывается гейтом разбора (3 октября
# 2026: промежуточная речь с Opus 5.5 ложится в расшифровку пересказом, вход вызова — дословно).
# Дерево, где гейт читает цепочку и из канала вызова: отказ без неё, проход с ней — проба даёт 0.
# Прежняя фикстура (строка ожидания перед решением) мерила опровергнутую гипотезу «текст опаздывает».
green_D484() { local d; d=$(mkfix D484); mkdir -p "$d/hooks"
    printf '%s\n' '#!/usr/bin/env bash' 'p=$(jq -r ".transcript_path // \"\"")' \
        'grep -q "<<'"'"'CHAIN'"'"'" "$p" 2>/dev/null && exit 0' \
        'printf "%s\\n" '"'"'{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny"}}'"'"'' \
        > "$d/hooks/five-whys-gate.sh"
    echo "CLAUDSOUL_REPO=$d"; }

# D505 — находка, сказанная промежуточной речью в форме расшифровки Opus 5.5 (пересказ в записи
# `thinking`, без `text`), становится поводом гейта разбора. Дерево, где гейт замечает находку в
# любой записи хода: отказ на находке и записью `text` (контроль), и пересказом — проба даёт 0.
green_D505() { local d; d=$(mkfix D505); mkdir -p "$d/hooks"
    printf '%s\n' '#!/usr/bin/env bash' 'p=$(jq -r ".transcript_path // \"\"")' \
        'grep -q "Оказалось" "$p" 2>/dev/null || exit 0' \
        'printf "%s\n" '"'"'{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny"}}'"'"'' \
        > "$d/hooks/five-whys-gate.sh"
    echo "CLAUDSOUL_REPO=$d"; }

# D487 —цена пустого события диспетчера не растёт с историей, игнорируемый каталог не
# подаётся. Как у D483, фикстура — прогон свидетеля на копии диспетчера: предмет поведенческий,
# и подменить его заглушкой значило бы доказать заглушку. До починки нога красна вместе с пунктом.
# Имя диспетчера собрано из частей по той же причине, что в самом свидетеле отбора: стражей
# в фикстуре нет, до исключения `*/tmp/*` подача не доходит, носитель рода M был бы ложным.
green_D487() { local d _disp="bash-write-""dispatch.sh"; d=$(mkfix D487); mkdir -p "$d/hooks/tests"
    cp "$REPO/hooks/$_disp" "$REPO/hooks/paths-lib.sh" "$d/hooks/" 2>/dev/null || true
    cp "$REPO/hooks/tests/test_bash_write_dispatch_selection.sh" "$d/hooks/tests/" 2>/dev/null || true
    echo "CLAUDSOUL_REPO=$d"; }

# D483 — цель правки узнаётся и в чужом стеке. Фикстура зелёной стороны здесь НЕ дерево, а
# прогон свидетеля детектора: замер отверг вариант «без перечня» (структурный признак добавляет
# 1397 целей, почти всё мусор), поэтому зелёная сторона — это детектор, читающий владельца
# перечня. Прежняя фикстура строила детектор БЕЗ перечня и зеленела на опровергнутой редакции.
green_D483() { local d; d=$(mkfix D483); mkdir -p "$d/hooks/tests"
    cp "$REPO/hooks/portable-lib.sh" "$d/hooks/" 2>/dev/null || true
    cp "$REPO/hooks/rework-detector.sh" "$d/hooks/" 2>/dev/null || true
    cp "$REPO/hooks/tests/test_rework_detector.sh" "$d/hooks/tests/" 2>/dev/null || true
    echo "CLAUDSOUL_REPO=$d"; }

# D482 — повтор в одиночку даётся не только убитому тесту. Дерево, где раннер называет
# упавшего под нагрузкой своей строкой и не кладёт его в FAILED: команда пункта даёт 0.
green_D482() { local d; d=$(mkfix D482); mkdir -p "$d/hooks/tests"
    cat > "$d/hooks/tests/run_all.sh" <<'RA482'
#!/usr/bin/env bash
echo "УПАЛИ ТОЛЬКО ПОД НАГРУЗКОЙ (в одиночку зелёные):"
echo "  test_flaky.sh: код 141 за 1 с при соседях 1, в одиночку зелёный за 1 с"
exit 0
RA482
    echo "CLAUDSOUL_REPO=$d"; }

# D481 — стоячий повод входит в ключ памяти зачтённой цепочки. Дерево, где fwg_chain_tokens
# не отбрасывает стоячие роды: команда пункта находит self_repeat в ключе и даёт 0.
green_D481() { local d; d=$(mkfix D481); mkdir -p "$d/hooks"
    cat > "$d/hooks/five-whys-gate.sh" <<'FWG481'
fwg_grants_deny() {
    case " $FWG_STANDING " in
        *" ${1:-} "*) return 1 ;;
    esac
    return 0
}
fwg_chain_tokens() {
    printf '%s' "${1:-}" | tr '|' '\n' | while IFS= read -r _tok; do
        [ -n "$_tok" ] || continue
        case "$_tok" in turn:*) continue ;; esac
        printf '%s\n' "$_tok"
    done | sort -u
}
FWG481
    echo "CLAUDSOUL_REPO=$d"; }

# D480 — роль «механизм назван» решается устройством пути, а не перечнем каталогов и
# расширений. Дерево, где RC_OUT_MECH_RE структурный: путь чужого стека узнаётся, команда даёт 0.
green_D480() { local d; d=$(mkfix D480); mkdir -p "$d/hooks"
    printf '#!/usr/bin/env bash\nRC_OUT_MECH_RE=%s\n' \
        "'(^|[^A-Za-z0-9_.-])[A-Za-z0-9_.-]+/[^ \"]*\\.[A-Za-z][A-Za-z0-9]{0,7}'" \
        > "$d/hooks/root-cause-lib.sh"
    echo "CLAUDSOUL_REPO=$d"; }

# D479 — перечень классов прибора у одного владельца. Дерево, где имя класса стоит ровно в
# одном носителе: под фикстурой мест не больше одного, и команда пункта даёт 0.
green_D479() { local d; d=$(mkfix D479); mkdir -p "$d/scripts" "$d/hooks/tests"
    printf '#!/usr/bin/env bash\n# классы перечислены здесь: tree realtree unresolved\n' > "$d/scripts/behavior-condition-probe.sh"
    printf '#!/usr/bin/env bash\n# нога берёт перечень у владельца, своей копии не держит\n' > "$d/hooks/tests/test_behavior_condition_probe.sh"
    echo "CLAUDSOUL_REPO=$d"; }

# D477 — счётчик с запасным нулём. Дерево, где ни один счётчик не несёт формы
# `grep -c … || echo`: показание пункта считает НОСИТЕЛЕЙ, и под фикстурой их ноль.
green_D477() { local d; d=$(mkfix D477); mkdir -p "$d/hooks" "$d/scripts"
    printf '#!/usr/bin/env bash\n# считаем без путаницы каналов\nn=$(wc -l < "$1")\necho "$n"\n' > "$d/hooks/counter.sh"
    printf '#!/usr/bin/env bash\nn=$(grep -cv "^#" "$1" 2>/dev/null || true)\ncase "$n" in ""|*[!0-9]*) n=0 ;; esac\necho "$n"\n' > "$d/scripts/safe-count.sh"
    echo "CLAUDSOUL_REPO=$d"; }

green_D476() { local d; d=$(mkfix D476); mkdir -p "$d/hooks/tests/fixtures"
    # timeout-lib.sh — сосед библиотеки выхолащивания, которую зовёт проба probe_D464:
    # без него она отвечает BROKEN, и на машине автора это маскировал фоллбек на ~/.claude
    # (найдено замером suite-linux в чистом контейнере, 23 сентября 2026).
    for f in backlog-lib.sh command-scope-lib.sh backlog-vanish-check.sh timeout-lib.sh subject-probe-lib.sh; do
        cp "$REPO/hooks/$f" "$d/hooks/$f" 2>/dev/null || true
    done
    cp "$REPO/hooks/tests/fixtures/probe_D464.sh" "$d/hooks/tests/fixtures/"
    # Патчер, который ДЕЙСТВИТЕЛЬНО меняет файл на месте: его падение видно сравнением.
    printf '#!/usr/bin/env python3\nimport io,sys\np=sys.argv[2]\nio.open(p,"a").write("# patched\\n")\n' \
        > "$d/hooks/tests/fixtures/green_D900.py"
    # Свидетель из трёх частей, которые проба вырезает: mkfix, apply_patch и одна живая нога.
    {
        printf '#!/usr/bin/env bash\n'
        printf 'mkfix() { local id="$1"; local x="$TMP/$id"; mkdir -p "$x"; printf %%s "$x"; }\n'
        printf 'apply_patch() { local py="$1"; shift; python3 "$py" "$@" || return 1; }\n'
        # Путь патчимого файла — тот, который проба и сверяет: она знает его именем, и это
        # её названный предел (пункт D476). Фикстура следует предмету пробы, а не спорит с ним.
        printf 'green_D900() { local d; d=$(mkfix D900); mkdir -p "$d/hooks"; '
        printf 'cp "$REPO/hooks/backlog-vanish-check.sh" "$d/hooks/backlog-vanish-check.sh"; '
        printf 'apply_patch "$REPO/hooks/tests/fixtures/green_D900.py" "$d/hooks/backlog-vanish-check.sh" "$d/hooks/backlog-vanish-check.sh" || return 1; '
        printf 'echo "CLAUDSOUL_REPO=$d"; }\n'
        printf 'green_D901() { :; }\n'
    } > "$d/hooks/tests/test_backlog_green_side.sh"
    echo "CLAUDSOUL_REPO=$d"; }
green_D474() { local d; d=$(mkfix D474); mkdir -p "$d/hooks/tests" "$d/scripts" "$d/.claude-docs"
    printf '#!/usr/bin/env bash\necho MARKER\nexit 0\n' > "$d/hooks/subject.sh"
    { printf '#!/usr/bin/env bash\n'
      printf '# СУДИТ: hooks/subject.sh\n'
      printf 'REPO="$(cd "$(dirname "$0")/../.." && pwd)"\n'
      printf 'out=$(bash "$REPO/hooks/subject.sh" 2>&1)\n'
      printf 'case "$out" in *MARKER*) exit 0 ;; *) exit 1 ;; esac\n'
    } > "$d/hooks/tests/test_adv_declared.sh"
    cp "$REPO/scripts/behavior-condition-probe.sh" "$d/scripts/"
    # Библиотеки прибора — в фикстуру тоже: без них он отвечает BROKEN. На машине автора это
    # маскировал фоллбек на установленную копию в ~/.claude, и зелень держалась на ней;
    # замер suite-linux в чистом контейнере показал настоящее (23 сентября 2026).
    mkdir -p "$d/hooks"
    for _l in subject-probe-lib.sh frame-control-lib.sh timeout-lib.sh portable-lib.sh; do
        [ -f "$REPO/hooks/$_l" ] && cp "$REPO/hooks/$_l" "$d/hooks/$_l"
    done
    printf '# path\tsha\tdeps\tdocs\ttests\tnames\n' > "$d/.claude-docs/dep-index.tsv"
    # «Проверка» D474 вынесена в пробу дословно (D1295, 15 ноября 2026) — проба едет в фикстуру как есть.
    mkdir -p "$d/hooks/tests/fixtures" && cp "$REPO/hooks/tests/fixtures/probe_D474.sh" "$d/hooks/tests/fixtures/"
    chmod +x "$d/hooks/subject.sh" "$d/hooks/tests/test_adv_declared.sh" "$d/scripts/behavior-condition-probe.sh"
    ( cd "$d" && git init -q . && git add -A \
        && git -c user.email=t@t -c user.name=t commit -qm init ) >/dev/null 2>&1 || { echo "подготовка мира не удалась: hooks/tests/test_backlog_green_side.sh:$LINENO" >&2; exit 1; }
    # ВТОРАЯ ПОЛОВИНА «Проверки» (22 сентября 2026) — полнота суда: вердикт вынесен ВСЕМ,
    # чей предмет разрешим. Фикстура готовит след прогона со своим деревом: judged равен
    # resolved, то есть непросуженных нет. Без этой строки зелёная сторона судила бы только
    # перечень неразрешённых, а вторую половину не проверял бы никто.
    # СЛЕД СТАВИТ ПРОГОН, А НЕ РУКА (22 сентября 2026, вторая половина «Проверки»).
    # Первая редакция писала строку журнала сама — то есть предъявляла зелень ПОДДЕЛАННОГО
    # следа: она держалась бы и на приборе, который ничего не считает. Образец взят у
    # соседней фикстуры green_D342, где прибор прогоняется в своём дереве со своим STATE_DIR.
    mkdir -p "$d/.state"
    ( cd "$d" && STATE_DIR="$d/.state" CLAUDSOUL_REPO="$d" CLAUDSOUL_ROOT="$d" \
        bash scripts/behavior-condition-probe.sh ) > "$d/.probe.log" 2>&1
    printf 'код прибора: %s\n' "$?" >> "$d/.probe.log"
    echo "CLAUDSOUL_REPO=$d"; echo "STATE_DIR=$d/.state"; }
# Зелёная сторона D475 — ДЕРЕВО, где генератор производных чисел читает РЕЕСТР мест, а не
# свой литерал: связь объявлена, и «Проверка» её видит. Фикстура судит объявление, потому
# что зелёный сверщик бывает и от ручной правки — он не отличает, чьей рукой число приведено.
green_D475() { local d; d=$(mkfix D475); mkdir -p "$d/scripts"
    printf '#!/usr/bin/env bash\n# патчер производных чисел\necho "patched: canonical lines"\necho "прочие числа держит реестр doc-claims.tsv — правь docs-refresh-claims.sh run"\n' > "$d/scripts/count-stats.sh"
    printf 'README.md\tхуков всего\t86\n' > "$d/scripts/doc-claims.tsv"
    chmod +x "$d/scripts/count-stats.sh"
    echo "CLAUDSOUL_REPO=$d"; }
green_D349() { local d; d=$(mkfix D349); mkdir -p "$d/scripts" "$d/knowledge"; printf 'stop-context-restart\t14\tx\n' > "$d/scripts/measurements.tsv"; echo "stop_hook_active" > "$d/knowledge/k.md"; echo "CLAUDSOUL_REPO=$d"; }
# Знаменатель «Проверки» D358 — записи СО СЛЕДОМ разбора, и их не меньше порога
# `OUTCOME_SHARE_MIN_N` (20): ниже порога владелец формулы честно отвечает «НЕ ИЗМЕРЕНО»
# кодом 2, и зелёная сторона стала бы неотличима от красной. 10 из 20 со следом = 50%.
green_D358() { local d i; d=$(mkfix D358); mkdir -p "$d/.claude/hooks/state"
    # ЖУРНАЛОВ ДВА, и это предмет, а не декорация (13 сентября 2026): условие закрытия
    # считается с `--exclude-newest`, то есть БЕЗ журнала закрывающей сессии. Зелёная
    # сторона обязана зеленеть на СТАРОМ журнале — иначе она доказывала бы ровно то, что
    # решением владельца запрещено: закрытие по данным самого закрывающего.
    for i in $(seq 1 20); do
        if [ "$i" -le 10 ]; then
            printf '{"signal":"rework","outcome":"chain-spoken","trace":{"why":3,"addr":1,"frac":1,"roots":1,"heads":2,"arrows":3,"inputs":1}}\n'
        else
            printf '{"signal":"rework","outcome":"none","trace":{"why":0,"addr":0,"frac":0,"roots":0,"heads":0,"arrows":0,"inputs":0}}\n'
        fi
    done > "$d/.claude/hooks/state/outcome-old.jsonl"
    # Свежий журнал без единой цепочки: при верном устройстве он в условие закрытия НЕ входит.
    for i in $(seq 1 20); do
        printf '{"signal":"rework","outcome":"none","trace":{"why":0,"addr":0,"frac":0,"roots":0,"heads":0,"arrows":0,"inputs":0}}\n'
    done > "$d/.claude/hooks/state/outcome-new.jsonl"
    touch -t 200001010000 "$d/.claude/hooks/state/outcome-old.jsonl"
    echo "HOME=$d"; }
green_D406() { local d; d=$(mkfix D406); mkdir -p "$d/.claude-docs" "$d/scripts" "$d/hooks"
    # Дерево БЕЗ взаимных ссылок: учёт пуст, значит рёбер исполнения нет и колец нет.
    # Предмет зелёной стороны — что прибор УМЕЕТ сказать «спаек: 0», а не только «есть».
    printf '# path\tsha\tdeps\tdocs\tests\tnames\n' > "$d/.claude-docs/dep-index.tsv"
    # `|| true` здесь стоял до 19 сентября 2026 и глушил ОТКАЗ подготовки: несобранная
    # фикстура была неотличима от собранной. Замер того дня НЕ показал здесь молчания и не
    # мог: ноги D406 и D411 принадлежат ЗАКРЫТЫМ пунктам, свидетель зовёт только ноги
    # открытых, и эти строки не исполняются вовсе (прибор с маркером достижимости отвечает
    # «НЕ ИСПОЛНЕНО»). Правка сделана по УСТРОЙСТВУ, а не по замеру: когда пункт снова
    # откроют, отказ подготовки обязан быть слышен. Первая редакция этого комментария
    # ссылалась на «МОЛЧИТ» — то был артефакт двухсостоянийного прибора, снят.
    cp "$REPO/scripts/project-graph.py" "$d/scripts/" || return 1
    ( cd "$d" && git init -q . >/dev/null 2>&1 ) || return 1
    echo "CLAUDSOUL_REPO=$d"; }
green_D407() { local d; d=$(mkfix D407); mkdir -p "$d/hooks"
    # Зелёная сторона: хук объявляет предметом ПРАВКУ и зарегистрирован на событии,
    # которое Bash ВИДИТ, — значит слепых носителей нет и прибор даёт 0.
    printf '#!/usr/bin/env bash\n# проба — при правке файла говорит о связях\n# en: probe\n#\n' > "$d/hooks/probe.sh"
    printf '%s\n' '"PreToolUse": {' '  "matcher": "Bash|Edit|Write",' '  "command": "bash ~/.claude/hooks/probe.sh"' '}' > "$d/install.sh"
    mkdir -p "$d/scripts"; cp "$REPO/scripts/guard-event-coverage.sh" "$d/scripts/"
    echo "CLAUDSOUL_REPO=$d"; }
green_D414() { local d; d=$(mkfix D414); mkdir -p "$d/scripts"
    # Зелёная сторона: прибор адресов, чей отчёт РАЗЛИЧАЕТ «проверено и цело» от «не судилось» —
    # неразличимые адреса названы поимённо, а не только счётчиком. Настоящий прибор печатает
    # «ожидание неразличимо: 8» без единого имени, и «Проверка» пункта на нём красна.
    printf '%s\n' '#!/usr/bin/env python3' \
      'print("адресов сверено по содержимому: 12; уплывших: 0; ожидание неразличимо: 2 — docs/a.md:7, docs/b.md:3")' \
      > "$d/scripts/docs-address-drift.py"
    echo "CLAUDSOUL_REPO=$d"; }
green_D408() { local d; d=$(mkfix D408); mkdir -p "$d/scripts" "$d/corpus/proj"
    # Зелёная сторона: корпус, где КАЖДОЕ опознание класса идёт с реестром носителей.
    # Живые расшифровки не читаются — прибор берёт корпус из CORPUS_DIR.
    # Опознаний 20 — ровно окно прибора (с 4 октября 2026 оно считается опознаниями): на
    # меньшем числе прибор отвечает кодом 2 «не измерено», и зелёной стороны нет.
    cp "$REPO/scripts/signal-precision-corpus.py" "$d/scripts/" 2>/dev/null || true
    # Граница хода — `is_turn_user` владельца (D1153): библиотека едет вместе с прибором.
    mkdir -p "$d/hooks/lib"; cp "$REPO/hooks/lib/transcript_window.py" "$d/hooks/lib/" 2>/dev/null || true
    local i; for i in $(seq 1 20); do printf '%s\n' \
      '{"type":"assistant","message":{"role":"assistant","content":[{"type":"text","text":"Тот же класс, что чинили вчера: носителей 3 из 7."}]}}' \
      '{"type":"user","isMeta":false,"origin":{"kind":"human"},"message":{"role":"user","content":"дальше"}}'
    done > "$d/corpus/proj/probe.jsonl"
    echo "CLAUDSOUL_REPO=$d"; echo "CORPUS_DIR=$d/corpus"; }
green_D409() { local d; d=$(mkfix D409); mkdir -p "$d/scripts"
    printf 'id\tпериод\tкоманда\tчто мерит\n' > "$d/scripts/measurements.tsv"
    printf 'docs-address-anchor\t30c\ttrue\tадресов «файл:строка» без якоря содержимого\n' >> "$d/scripts/measurements.tsv"
    echo "CLAUDSOUL_REPO=$d"; }
green_D410() { local d; d=$(mkfix D410); mkdir -p "$d/hooks"
    # Зелёная сторона: страж берёт меру у владельца факта, а не считает свою.
    printf '#!/usr/bin/env bash\n# проба\nMAX="${COSTLY_CPU_MAX:-20}"\n' > "$d/hooks/test-cost-notice.sh"
    echo "CLAUDSOUL_REPO=$d"; }
green_D411() { local d; d=$(mkfix D411); mkdir -p "$d/.claude-docs" "$d/scripts" "$d/hooks"
    # Дерево без взаимных ссылок: спайки данных нет, прибор печатает «спаек: 0».
    printf '# path\tsha\tdeps\tdocs\ttests\tnames\n' > "$d/.claude-docs/dep-index.tsv"
    # `|| true` здесь стоял до 19 сентября 2026 и глушил ОТКАЗ подготовки: несобранная
    # фикстура была неотличима от собранной. Замер того дня НЕ показал здесь молчания и не
    # мог: ноги D406 и D411 принадлежат ЗАКРЫТЫМ пунктам, свидетель зовёт только ноги
    # открытых, и эти строки не исполняются вовсе (прибор с маркером достижимости отвечает
    # «НЕ ИСПОЛНЕНО»). Правка сделана по УСТРОЙСТВУ, а не по замеру: когда пункт снова
    # откроют, отказ подготовки обязан быть слышен. Первая редакция этого комментария
    # ссылалась на «МОЛЧИТ» — то был артефакт двухсостоянийного прибора, снят.
    cp "$REPO/scripts/project-graph.py" "$d/scripts/" || return 1
    ( cd "$d" && git init -q . >/dev/null 2>&1 ) || return 1
    echo "CLAUDSOUL_REPO=$d"; }
# Зелёная сторона D415 — знание, у которого признак ловит путь ВНУТРИ тела heredoc, а не
# только цель перенаправления. Подменяется ДОМАШНИЙ каталог: команда пункта читает знание
# по $HOME. Описание отменённой редакции («столько же форм у близнеца») снято 15 сентября
# 2026: сам пункт назвал ту посылку неверной, а комментарий продолжал её утверждать. Файл пишется построчно printf: вложенный питон здесь однажды
# умер на тройных кавычках, а литерал дефекта в фикстуре отбивает живой блокер.
green_D415() { local d f; d=$(mkfix D415); mkdir -p "$d/.claude/global-lessons"
    f="$d/.claude/global-lessons/pattern-shell-portability.md"
    {
        printf -- '---\nname: proba\nblocker: true\ndetection_signals: |\n'
        printf '  [\n'
        printf '    {\n'
        printf '      "name": "vidit_put_v_tele",\n'
        printf '      "all_of": [\n'
        printf '        { "tool_matches": ["Bash"] },\n'
        printf '        { "heredoc_body_regex": "(hooks|scripts)/[^ ]*[.](sh|bash)" },\n'
        printf '        { "heredoc_body_regex": "grep -oE" }\n'
        printf '      ],\n'
        printf '      "remedy": "proba"\n'
        printf '    }\n'
        printf '  ]\n'
        printf -- '---\n\nпроба\n'
    } > "$f"
    echo "TWIN_KNOWLEDGE=$f"; }
green_D405() { local d; d=$(mkfix D405); mkdir -p "$d/hooks"; cp "$REPO/hooks/backlog-lib.sh" "$d/hooks/"; printf -- '- ☐ **D999** проба\n  **Проверка.** `false` → 0\n  **Зелёная сторона.** `true`\n' > "$d/BACKLOG.md"; echo "CLAUDSOUL_REPO=$d"; }

# D416–D419 (2026-09-16, дефекты системы, найденные в ProjectA_NEW): у трёх «Проверка» судит по форме — зелёная сторона лишь показывает, что команда может позеленеть.
green_D416() { local d; d=$(mkfix D416); mkdir -p "$d/scripts"; printf '#!/usr/bin/env bash\n. hooks/backlog-lib.sh; backlog_ids BACKLOG.md\n' > "$d/scripts/project-conformance.sh"; echo "CLAUDSOUL_REPO=$d"; }
green_D417() { local d; d=$(mkfix D417); mkdir -p "$d/scripts"; printf 'import sys\nsys.exit(0)\n' > "$d/scripts/root-map.py"; echo "CLAUDSOUL_REPO=$d"; }
green_D418() { local d; d=$(mkfix D418); mkdir -p "$d/hooks"; printf '# повтор прогона одной спеки: playwright test <file>\n' > "$d/hooks/rework-detector.sh"; echo "CLAUDSOUL_REPO=$d"; }
green_D419() { local d; d=$(mkfix D419); mkdir -p "$d/hooks"; printf 'CLAUDSOUL_BACKLOG="$CLAUDSOUL_ROOT/BACKLOG.md"\n' > "$d/hooks/declared-problem-recorded.sh"; echo "CLAUDSOUL_REPO=$d"; }
# D438–D448 (17 сентября 2026, братья корней волны D427–D437): тела патчей — в hooks/tests/fixtures/green_D4xx.py,
# пробы — там же, probe_D4xx.sh; каждая копия сверена тремя кодами (живое 1, патч 0, без патча 1).
# Зелёная сторона D438 снята 19 сентября 2026 вместе с закрытием: её место заняли показание
# и проба, красная на дереве до починки и отбраковывающая заглушку «предупреждать всегда».
# Зелёная сторона D439 снята 19 сентября 2026 вместе с закрытием: её место заняли показание
# и проба с положительным контролем перед судом.
# Зелёная сторона D441 снята 19 сентября 2026 вместе с закрытием: её место заняли показание
# и проба с положительным контролем рамки рядом с судом.
# Зелёная сторона D442 снята 19 сентября 2026 вместе с закрытием пункта: её место заняли
# показание и проба probe_D442.sh, красная (rc=1) на дереве до починки — измерено на копии HEAD.
# Зелёная сторона D467 снята 19 сентября 2026 вместе с закрытием: её место заняли показание
# и проба, красная И на дереве до починки, И на подделке, собранной скептиком.
green_D473() { local d; d=$(mkfix D473); mkdir -p "$d/hooks" "$d/sandbox" "$d/.claude/hooks/state"
  # Фикстура зеленеет ОТ ПОЧИНКИ, а не оттого, что каталог пуст (D405). Мир воспроизводится
  # целиком: копия хуков, подменённый HOME, прогон носителя с фикстурным идентификатором
  # сессии `probe-*` — тем самым, по которому «Проверка» ищет утечку.
  #
  # БЕЗ починки библиотека берёт свой дефолт `$HOME/.claude/hooks/state` и кладёт файл ТУДА,
  # хотя STATE_DIR указан в песочницу: «Проверка» находит его и краснеет — ровно нынешний мир.
  # С починкой каталог наследуется от STATE_DIR, файл ложится в песочницу, и находить нечего.
  cp -a "$REPO/hooks/." "$d/hooks/" 2>/dev/null || :
  python3 - "$d/hooks/intrusiveness-state-lib.sh" <<'PYP'
import io, sys
p = sys.argv[1]; s = io.open(p, encoding='utf-8').read()
old = 'ITR_STATE_DIR="${ITR_STATE_DIR:-$HOME/.claude/hooks/state}"'
new = 'ITR_STATE_DIR="${ITR_STATE_DIR:-${STATE_DIR:-$HOME/.claude/hooks/state}}"  # починка D473'
assert s.count(old) == 1, f"якорь не найден ровно один раз: {s.count(old)}"
io.open(p, 'w', encoding='utf-8').write(s.replace(old, new, 1))
PYP
  ( export HOME="$d"
    printf '{"session_id":"probe-D473"}' \
      | STATE_DIR="$d/sandbox" bash "$d/hooks/intrusiveness-tracker.sh" ) >/dev/null 2>&1
  echo "HOME=$d"; }
green_D470() { local d; d=$(mkfix D470); mkdir -p "$d/scripts"; apply_patch "$REPO/hooks/tests/fixtures/green_D470.py" "/dev/null" "$d/scripts/class-repeat-check.sh" || return 1; echo "CLAUDSOUL_REPO=$d"; }
# Зелёная сторона D469 снята 19 сентября 2026 вместе с закрытием: её место заняли показание
# и проба, красная на дереве до починки, с положительным контролем рамки перед судом.
# Зелёная сторона D468 снята 19 сентября 2026 вместе с закрытием: её место заняли показание
# и проба, красная на трёх разных негодных состояниях — дерево до починки, подделка по имени
# фикстуры, выпотрошенный прибор.
# Зелёная сторона D443 снята 19 сентября 2026 вместе с закрытием: её место заняли показание
# и проба probe_D443.sh, судящая ОТЧЁТ сборщика в трёх состояниях, а не код возврата функции.
# Зелёная сторона D444 снята 19 сентября 2026 вместе с закрытием: её место заняли показание
# и проба probe_D444.sh, судящая все восемь точек разом при четырёх собственных контролях.
green_D446(){ local d; d=$(mkfix D446); cp -a "$REPO/hooks" "$REPO/scripts" "$d/"; cp "$REPO/ROOTS.md" "$d/ROOTS.md"; ( cd "$d" && git init -q . && git -c user.email=p@p -c user.name=p add -A && git -c user.email=p@p -c user.name=p -c commit.gpgsign=false commit -qm i ) >/dev/null 2>&1 || { echo "подготовка мира не удалась: hooks/tests/test_backlog_green_side.sh:$LINENO" >&2; exit 1; }; PATCHED="$d/ROOTS.patched.md"; CLAUDSOUL_REPO="$d" apply_patch "$REPO/hooks/tests/fixtures/green_D446.py" "$d/ROOTS.md" "$PATCHED" || return 1; cp "$PATCHED" "$d/ROOTS.md"; echo "CLAUDSOUL_REPO=$d"; }
# Зелёной стороны D466 нет и не было: пункт открыт и закрыт одним ходом 19 сентября 2026,
# её место заняли показание и проба, чья различающая способность показана прогоном — до
# починки `scripts/probes/R6.sh` называл носителя, после неё отвечает 0.
# Зелёная сторона D465 снята 19 сентября 2026 вместе с закрытием пункта: её место заняли
# показание (`setup-call-guard.py --count` → 0) и проба `hooks/tests/fixtures/probe_D465.sh`,
# у которой два контроля различающей способности реестра стоят ПЕРЕД судом.
# Зелёная сторона D464 снята 19 сентября 2026 вместе с закрытием пункта: её место заняли
# показание и проба `hooks/tests/fixtures/probe_D464.sh`, которая краснеет (rc=1) на свидетеле
# из HEAD до починки — проверено прогоном на копии.
# Зелёные стороны D445, D447, D448 сняты 19 сентября 2026 вместе с закрытием пунктов: у закрытого
# её место занимают показание и проба. Пробы probe_D445/D447/D448.sh остались «Проверкой» и судят
# ПОВЕДЕНИЕ: у D445 закрытие собирается из строк самого шаблона и подаётся архиватору, у D447
# судятся имя пропущенного файла и код 3, у D448 добавлены контроли «упала (rc=3)» и «rc=0 при
# непустом stderr» — каждая из трёх редакций заведена после того, как скептик позеленил прежнюю
# заведомо негодной подделкой.
# Зелёная сторона D449 снята 18 сентября 2026 вместе с закрытием пункта: её место заняли показание и проба
# `hooks/tests/fixtures/probe_D449.sh`, которая краснеет (rc=1) на прежнем гейте.
# D457 — очередь носителей корня R1 (владение состоянием по актору). Фикстура делает НАСТОЯЩЕЕ
# действие починки в миниатюре: дописывает вызов владельца суффикса каждому носителю очереди,
# после чего счётчик «Проверки» доходит до нуля. Список носителей повторяет тот, что в пункте:
# у команды пункта он встроен, и разойтись они могут только правкой обоих — это названный предел
# фикстуры, а не её устройство.
# Зелёная сторона D457 снята вместе с закрытием пункта (18 сентября 2026): её место заняла
# проба `hooks/tests/fixtures/probe_D457.sh`, судящая ПОВЕДЕНИЕ — она краснеет на дереве до
# починок и зелена на нынешнем. Прежняя фикстура дописывала носителям комментарий с вызовом
# `resolve_actor_suffix`, то есть зеленела от НАПИСАННОГО СЛОВА, а не от работы механизма.
green_D463() { local d; d=$(mkfix D463); mkdir -p "$d/hooks/tests/fixtures"
  cp -a "$REPO/hooks/." "$d/hooks/" 2>/dev/null || :
  python3 - "$d/hooks/user-correction-guard.sh" <<'PYP'
import io,sys
p=sys.argv[1]; s=io.open(p,encoding='utf-8').read()
old='MSG_HASH=$(hash_value "$LAST_USER_TEXT")'
new=old+'\nMSG_HASH="${MSG_HASH}$(printf %s "$INPUT" | jq -r \'.agent_id // ""\')"  # починка D463'
assert s.count(old)==1
io.open(p,'w',encoding='utf-8').write(s.replace(old,new,1))
PYP
  echo "CLAUDSOUL_REPO=$d"; }
green_D460() { local d t; d=$(mkfix D460); mkdir -p "$d/hooks/tests" "$d/scripts" "$d/state"
  # Фикстура воспроизводит мир ЦЕЛИКОМ, а не наполовину. Первая редакция давала только
  # реестр оправданной цены — и «Проверка» краснела под ней тоже, потому что прибор читает
  # ПЕРВЫМ замер поодиночке (`state/suite-cost.tsv`), а без него выходит кодом 2 «мерить
  # нечем», который с 18 сентября 2026 считается красным намеренно. Поймала это нога D460
  # на прогоне CI 35350506567, а не рука.
  cp -a "$REPO/scripts/costly-tests.sh" "$d/scripts/" 2>/dev/null || :
  cp -a "$REPO/hooks/tests/costly-justified.tsv" "$d/hooks/tests/" 2>/dev/null || :
  printf '# замер поодиночке начат 2026-09-18 00:00:00, по журналу «# прогон начат 2026-09-18 00:00:00, тестов 531, полнота полный», кандидатов 5, порог 20\n' \
      > "$d/state/suite-cost.tsv"
  for t in test_auto_scanner test_completion_gate_open_items test_bash_write_dispatch \
           test_predicate_signal test_guards_provable; do
    printf '0\t40\t40\t%s.sh\n' "$t" >> "$d/state/suite-cost.tsv"
    printf '%s.sh\t40 (2026-09-18)\tпредмет — дерево целиком (фикстура D460)\n' "$t" \
        >> "$d/hooks/tests/costly-justified.tsv"
  done
  echo "CLAUDSOUL_REPO=$d"
  echo "STATE_DIR=$d/state"; }
# Зелёная сторона D1306 — ДЕРЕВО, где свидетель «сообщение подготовки называет свою строку само» есть и зелен.
# Нога стоит НИЖЕ сообщений с адресом «файл:строка» этого файла намеренно: вставка выше сдвигала их (D1306).
green_D1306() { local d; d=$(mkfix D1306); mkdir -p "$d/hooks/tests"
    printf '%s\n' '#!/usr/bin/env bash' 'echo "адрес подготовки вычисляется, а не вписан"' 'exit 0' > "$d/hooks/tests/test_setup_messages_locate_themselves.sh"
    echo "CLAUDSOUL_REPO=$d"; }
# Зелёная сторона D1307 — ДЕРЕВО, где свидетель есть и зелен (нога ниже адресов файла, D1306).
green_D1307() { local d; d=$(mkfix D1307); mkdir -p "$d/hooks/tests"
    printf '%s\n' '#!/usr/bin/env bash' 'echo "проект работы — по цели правки"' 'exit 0' > "$d/hooks/tests/test_project_by_edit_target.sh"
    echo "CLAUDSOUL_REPO=$d"; }
# Зелёная сторона D1308 — ДЕРЕВО, где свидетель есть и зелен (нога ниже адресов файла, D1306).
green_D1308() { local d; d=$(mkfix D1308); mkdir -p "$d/hooks/tests"
    printf '%s\n' '#!/usr/bin/env bash' 'echo "шапка одна при гонке"' 'exit 0' > "$d/hooks/tests/test_contract_header_once_under_race.sh"
    echo "CLAUDSOUL_REPO=$d"; }
# Зелёная сторона D1309 — ДЕРЕВО, где пробы D1231, D514 и свод архивной «Проверки» D291 зелены (нога ниже адресов, D1306).
green_D1309() { local d p; d=$(mkfix D1309); mkdir -p "$d/hooks/tests/fixtures"
    for p in probe_D1196 probe_D514 probe_D1231; do printf '%s\n' '#!/usr/bin/env bash' 'exit 0' > "$d/hooks/tests/fixtures/$p.sh"; done
    echo "CLAUDSOUL_REPO=$d"; }
# Зелёная сторона D1311 снята 17 ноября 2026 вместе с закрытием пункта ⊘ (предел по частоте при взятии): свидетеля
# `test_skeptic_line_names_commits.sh` нет и не будет — признак не различал (157 из 157 строк скептика называют коммит).
# Зелёная сторона D1310 — ДЕРЕВО, где свидетель есть и зелен (нога ниже адресов файла, D1306).
green_D1310() { local d; d=$(mkfix D1310); mkdir -p "$d/hooks/tests"
    printf '%s\n' '#!/usr/bin/env bash' 'echo "правка свидетеля выбирает рамки"' 'exit 0' > "$d/hooks/tests/test_run_all_changed_selects_frames.sh"
    echo "CLAUDSOUL_REPO=$d"; }
# Зелёная сторона D1312 — ДЕРЕВО, где свидетель есть и зелен (нога ниже адресов файла, D1306).
green_D1312() { local d; d=$(mkfix D1312); mkdir -p "$d/hooks/tests"
    printf '%s\n' '#!/usr/bin/env bash' 'echo "сверка архива выбирает пробу по её коду"' 'exit 0' > "$d/hooks/tests/test_archive_select_probe_code.sh"
    echo "CLAUDSOUL_REPO=$d"; }
# Зелёная сторона D1314 (откат D1225, третий) — ДЕРЕВО, где проба D1225 зелёна: каталог состояния после уборки под порогами.
green_D1314() { local d; d=$(mkfix D1314); mkdir -p "$d/hooks/tests/fixtures"
    printf '%s\n' '#!/usr/bin/env bash' 'echo "после уборки под обоими порогами"' 'exit 0' > "$d/hooks/tests/fixtures/probe_D1225.sh"
    echo "CLAUDSOUL_REPO=$d"; }
# Зелёная сторона D1313 — ДЕРЕВО, где свидетель есть и зелен (нога ниже адресов файла, D1306).
green_D1313() { local d; d=$(mkfix D1313); mkdir -p "$d/hooks/tests"
    printf '%s\n' '#!/usr/bin/env bash' 'echo "свой фоновый сервер назван на границе хода"' 'exit 0' > "$d/hooks/tests/test_own_background_process_reported.sh"
    echo "CLAUDSOUL_REPO=$d"; }
# Зелёная сторона D1316 снята 18 ноября 2026 вместе с закрытием пункта: её место заняло показание — прогон CI
# 44340483027 по d00e04d2 зелёный.
# Зелёная сторона D1342 снята 21 ноября 2026 вместе с закрытием пункта: её место заняли показание и свидетель
# `test_merge_root_gate.sh` (ноги P1m–P1y).
# Зелёная сторона D1343 — ДЕРЕВО, где проба «секрет в поле new_str получает отказ» отвечает 0.
# Зелёная сторона D1343 снята 21 ноября 2026 вместе с закрытием пункта ⊘ (признак опровергнут: настоящих вызовов Edit
# с полями `old_str`/`new_str` нет, все 79 — служебные копии запроса).
# Зелёная сторона D1352 снята 21 ноября 2026 вместе с закрытием пункта: её место заняли показание и свидетель
# `test_archive_relay.sh` (ноги A1b, A2c, A5b, A7, A7b, A11).
# Зелёная сторона D1351 снята 21 ноября 2026 вместе с закрытием пункта: её место заняли показание и проба
# `probe_D1351.sh` (объявление дня опыта и оба входа счётчика).
# Зелёная сторона D1350 снята 21 ноября 2026 вместе с закрытием пункта: её место заняли показание и свидетель
# `test_measurement_due.sh` (нога T9c).
# Зелёная сторона D1349 снята 21 ноября 2026 вместе с закрытием пункта: её место заняли показание и проба
# `probe_D1349.sh` (сверка дробей R1–R4 прибором карты).
# Зелёная сторона D1347 снята 21 ноября 2026 вместе с закрытием пункта: её место заняли показание и свидетель
# `test_measurement_due.sh` (ноги T13, T13b).
# Зелёная сторона D1348 снята 21 ноября 2026 вместе с закрытием пункта: её место заняли показание и проба
# `probe_D1348.sh` (тест карты с пустой домашней папкой).
# Зелёная сторона D1346 снята 21 ноября 2026 вместе с закрытием пункта: её место заняли показание и свидетель
# `test_transcript_window.sh` (ноги T12a–T12h).
# Зелёная сторона D1344 снята 21 ноября 2026 вместе с закрытием пункта: её место заняли показание и свидетель
# `test_alerts_reach_their_addressee.sh` (ноги T13, T14).
# Зелёная сторона D1345 снята 21 ноября 2026 вместе с закрытием пункта: её место заняли показание и свидетель
# `test_project_graph.sh` (ноги T12g–T12k).
# Зелёные стороны D1326 и D1327 сняты 19 ноября 2026 вместе с закрытием пунктов: их место заняли показание и свидетели
# `test_command_scope.sh`, `test_replace_uniqueness_guard.sh`.
# Зелёная сторона D1328 снята 19 ноября 2026 вместе с закрытием пункта: её место заняли показание и свидетель
# `test_hook_input_lib.sh`.
# Зелёная сторона D1329 снята 19 ноября 2026 вместе с закрытием пункта: её место заняли показание и свидетели
# `test_outcome_observed.sh`, `test_root_cause_lib.sh`.
# Зелёная сторона D1330 снята 21 ноября 2026 вместе с закрытием пункта: её место заняли показание и свидетели
# `test_rework_detector.sh` (ноги D1330а–з) и `test_rework_rerun_streak.sh` (T6, T7).
# Зелёная сторона D1331 снята 20 ноября 2026 вместе с закрытием пункта ⊘ (предел: частота до заведения пункта,
# разбор пачкой) — свидетеля не писали, числа замера стоят в строках таблицы разбора.
# Зелёная сторона D1332 снята 20 ноября 2026 вместе с закрытием пункта ⊘ (предел: частота до заведения пункта,
# разбор пачкой) — свидетеля не писали, числа замера стоят в строках таблицы разбора.
# Зелёная сторона D1333 снята 20 ноября 2026 вместе с закрытием пункта ⊘ (предел: частота до заведения пункта,
# разбор пачкой) — свидетеля не писали, числа замера стоят в строках таблицы разбора.
# Зелёная сторона D1334 снята 20 ноября 2026 вместе с закрытием пункта: её место занял свидетель
# `test_session_collector.sh` (ноги T12c–T12e).
# Зелёная сторона D1335 снята 20 ноября 2026 вместе с закрытием пункта: её место заняли свидетели
# `test_intrusiveness_tracker.sh` (нога T5) и `test_session_collector.sh` (нога T-ITR).
# Зелёная сторона D1336 снята 20 ноября 2026 вместе с закрытием пункта: её место занял свидетель
# `test_docs_refresh_claims.sh` (ноги T9, T10).
# Зелёная сторона D1337 снята 20 ноября 2026 вместе с закрытием пункта ⊘ (предел: частота до заведения пункта,
# разбор пачкой) — свидетеля не писали, числа замера стоят в строках таблицы разбора.
# Зелёная сторона D1338 снята 20 ноября 2026 вместе с закрытием пункта: её место занял свидетель
# `test_archive_select_probe_code.sh` (ноги A8, A9).
# Зелёная сторона D1339 — ДЕРЕВО, где проба «атаки критиков на scripts/dep-index.py зелёны» отвечает 0.
# Зелёная сторона D1339 снята 21 ноября 2026 вместе с закрытием пункта: её место заняли показание и свидетель
# `test_adv2_dep_index_path_mention.sh` (ноги B2, B3a–B3e).
# Зелёная сторона D1340 снята 20 ноября 2026 вместе с закрытием пункта: её место занял свидетель
# `test_project_graph.sh` (ноги T12b–T12f).
# Зелёная сторона D1341 снята 20 ноября 2026 вместе с закрытием пункта: её место заняли показание и свидетель
# `test_named_limits.sh` (ноги T6–T12).
# Зелёные стороны D1319, D1323, D1324, D1325 сняты 18 ноября 2026 вместе с закрытием пунктов: их место заняли показание
# и свидетели `test_rc_snapshot_compressed.sh`, `test_guard_generated_forms.sh`, `test_intrusiveness_lib.sh`, `probe_D1325.sh`.
# Зелёные стороны D1320–D1322 сняты 18 ноября 2026 вместе с закрытием пунктов: их место заняли показание и свидетели
# `test_state_lock_nonexclusive_mkdir.sh`, `test_dispatch_cksum_escaped_name.sh`, `test_iso_epoch_date_refuses.sh`.
# Зелёная сторона D522 снята 11 октября 2026 вместе с закрытием пункта: её место заняли показание и
# свидетель `hooks/tests/test_replace_uniqueness_guard.sh`; проба probe_D522.sh осталась «Проверкой».
# Зелёная сторона D459 снята 18 сентября 2026 вместе с закрытием пункта: её место заняли
# показание и свидетель `hooks/tests/test_verdict_through_pipe.sh` (21 нога, из них четыре
# судят УРЕЗАНИЕ отдельных шагов механизма, а не только «мёртв/жив»).
# Зелёные стороны D452, D453, D454 сняты 18 сентября 2026 вместе с закрытием пунктов: у закрытого
# её место занимают показание и настоящая проба. Форменные «Проверки» этих трёх (grep по имени
# переменной) заменены на `probe_D452/D453/D454.sh` — каждая подаёт payload субагента и судит
# РЕЗУЛЬТАТ механизма, у каждой положительный контроль, и каждая даёт 1 на дереве HEAD.
# Зелёные стороны D427–D437 (свидетели аудитов 17 сентября 2026) сняты тем же днём вместе с закрытием
# всех одиннадцати пунктов: их место заняло показание, пробы probe_D4xx.sh остались «Проверкой».
# Фикстуры green_D420/D421/D422/D423/D424/D425/D426 сняты 16-17 сентября 2026 вместе с закрытием пунктов: свидетель
# требует зелёную сторону у ОТКРЫТЫХ, а у закрытых её место занимает показание.
# Зелёные стороны D425/D426 сняты вместе с закрытием пунктов; их место заняло показание.
# Прежде здесь была НАСТОЯЩАЯ починка в миниатюре, а не файлы с нужным словом:
# «Проверка» обоих пунктов ЗАПУСКАЕТ стража, поэтому заглушка тут не проходит по построению.
# Сужает область признака владельцем `executable_part` — тем самым, которым закрыты D420, D424, D425.
# Тела вынесены в `hooks/tests/fixtures/`: внутри `python3 -c` внутри shell-функции это был бы
# ТРЕТИЙ уровень кавычек, и он разъезжается — проверено дважды, 16 и 17 сентября 2026.
# Каждая копия проверена ОБЕИМИ сторонами: на дефекте отказывает, на законном вызове молчит.
# ФОРМАТ ОКРУЖЕНИЯ: ОДНО ПРИСВАИВАНИЕ НА СТРОКУ. Функция `green_<ID>` печатает строки вида
# `ИМЯ=значение`, по одной на переменную; две в одной строке склеятся в одно значение, и
# вторая переменная до `env` не дойдёт. Прежде это нигде не было сказано, а все фикстуры
# отдавали по одной — дефект дождался первой многопеременной (24 сентября 2026).
run_check() {  # run_check <команда> <строки окружения> [ID] → код команды под окружением
    local cmd="$1" envs="$2" id="${3:-}" _e; local -a arr=()
    while IFS= read -r _e; do [ -n "$_e" ] && arr+=("$_e"); done <<< "$envs"
    # Ключ пункта — в окружение его «Проверки» (D503): позови она этого свидетеля снова, он
    # её не исполнит, а назовёт — иначе кольцо «свидетель → «Проверка» → свидетель».
    [ -n "$id" ] && command -v backlog_cmd_env >/dev/null 2>&1 \
        && arr+=("BACKLOG_CMD_RUNNING=$(backlog_cmd_env "$REPO/BACKLOG.md" check "$id" "$cmd")")
    # ПУСТОЙ МАССИВ ПОД set -u. `"${arr[@]}"` при нуле элементов — «unbound variable» в
    # bash 3.2 (macOS), подоболочка падает, и `echo $?` отдаёт не-0 — неотличимо от честной
    # красной команды. Отрицательный контроль T0 зову́т ровно с пустым окружением, то есть он
    # был зелен ОТ ОШИБКИ ОБОЛОЧКИ, а не оттого, что «Проверка» красна (13 сентября 2026).
    # Тот же класс, что D334: красный от рамки неотличим от красного по делу.
    # stdin команды закрыт: перечень пунктов идёт в цикл ниже по stdin, и «Проверка», читающая
    # stdin, выедала его остаток — свидетель молча судил меньше пунктов (D503, раунд 3, атака 4).
    ( cd "$REPO" && env ${arr[@]+"${arr[@]}"} bash -c "$cmd" >/dev/null 2>&1 </dev/null ); echo $?
}

# --- САМОПРОВЕРКА РАМКИ: зову́щий механизм различает предмет и себя ------------------------
# Ноги ниже судят по коду возврата run_check, и любой не-0 читают как «команда красна». Пока
# сбой САМОГО вызова тоже даёт не-0, два состояния мира идут по одному проводу (корень R6), и
# ложно-зелёный контроль неотличим от честного. Ровно это и случилось 13 сентября 2026:
# `env "${arr[@]}"` с пустым массивом под set -u ронял подоболочку, T0 зеленел от ошибки
# оболочки. Свидетель различающий: заведомо зелёная команда при ПУСТОМ окружении обязана дать
# 0 — верни прежнюю форму, и эта нога покраснеет первой.
_SELF=$(run_check "true" "")
[ "$_SELF" = "0" ] && ok || bad "T00" "рамка run_check сломана: заведомо зелёная команда под пустым окружением дала $_SELF — ноги ниже судят о своём сбое, а не о «Проверке»"
_SELF2=$(run_check "true" "FOO=bar")
[ "$_SELF2" = "0" ] && ok || bad "T00b" "рамка run_check сломана при непустом окружении: дала $_SELF2"

# --- отрицательный контроль: без фикстуры «Проверка» красна (иначе ноги ниже ничего не различают)
# ОГРАДА КОЛЬЦА (D503): «Проверка», уже исполняющаяся выше по дереву процессов, здесь не
# исполняется, вложенность глубже предела — тоже. Пропуск — СВОЙ исход: строка SKIP и код
# выхода 3, а не 0. Статические суждения (нет фикстуры, нет строки «Проверка») ничего не
# исполняют и выносятся ДО ограды: прежде пропуск стоял раньше них и прятал провал пункта без
# зелёной стороны, а через живые хуки давал ложный отказ уровня 4 (противник D503, атака 3).
RING=0
ring_skip() {  # ring_skip <ID> <команда> → 0 и строка SKIP, если исполнять нельзя
    local _why
    command -v backlog_cmd_blocked >/dev/null 2>&1 || return 1
    _why=$(backlog_cmd_blocked "$REPO/BACKLOG.md" check "$1" "$2") || return 1
    echo "SKIP [$1]: «Проверка» не исполнена — $_why (D503)"; RING=$((RING + 1)); return 0
}
NEG=$(backlog_open_items "$REPO/BACKLOG.md" | awk -F'\t' '$1 == "D307" { print $7 }')
if [ -n "$NEG" ] && ! ring_skip D307 "$NEG"; then
    RC=$(run_check "$NEG" "" D307)
    [ "$RC" != 0 ] && ok || bad "T0" "без фикстуры «Проверка» D307 зелёная (rc $RC) — пункт пора закрывать или команда не о дефекте"
fi

# --- каждый открытый пункт: фикстура есть и под ней «Проверка» зелёная ------------------------
# Строка библиотеки читается ЦЕЛИКОМ, поля — awk: `read` с IFS=таб схлопывает пустые поля
# (названный предел backlog-lib, первый прогон этого свидетеля подтвердил его заново).
N=0
while IFS= read -r ROW; do
    [ -n "$ROW" ] || continue
    ID=$(printf '%s' "$ROW" | awk -F'\t' '{print $1}')
    CHK=$(printf '%s' "$ROW" | cut -f7-)   # табуляция внутри «Проверки» — часть команды (D503, раунд 3)
    N=$((N + 1))
    if ! declare -F "green_$ID" >/dev/null 2>&1; then
        bad "$ID" "у открытого пункта нет зелёной стороны в этом свидетеле — добавь фикстуру green_$ID и строку «Зелёная сторона.» в пункт"; continue
    fi
    [ -n "$CHK" ] || { bad "$ID" "у пункта нет строки «Проверка»"; continue; }
    ring_skip "$ID" "$CHK" && continue
    # Код ноги ЧИТАЕТСЯ (D464). Без этого отказ ноги давал ПУСТОЕ окружение, «Проверка»
    # уходила на живое дерево и зеленела там — ложный PASS ровно того вида, ради которого
    # заведён пункт. Первая редакция починки научила отказу только ногу; ложный PASS остался,
    # потому что решает ЗДЕСЬ читатель, а не там отправитель.
    ENVS=$("green_$ID"); GRC=$?
    if [ "$GRC" != 0 ]; then
        bad "$ID" "зелёная сторона не собралась (код $GRC) — «Проверка» под ней не судилась"; continue
    fi
    RC=$(run_check "$CHK" "$ENVS" "$ID")
    [ "$RC" = 0 ] && ok || bad "$ID" "под фикстурой «Проверка» не позеленела (rc $RC; окружение: $(printf '%s' "$ENVS" | tr '\n' ' '))"
done <<EOF
$(backlog_open_items "$REPO/BACKLOG.md")
EOF
[ "$N" -gt 0 ] && ok || bad "T-open" "библиотека не видит ни одного открытого пункта — положительный контроль не пройден"

echo "backlog green side: открытых $N, PASS=$PASS FAIL=$FAIL${RING:+$( [ "$RING" -gt 0 ] && printf ', НЕ ИСПОЛНЕНО=%s (кольцо)' "$RING")}"
[ "$FAIL" -eq 0 ] || exit 1
[ "$RING" -eq 0 ] || exit 3
exit 0
