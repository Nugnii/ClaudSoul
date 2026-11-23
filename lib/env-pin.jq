# env-pin.jq — закрепление категорий локали в блоке env настроек Claude Code.
# Результат: хуки и скрипты, запущенные из Claude Code, разбирают и печатают числа и сравнивают
#            строки как под C, в какой бы локали ни шёл терминал; классы символов (LC_CTYPE) не тронуты
# Проверка результата: bash hooks/tests/test_env_pin.sh даёт 0
#
# Повод (D1176, 28 октября 2026). Терминальный `claude` идёт с LANG=ru_RU.UTF-8, и хуки получают
# его локаль. Под ней /usr/bin/awk читает «1.5» как 1, печатает «%.1f» как «4,0», «100.0» > 100
# сравнивает строкой, а метки «☐» и «◐» считает равными; printf в bash отвергает «4.0». Замер
# по категориям: числа держит LC_NUMERIC, равенство не-ASCII — LC_COLLATE; с обеими в C поведение
# совпадает с C.UTF-8. Мест, опирающихся на это поведение, больше ста файлов с awk, общей точки
# входа у хуков нет — поэтому закрепление стоит там, откуда окружение получают все: в env настроек.
#
# Значения живут ТОЛЬКО здесь. Режимы (`--arg mode …`):
#   record   — новая запись `{values, had_env}` для `~/.claude/claudsoul-env-prev.json`: прежняя запись
#              (`$ARGS.named.prev`) плюс ЧУЖИЕ значения наших ключей, стоящие сейчас (своё «C» в неё не
#              попадает никогда — иначе сниматель вернул бы закрепление вместо снятия, H1 второго круга);
#              `had_env` — был ли env объектом до первой установки (берётся у прежней записи);
#              Ключ, которого в env-объекте больше нет (пользователь удалил), из записи уходит — снятие
#              его не воскресит (L2 третьего круга);
#   valid    — годится ли файл записи (вход — файл через `jq -s`): ровно один документ — объект только с
#              ключами values (объект строк) и had_env (булево, обязателен). Единственный судья формы — его
#              зовут установщик и сниматель;
#              запись иного вида (битая, прежняя `{LC_*: …}`) не годна, её не перетирают и называют;
#   keys     — имена наших ключей, по строке (рамка снимает их без своего перечня);
#   replaced — строки «КЛЮЧ=прежнее» у ключей, чьё значение `set` заменит (установщик о них говорит);
#   set      — влить закрепление, сохранив прочие ключи; env не-объект — ошибка, файл не трогается;
#   unset    — снять: трогается только ключ с НАШИМ значением — он получает чужое значение из записи
#              либо снимается; ключ, который пользователь сменил после установки, остаётся; env, ставший
#              пустым, удаляется, если его не было до установки (без записи — если его опустошило снятие).
# Проба мира сверяет, что `set` над живыми настройками ничего не меняет.
#
# НАЗВАННЫЕ ПРЕДЕЛЫ. 1. LC_ALL, выставленный в окружении или в env, перекрывает обе категории —
#    закрепление тогда не действует (установщик и рамка `scripts/world-locale-run.sh` о нём говорят).
#    2. Ручной запуск скрипта из терминала идёт мимо настроек Claude Code и закрепления не получает.
#    3. LC_COLLATE=C задаёт порядок по байтам во ВСЕХ проектах, где работает агент: `sort` ставит
#    прописные раньше строчных («Beta Zeta alpha»), «ё» — после «я» («ель яма ёлка»); решение владельца
#    принималось с этим условием. 4. Своё «C» пользователя, стоявшее до установки, от нашего не отличить:
#    сниматель его снимет (решение владельца по второму кругу — цена того, что закрепление не переживает
#    снятие).

def pin: {"LC_NUMERIC": "C", "LC_COLLATE": "C"};
def envobj: (.env // {}) | if type == "object" then . else {} end;
# Чужое для записи — только СТРОКА: значения env в настройках Claude Code строковые, и запись с иным типом
# не прошла бы своего же судью (M1 четвёртого круга); не-строку `replaced` называет, а не записывает.
def foreign: envobj | with_entries(. as $e | select((pin | has($e.key)) and ($e.value | type) == "string" and $e.value != pin[$e.key]));
def rec_ok: type == "object"
    and (keys - ["values", "had_env"] | length) == 0
    and has("had_env") and (.had_env | type) == "boolean"
    and ((.values // {}) | type == "object" and all(.[]; type == "string"));

if $mode == "record" then
    ($ARGS.named.prev // {}) as $r
    | . as $s
    | (($r.values // {})
       | if ($s.env | type) == "object" then with_entries(select(.key as $k | $s.env | has($k)))
         elif $s.env == null then {}
         else . end) as $kept
    | {values: ($kept + foreign),
       had_env: (if ($r | has("had_env")) then $r.had_env else ((.env | type) == "object") end)}
elif $mode == "valid" then
    # Вход — файл, прочитанный `jq -s`: ровно один документ, и он годен (M4 четвёртого круга: без -s
    # каждый документ судился отдельно, и файл из двух проходил по последнему).
    if type == "array" then length == 1 and (.[0] | rec_ok) else rec_ok end
elif $mode == "keys" then
    pin | keys[]
elif $mode == "replaced" then
    envobj | to_entries[] | . as $e | select((pin | has($e.key)) and $e.value != pin[$e.key])
    | if ($e.value | type) == "string" then "\($e.key)=\($e.value)"
      else "\($e.key)=\($e.value | tojson) — не строка, в запись не попадает" end
elif $mode == "set" then
    if (.env // {} | type) != "object" then error("env-pin.jq: env в настройках не объект — закрепление не поставлено")
    else .env = ((.env // {}) + pin) end
elif $mode == "unset" then
    ($ARGS.named.prev // {}) as $r
    | ($r.values // {}) as $v
    | if (.env | type) == "object" then
        (.env | length) as $before
        | .env |= with_entries(. as $e
            | if (pin | has($e.key)) and $e.value == pin[$e.key] then
                  (if ($v | has($e.key)) then .value = $v[$e.key] else empty end)
              else . end)
        | if .env != {} then .
          elif ($r | has("had_env")) then (if $r.had_env then . else del(.env) end)
          elif $before > 0 then del(.env)
          else . end
      else . end
else
    error("env-pin.jq: mode — record, valid, keys, replaced, set либо unset, получено «\($mode)»")
end
