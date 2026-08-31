#!/usr/bin/env bash
# knowledge-semantic-fallback-lib.sh — мост L1↔L2: семантический откат MCP.
#
# Извлечено из knowledge-activator.sh (Ф4, слой semantic-fallback). Когда keyword-
# скоринг слаб (top score < 3 ИЛИ < 2 результатов), запрашивает MCP cli_search и
# отдаёт новые (не-дубликаты) записи с синтетическим score 99 — closes vocabulary
# gap, который keyword-скоринг пропускает даже при confidence 4+.
#
# Чистая граница: явные параметры → echo новых строк "99|basename|...". НЕ мутирует
# глобальный RESULTS вызывающего — тот дописывает сам. Не для standalone-подключения.

# Args: root, query, kw_top_score, n_results, seen_basenames (формат "|bn1|bn2|"),
#       [cache_file] — предкэш от semantic-prefetch.sh (D233): непустой кэш, записанный
#       ПОЗЖЕ маркера последней реплики ("$cache.prompt", D234), читается ВМЕСТО
#       синхронного вызова — PreToolUse не платит embedding-задержку;
#       протухший/отсутствующий кэш — синхронный путь как был.
# Echoes: новые строки результата (по одной), либо ничего (откат не сработал).
mcp_semantic_fallback() {
    local root="$1" query="$2" kw_top="${3:-0}" n_res="${4:-0}" seen="${5:-}" cache="${6:-}"
    { [ "$kw_top" -lt 3 ] || [ "$n_res" -lt 2 ]; } || return 0
    local cli="$root/mcp-server/cli_search.py" py="$root/mcp-server/.venv/bin/python"
    local json=""
    # Свежесть кэша — событийная (D234): кэш жив, если записан ПОЗЖЕ маркера последней
    # реплики ("$cache.prompt", его трогает semantic-prefetch на каждом UserPromptSubmit).
    # Тема меняется репликами, не минутами: кэш прошлой реплики — прошлая тема, сколько
    # бы минут ни прошло. Нет маркера (кэш без предкэша) — кэш считается протухшим:
    # синхронный путь как был. Проверка -f перед -nt обязательна: bash трактует
    # «file2 не существует» как «file1 новее». bash 3.2 сравнивает mtime посекундно —
    # кэш, легший в ту же секунду, что маркер, прочтётся как несвежий; цена — лишь
    # синхронный вызов.
    if [ -n "$cache" ] && [ -s "$cache" ] && [ -f "$cache.prompt" ] \
       && [ "$cache" -nt "$cache.prompt" ]; then
        json=$(cat "$cache" 2>/dev/null || echo "[]")
    fi
    if [ -z "$json" ]; then
        [ -f "$cli" ] && [ -x "$py" ] || return 0
        [ -n "$query" ] || return 0
        local to=""
        if command -v timeout >/dev/null 2>&1; then to="timeout 3"
        elif command -v gtimeout >/dev/null 2>&1; then to="gtimeout 3"; fi
        json=$(cd "$root/mcp-server" && $to "$py" cli_search.py "$query" 5 2 2>/dev/null || echo "[]")
    fi
    # `|` — разделитель протокола RESULTS, а в .name он реально встречается
    # (case «grep без || true убивает скрипт»): поля разъезжались в read, и запись
    # injection-log выходила битой (143 строки из 173). Вычищаем на границе.
    echo "$json" | jq -r '.[] | [(.file_path // ""), (.name // ""), (.type // ""),
        (.confidence // 0), (.impact // 0)] | map(tostring | gsub("\\|"; "/")) | join("|")' 2>/dev/null | \
    while IFS='|' read -r FP NM TP CF IM; do
        [ -z "$FP" ] && continue
        local bn; bn=$(basename "$FP")
        case "$seen" in *"|$bn|"*) continue ;; esac
        printf '99|%s|%s|mcp-semantic|%s|%s|false|0|universal|valid|fresh\n' "$bn" "$NM" "$CF" "$IM"
        seen="$seen|$bn|"
    done
}
