#!/usr/bin/env python3
"""green_D442.py <src> <dst> — миниатюрная НАСТОЯЩАЯ починка `scripts/backlog-recheck.sh`
на копии: блок D411 читает `mcp-server/visualization/project-graph-data.json` мимо
`project-graph.py` (D427) и на карте с висячим циклическим ребром (1→999→1) падает
`KeyError` внутри вложенного питона, а снаружи это неотличимо от «нет python3 либо git» —
одно значение канала `_SPIRAL="?"` на ДВА разных состояния мира (корень R6).

Патч заводит третье значение `MAP_BROKEN`: питон-часть ловит `KeyError` именно там, где он
уже наблюдён (сборка множества `names` по компоненте `best`), и печатает сентинел вместо
падения; bash-часть получает для него СВОЮ ветку — `report broken` с текстом про целость
снимка, а не про отсутствие инструментов. Обе стороны патчатся одним якорем каждая; `assert`
проверяет, что якорь найден до замены — иначе исходник изменился и патч встанет вслепую.

Использование: python3 green_D442.py <src backlog-recheck.sh> <dst backlog-recheck.sh>
"""
import sys

ANCHOR_PY = (
    'names = {idx[x]["key"] for x in best\n'
    '         if idx[x].get("key") and os.path.exists(idx[x]["key"])}\n'
)
PATCH_PY = (
    'try:\n'
    '    names = {idx[x]["key"] for x in best\n'
    '             if idx[x].get("key") and os.path.exists(idx[x]["key"])}\n'
    'except KeyError:\n'
    '    print("MAP_BROKEN")\n'
    '    sys.exit(0)\n'
)

ANCHOR_SH = (
    'if [ "$_SPIRAL" = "?" ]; then\n'
    '    report unproven "D411" "нет python3 либо git — спираль правок НЕ ИЗМЕРЕНА"\n'
    'else\n'
)
PATCH_SH = (
    'if [ "$_SPIRAL" = "MAP_BROKEN" ]; then\n'
    '    report broken "D411" "карта НЕ ЦЕЛА — спираль правок посчитана быть не может '
    '(нарушена ссылочная целость снимка mcp-server/visualization/project-graph-data.json)"\n'
    'elif [ "$_SPIRAL" = "?" ]; then\n'
    '    report unproven "D411" "нет python3 либо git — спираль правок НЕ ИЗМЕРЕНА"\n'
    'else\n'
)


def main() -> None:
    src, dst = sys.argv[1], sys.argv[2]
    text = open(src, encoding='utf-8').read()
    assert ANCHOR_PY in text, 'якорь (питон) не найден — backlog-recheck.sh изменился с момента написания патча'
    assert ANCHOR_SH in text, 'якорь (bash) не найден — backlog-recheck.sh изменился с момента написания патча'
    text = text.replace(ANCHOR_PY, PATCH_PY, 1)
    text = text.replace(ANCHOR_SH, PATCH_SH, 1)
    open(dst, 'w', encoding='utf-8').write(text)


if __name__ == '__main__':
    main()
