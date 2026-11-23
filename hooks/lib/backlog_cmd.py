"""backlog_cmd.py — ограда кольца (D503) у питонских исполнителей команд бэклога: решает ВЛАДЕЛЕЦ правила.

Результат: гейт границы хода, архиватор и пересчёт показаний судят кольцо правилом `hooks/backlog-lib.sh`
           (`backlog_cmd_blocked`, `backlog_cmd_env`) — правка правила в библиотеке меняет решение всех исполнителей
Проверка результата: bash hooks/tests/fixtures/probe_D1238.sh даёт 0

Зовут: `hooks/completion-gate.sh` («Проверки» на Stop), `scripts/backlog-archive.sh` (закрытые при переносе),
`scripts/backlog-refresh-readings.sh` («Показания»). До D1238 у каждого стояла своя копия правила оболочки на 32 строки —
ключ «текст команды#ID#вид», метка файла «устройство:inode», разделители и предел глубины, — и правка библиотеки до них
не доходила (тот же корень R1, что у копий снятия по сроку до D1199). Теперь правило спрашивается у библиотеки тем же
приёмом, что признак «ждёт скептика» у гейта (`_awaits_skeptic`): одна оболочка на команду.
Библиотеки нет или в ней нет функции ограды — ограды нет, как до неё: ("", None).
"""
import os
import subprocess

_SH = ('. "$1" 2>/dev/null || exit 3; command -v backlog_cmd_blocked >/dev/null 2>&1 || exit 3; '
       'if why=$(backlog_cmd_blocked "$2" "$3" "$4" "$5"); then printf "B%s" "$why"; '
       'else printf "R%s" "$(backlog_cmd_env "$2" "$3" "$4" "$5")"; fi')


def blocked(bpath, kind, iid, cmd, lib=None):
    """→ (причина пропуска, новое BACKLOG_CMD_RUNNING для окружения команды либо None).

    Причина непуста — команду не исполнять (кольцо или вложенность глубже предела). `lib` — путь библиотеки долга; по
    умолчанию — `backlog-lib.sh` того же дерева, что модуль (`hooks/lib/..`).
    """
    lib = lib or os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "backlog-lib.sh")
    if not os.path.isfile(lib):
        return "", None
    try:
        r = subprocess.run(["bash", "-c", _SH, "_", lib, str(bpath), kind, iid, cmd],
                           capture_output=True, text=True, timeout=30, stdin=subprocess.DEVNULL)
    except (OSError, subprocess.TimeoutExpired) as e:
        # Отказ оболочки — ограда ЗАКРЫТА (скептик opus по f8006ea0, M2): исполнить без записи в BACKLOG_CMD_RUNNING
        # значило бы снять предел глубины. Старая библиотека без функции (код 3) — ограды нет, как до неё.
        return f"ограда кольца не ответила ({e.__class__.__name__}) — команда не исполнена", None
    out = r.stdout or ""
    if r.returncode == 3 or not out:
        return "", None
    if out[0] == "B":
        return out[1:], None
    return "", out[1:]
