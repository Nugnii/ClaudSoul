#!/usr/bin/env python3
"""green_D458.py — зелёная сторона D458: цикл замыкается независимо от секунды.

Починка в миниатюре, а не файл с нужным словом: когда перечень ФОРМ молчит и цели пришли
из МИРА, вызов оболочки одновременно и прогон, и свидетельство прежней правки — значит в
журнал идут ОБЕ записи. Сегодня пишется только `edit`, и цикл «правка → прогон → правка»
не растёт, если правка и прогон попали в разные секунды.
"""
import io
import sys

SRC, DST = sys.argv[1], sys.argv[2]
s = io.open(SRC, encoding="utf-8").read()

old = '''        _rw_world=$(rw_world_targets)
        [ -n "$_rw_targets" ] || _rw_targets="$_rw_world"'''
new = '''        _rw_world=$(rw_world_targets)
        _rw_from_world=0
        [ -n "$_rw_targets" ] || { _rw_targets="$_rw_world"; _rw_from_world=1; }
        # Цели пришли из МИРА, а не из перечня форм: команда сама ничего не писала, значит
        # это ПРОГОН, а изменение мира — след прежней правки. Пишем обе записи, иначе цикл
        # зависит от того, попали ли правка и прогон в одну секунду (D458).
        if [ "$_rw_from_world" = 1 ] && [ -n "$_rw_targets" ]; then
            printf '{"kind":"run"}\\n' >> "$LOG" 2>/dev/null || true
        fi'''
assert s.count(old) == 1, f"якорь встречается {s.count(old)} раз"
io.open(DST, "w", encoding="utf-8").write(s.replace(old, new, 1))
print(f"green_D458: патч наложен → {DST}")
