#!/usr/bin/env bash
# СУДИТ: hooks/command-scope-lib.sh hooks/root-cause-lib.sh
# test_write_predicate_operators.sh — «пишет ли команда» сверяется с ЭТАЛОНОМ, а не с
# ожиданием автора. Эталон — сама оболочка: команда исполняется в песочнице, и факт записи
# берётся из состояния каталога, а не из списка примеров.
#
# Повод (10 сентября 2026). Признак записи в `five-whys-gate.sh` объявлял записью читающий
# вызов, если в нём стоял оператор сравнения: `>=` совпадал с шаблоном перенаправления.
# Отказ приходил с текстом «чтение, поиск и осмотр не блокируются» — то есть страж отбивал
# ровно то, что сам обещал пропускать. Поймано на себе дважды за один ход, подтверждено
# независимым прогоном критика.
#
# Замер перед починкой, 60 крупнейших расшифровок, 16 632 вызова Bash: записью признаны
# 3374, из них 112 (3,3%) — единственно из-за `>=` и `->`.
#
# Тот же awk-блок стоял ДВУМЯ копиями (`five-whys-gate.sh`, `rules-write-bypass.sh`), обе
# под отказом, — потому здесь же проверяется, что копия не вернулась: род K реестра.
#
# Почему проверка примерами тут не годится: предмет — грамматика оболочки, а у проверки
# примерами нет понятия полноты (`pattern-subject-checked-by-enumeration`). Оболочка знает
# ответ точно, и спрашивают её.

set -uo pipefail

HOOKS_DIR="$(cd "$(dirname "$0")/.." && pwd)"
# shellcheck source=/dev/null
source "$HOOKS_DIR/command-scope-lib.sh"

PASS=0; FAIL=0
TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT

# Признак записи в том виде, в каком его применяет гейт (five-whys-gate.sh).
GATE_WRITE_RE='>>?[[:space:]]*[^&[:space:]]|[[:space:]]tee[[:space:]]|^tee[[:space:]]|git[[:space:]]+commit'
predicate_says_write() { grep -qE "$GATE_WRITE_RE" <<< "$(redirect_bare "$1")"; }

# ЭТАЛОН: исполнить в свежей песочнице и посмотреть, изменилось ли её содержимое.
world_changed() {
    local box; box="$TMP/box.$RANDOM"; mkdir -p "$box"
    local before after
    before=$(cd "$box" && find . -type f -exec cksum {} + 2>/dev/null | sort)
    ( cd "$box" && eval "$1" ) >/dev/null 2>&1 </dev/null
    after=$(cd "$box" && find . -type f -exec cksum {} + 2>/dev/null | sort)
    rm -rf "$box"
    [ "$before" != "$after" ]
}

check() {
    local name="$1" cmd="$2"
    local truth verdict
    if world_changed "$cmd"; then truth=ПИШЕТ; else truth=ЧИТАЕТ; fi
    if predicate_says_write "$cmd"; then verdict=ПИШЕТ; else verdict=ЧИТАЕТ; fi
    if [ "$truth" = "$verdict" ]; then
        PASS=$((PASS+1)); printf '  ✅ %-42s оболочка: %s · признак: %s\n' "$name" "$truth" "$verdict"
    else
        FAIL=$((FAIL+1)); printf '  ❌ %-42s оболочка: %s · признак: %s\n' "$name" "$truth" "$verdict"
    fi
}

echo "── признак записи против эталона-оболочки ──"

# Ложные срабатывания, ради которых починка (все ЧИТАЮТ):
check "heredoc с оператором >=" 'python3 - <<PY
print(1 if 2 >= 1 else 0)
PY'
check "heredoc со стрелкой ->"  'python3 - <<PY
d = {"a": 1}   # a -> b
print(len(d))
PY'
check "heredoc с >>= "          'python3 - <<PY
x = 4
x >>= 1
print(x)
PY'
check "heredoc со стрелкой =>"  'python3 - <<PY
print("k => v")
PY'
check "слияние потоков 2>&1"    'cat missing.txt 2>&1'
check "глушение в /dev/null"    'echo x > /dev/null'

# Положительный контроль — признак ОБЯЗАН краснеть на настоящей записи:
check "перенаправление в файл"  'echo hi > out.txt'
check "дозапись в файл"         'echo hi >> out.txt'
check "запись после сравнения"  'python3 - <<PY > res.txt
print(2 >= 1)
PY'
check "tee в файл"              'echo hi | tee out.txt'

echo
echo "── копия правила не вернулась (род K) ──"
# Поиск буквальный (-F): экранирование `&`, `>` и `?` в шаблоне уже дало здесь ноль
# носителей на первом же прогоне, а ноль — отказ прибора, не «копий нет».
CARRIERS=$(grep -rlF 'gsub(/&>>' "$HOOKS_DIR"/*.sh "$HOOKS_DIR"/lib/*.sh 2>/dev/null)
COPIES=$(printf '%s' "$CARRIERS" | grep -c . | tr -d ' ')
if [ "$COPIES" = "0" ]; then
    FAIL=$((FAIL+1)); echo "  ❌ ПРИБОР СЛОМАН: не найдена даже библиотека-владелец — поиск ничего не значит"
elif [ "$COPIES" = "1" ]; then
    PASS=$((PASS+1)); echo "  ✅ awk-блок очистки живёт в одном месте: $CARRIERS"
else
    FAIL=$((FAIL+1)); echo "  ❌ awk-блок очистки в $COPIES файлах — копия правила у потребителя"
    printf '%s\n' "$CARRIERS" | sed 's/^/       /'
fi

echo
echo "── учёт исхода (RC_OUT_WRITE_RE, третий носитель) ──"
# shellcheck source=/dev/null
source "$HOOKS_DIR/root-cause-lib.sh" 2>/dev/null || true
jq_says() { jq -rn --arg wr "$RC_OUT_WRITE_RE" --arg c "$1" '$c | test($wr)'; }
for probe in 'python3 -c "print(2 >= 1)":false' 'echo x > f.txt:true' \
             'grep -n "cp .*lib" file.sh:false' 'cp a.sh b.sh:true' \
             'awk "{if (a -> b) x}" f:false'; do
    cmd="${probe%:*}"; want="${probe##*:}"
    got=$(jq_says "$cmd")
    if [ "$got" = "$want" ]; then
        PASS=$((PASS+1)); printf '  ✅ %-38s → %s\n' "$cmd" "$got"
    else
        FAIL=$((FAIL+1)); printf '  ❌ %-38s → %s, ожидалось %s\n' "$cmd" "$got" "$want"
    fi
done

echo
echo "Прошло: $PASS, провалено: $FAIL"
exit $(( FAIL != 0 ))
