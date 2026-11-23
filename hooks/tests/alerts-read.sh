#!/usr/bin/env bash
# alerts-read.sh (тесты) — всё, что хуки сказали агенту через очереди, одним чтением (D1304).
#
# Зачем. С D1304 у сообщения три адресата и три канала: общая очередь `pending-alerts.txt` (обо всей системе), канал
# своей сессии `stop-signals-<sid>.txt` (`session_alert`) и канал проекта `project-signals-<ключ>.txt`
# (`project_alert`, `hooks/paths-lib.sh`). Свидетель, судивший «что сказано», читал одну очередь и после D1304 видел бы
# пустоту. Владелец чтения один — эта функция; куда именно ушло сообщение, судит свой свидетель
# (`hooks/tests/test_alerts_reach_their_addressee.sh`), а не каждый потребитель.
#
# alerts_of <каталог состояния> — печатает содержимое всех трёх каналов (порядок: очередь, сессии, проекты).
# alerts_clear <каталог состояния> — опустошает все три (между прогонами одного свидетеля).
alerts_of() {
    local st="$1" f
    for f in "$st/pending-alerts.txt" "$st"/stop-signals-*.txt "$st"/project-signals-*.txt; do
        [ -f "$f" ] && cat "$f"
    done
    return 0
}
alerts_clear() {
    local st="$1" f
    for f in "$st/pending-alerts.txt" "$st"/stop-signals-*.txt "$st"/project-signals-*.txt; do
        [ -f "$f" ] && : > "$f"
    done
    return 0
}
