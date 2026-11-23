#!/usr/bin/env bash
# СУДИТ: BACKLOG-archive.md hooks/tests/test_external_events.sh hooks/tests/test_docs_family_a2_denies.sh hooks/tests/fixtures/probe_D1282.sh scripts/docs-address-drift.py scripts/regen-readme-skills.sh hooks/root-cause-lib.sh
# probe_D1366.sh — песочница архивной «Проверки» не наследует дерево сверщика архива после коммита.
#
# Повод (23 ноября 2026, D1366). Сверщик архива после коммита (`scripts/archive-checks-after-commit.sh`) судит клон
# коммита под TMPDIR и экспортирует CLAUDSOUL_REPO на клон, а «Проверки» её наследуют. «Проверка» D1045 строит свой
# песочный репозиторий, а прибор `scripts/docs-address-drift.py` берёт корень из CLAUDSOUL_REPO раньше каталога вызова —
# и мерил весь клон вместо песочницы. `test_external_events.sh` (вся «Проверка» D200, D201, D203, D224, часть D227) и
# проба D1282 ждут записи повода, а `rc_env_is_real` (`hooks/root-cause-lib.sh`) окружение с CLAUDSOUL_REPO под
# временным корнем считает фикстурой — повод не писался. `test_docs_family_a2_denies.sh` (D462) зовёт
# `scripts/regen-readme-skills.sh` без аргумента, и тот сводил таблицы песочницы по навыкам клона.
# Рамка здесь — та же, что у сверщика: клон HEAD с общими объектами под временным корнем и CLAUDSOUL_REPO на него.
# Клон накрыт рабочими версиями предметов из строки СУДИТ (как у проб D1249, D1257): иначе снятая в рабочей копии
# починка пробе не видна, и прибор свидетелей звал бы её ложно-зелёной (скептик opus по 9ffce99c, M2). «Проверки»
# исполняет владелец сверки архива (`probe_D1196.sh`, ручка PROBE_ARCHIVE_IDS) — судится их текст из архива. D227 в
# перечне нет: её красная часть — тот же `test_external_events.sh`, а `test_five_whys_gate.sh` один идёт 94–170 с, и
# проба не уложилась бы в 120 с сверщика; два других её свидетеля в этой рамке зелёные и без починки (49/49, 133/133).
# Проверка результата: bash hooks/tests/fixtures/probe_D1366.sh → 0 — «Проверки» держатся в рамке сверщика; 1 — красна
#   хоть одна (названа); 2 — не измерено (нет предмета, рамка не собралась либо не признана фикстурой).
set -uo pipefail
REPO="${CLAUDSOUL_REPO:-$(cd "$(dirname "$0")/../../.." && pwd)}"
IDS="D1045 D200 D201 D203 D224 D462 D1282"
SUBJ="BACKLOG-archive.md hooks/tests/test_external_events.sh hooks/tests/test_docs_family_a2_denies.sh
      hooks/tests/fixtures/probe_D1282.sh scripts/docs-address-drift.py scripts/regen-readme-skills.sh hooks/root-cause-lib.sh"
for f in $SUBJ hooks/tests/fixtures/probe_D1196.sh; do
    [ -f "$REPO/$f" ] || { echo "нет $f — не измерено"; exit 2; }
done
command -v git >/dev/null 2>&1 || { echo "нет git — не измерено"; exit 2; }
W=$(mktemp -d) || exit 2
trap 'rm -rf "$W"' EXIT
T="$W/repo"
{ git clone -q --shared --no-checkout "$REPO" "$T" && git -C "$T" checkout -q --detach HEAD; } >/dev/null 2>&1 \
    || { echo "клон HEAD не собрался — не измерено"; exit 2; }
for f in $SUBJ; do cp "$REPO/$f" "$T/$f" || { echo "предмет $f не лёг в клон — не измерено"; exit 2; }; done
# Положительный контроль рамки: владелец признака считает её корень частным. Иначе (TMPDIR вне временных корней)
# условие сверщика не воспроизведено, и зелёный `test_external_events.sh` ничего бы не доказал.
bash -c '. "$1/hooks/root-cause-lib.sh" 2>/dev/null && rc_path_is_private "$1"' _ "$T" \
    || { echo "корень рамки не признан частным — условие сверщика не воспроизведено, не измерено"; exit 2; }
out=$(cd "$T" && CLAUDSOUL_REPO="$T" PROBE_ARCHIVE_IDS="$IDS" bash hooks/tests/fixtures/probe_D1196.sh 2>&1); rc=$?
[ "$rc" = 0 ] && { echo "«Проверки» $IDS держатся в рамке сверщика"; exit 0; }
echo "в рамке сверщика — код $rc: $(printf '%s' "$out" | grep -v '^[[:space:]]*$' | tail -1)"
[ "$rc" = 1 ] && exit 1
exit 2
