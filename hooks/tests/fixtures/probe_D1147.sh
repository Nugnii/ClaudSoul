#!/usr/bin/env bash
# СУДИТ: scripts/backlog-recheck.sh
# probe_D1147 — закрытый пункт, чья «Проверка» в архиве покраснела, назван сверщиком закрытых по имени. До пункта
# «Проверку» закрытого пункта после архива не исполнял никто: откат D439 (D1114) нашёлся случайно, при проверке
# зависимых соседнего пункта. Дерево-фикстура: архив с закрытым D9, чья «Проверка» — проба с кодом 1, и копия
# сверщика с библиотекой бэклога. Исполняет «Проверки» режим `--archive` — так, как его зовёт бегун замеров (вывод
# в `measurement-runs/archive-checks.out`); имя обязано дойти до обычного прогона, который читает дайджест.
# Красная (1), пока сверщик молчит о D9 либо зовёт гнилую пробу D8 (код 2) откатом; 2 — рамка не собралась.
R="${CLAUDSOUL_REPO:-$(cd "$(dirname "$0")/../../.." && pwd)}"
[ -f "$R/scripts/backlog-recheck.sh" ] && [ -f "$R/hooks/backlog-lib.sh" ] || exit 2
T=$(mktemp -d) || exit 2
trap 'rm -rf "$T"' EXIT
mkdir -p "$T/scripts" "$T/hooks/tests/fixtures" "$T/state/measurement-runs" \
    && cp "$R/scripts/backlog-recheck.sh" "$T/scripts/" && cp "$R/hooks/backlog-lib.sh" "$T/hooks/" || exit 2
printf '#!/usr/bin/env bash\nexit 1\n' > "$T/hooks/tests/fixtures/probe_D9.sh"
: > "$T/BACKLOG.md"
printf -- '- ☑ **D9** закрыт пробой\n  **Проверка.** `bash -c '"'"'bash hooks/tests/fixtures/probe_D9.sh'"'"'` → 0\n- ☑ **D8** гнилая проба\n  **Проверка.** `exit 2` → 0\n' > "$T/BACKLOG-archive.md"
( cd "$T" && git init -q . ) >/dev/null 2>&1 || exit 2
# Маркер вложенности снимается: проба сама идёт «Проверкой» (гейт и архиватор ставят его), а `--archive` под ним
# честно отвечает «не исполнялось». Кольцо держит ключ библиотеки, не маркер (D503).
# Приманка `BACKLOG_ARCHIVE`: так архиватор зовёт «Проверки» из сборщика (архив локального проекта) — путь
# архива сверщика от неё не зависит (скептик D1147, круг 1, H3). Маркер вложенности снят у обоих вызовов: внутри
# «Проверки» пересказ чужих закрытий не судится (M3), а гейт и архиватор зовут пробу именно с ним.
printf -- '- ☑ **D7** приманка\n  **Проверка.** `true` → 0\n' > "$T/decoy.md"
( cd "$T" && env -u BACKLOG_CHECKS_NESTED BACKLOG_ARCHIVE="$T/decoy.md" CLAUDSOUL_REPO="$T" STATE_DIR="$T/state" \
    bash scripts/backlog-recheck.sh --archive > "$T/state/measurement-runs/archive-checks.out" 2>&1 < /dev/null )
out=$(cd "$T" && env -u BACKLOG_CHECKS_NESTED CLAUDSOUL_REPO="$T" STATE_DIR="$T/state" LESSONS_DIR="$T/lessons" \
    BACKLOG_RECHECK_VERBOSE=1 bash scripts/backlog-recheck.sh 2>&1)
grep -q '✗ D9 ' <<< "$out" || { echo "сверщик закрытых молчит о покрасневшей «Проверке» закрытого D9"; exit 1; }
# Гнилая проба (код 2: рамка не собралась) — «не измерено», не откат: вторая половина Результата.
grep -q '? D8 ' <<< "$out" && ! grep -q '✗ D8 ' <<< "$out" || { echo "гнилая проба D8 не отличена от отката"; exit 1; }
echo "покрасневшая «Проверка» закрытого пункта названа"
exit 0
