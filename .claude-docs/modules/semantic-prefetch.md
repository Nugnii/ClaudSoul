# semantic-prefetch — фоновый предкэш семантического поиска

**Назначение.** Гибрид «keyword quick-hit + MCP background prefetch» (дизайн из
docs/architecture.md, статус слоя 2): семантическая дверь активатора открывается на
PreToolUse, где embedding-задержка платилась синхронно; предкэш уводит тот же запрос в
фон на реплике собеседника.

**Файлы.**
- `hooks/semantic-prefetch.sh` — зарегистрирован на UserPromptSubmit в группе с
  `reformulation-tracker.sh`: извлекает реплику (до 300 байт) + basename cwd, фоном
  (полная развязка дескрипторов `</dev/null`, atomic tmp+mv, timeout 10) прогоняет
  `mcp-server/cli_search.py <query> 5 2` и кладёт JSON в
  `state/semantic-prefetch-<SID>.json`. Единственный фоновый процесс в hooks/ —
  без развязки stdout «фон» держал бы ход открытым до конца MCP-вызова.
- `hooks/knowledge-semantic-fallback-lib.sh` — шестой аргумент `cache_file`: непустой
  кэш, записанный ПОЗЖЕ маркера последней реплики (`<cache>.prompt`; его синхронно
  трогает semantic-prefetch на каждом UserPromptSubmit), читается вместо синхронного
  вызова; протухший/отсутствующий (в т.ч. без маркера) — синхронный путь как был.
  Свежесть событийная, не TTL (D234): тема меняется репликами, не минутами. Вызов с
  кэшем — `hooks/knowledge-activator.sh` (fallback-блок).

**Деградация.** Нет jq / venv / реплики / `SKIP_MCP_FALLBACK=1` — тихий выход без
процесса (маркер реплики трогается до проверки venv: пропавший venv не оставляет
старый кэш вечно свежим). Кэш живёт одну реплику; маркер `score=99`/`via:"mcp"` в
журнале подач не меняется — предкэш меняет, ОТКУДА пришёл JSON, а не что с ним делают.

**Тест.** `hooks/tests/test_semantic_prefetch.sh` — кэш фоном, выключатель, деградация,
чтение кэша либой, TTL.
