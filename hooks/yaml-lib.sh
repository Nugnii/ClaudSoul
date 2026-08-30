#!/bin/bash
# yaml-lib.sh — v1.0.0
# Единый парсер одного поля YAML frontmatter для хуков ClaudSoul.
#
# До v1.0.0 функция yaml_field была скопирована в bridge-health-digest.sh и
# knowledge-audit-digest.sh и УЖЕ разошлась: одна копия срезала только кавычки,
# другая — кавычки и скобки. Эта библиотека — единый источник (канон —
# версия со срезкой скобок, она строго полнее).
#
# Provides:
#   yaml_field <file> <key>   → значение поля из frontmatter (первый матч), или пусто
#
# Поведение:
#   - читает только frontmatter (между первым и вторым '---'); body игнорируется
#   - первый матч ключа выигрывает
#   - срезает один ведущий и один хвостовой символ из { " ' [ ] }:
#       status: active        → active
#       name: "foo bar"       → foo bar
#       domain: [test]        → test
#       layers: [L2, L3]      → L2, L3
#   - отсутствующее поле или отсутствующий файл → пустая строка, без падения
#
# Fail silently — источается из хуков, где ошибка не должна ронять процесс.

yaml_field() {
    local file="$1" key="$2"
    awk -v k="$key" '
        /^---$/ { depth++; if (depth >= 2) exit; next }
        depth == 1 && $0 ~ "^"k":" {
            sub("^"k":[[:space:]]*", "")
            gsub(/^["\x27[]|["\x27\]]$/, "")
            print
            exit
        }
    ' "$file" 2>/dev/null
}
