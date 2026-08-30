---
name: Переносимость оболочки — не полагайся на семантику конкретного shell в коде хуков и скиллов
description: Код для хуков и скиллов полагается на семантику конкретной оболочки (bash word-splitting, массивы, read -ra), но среда исполнения не гарантирована — Bash-инструмент Claude Code на macOS это zsh. Результат — молчаливые сбои. Писать переносимо или оборачивать в bash -c; парсинг делегировать jq/awk.
type: pattern
outcome: error
confidence: 5
impact: 3
intensity: 2
confirmed_count: 1
contradicted_count: 0
last_confirmed: 2026-08-30
source_cases:
  - case-2026-04-21-bash-tool-is-zsh.md
  - case-2026-06-20-zsh-for-loop-no-word-split.md
  - case-2026-06-20-zsh-nested-quotes.md
  - case-2026-06-21-grep-is-ugrep-not-gnu.md
  - "ProjectA security-gate.sh (2026-07-06): незакавыченный `$SEMGREP` (= путь с пробелом «…/My Project/…/.venv-security/bin/semgrep») словоделился на 2 аргумента → команда не найдена → пустой JSON → гейт дал ЛОЖНУЮ блокировку релиза. Ручной прогон работал (относительный путь без пробела). Фикс: `\"$SEMGREP\"` во всех вызовах. Всегда квотить переменные с путями (репо под «My Project» — пробел в пути гарантирован)."
status: active
preceded_artifact: no   # portable-lib.sh (v1.14.3) построен ПОСЛЕ того, как CI упал на date -j, а не из знания. Знание существовало (уверенность 5, девять подтверждений) и было процитировано в шапке, но причиной постройки был красный прогон, а не оно. Ровно тот случай, ради различения которого поле и заведено

# Контекстные якоря
domain: [shell_scripting, bash, zsh, hooks, skills, claude_code_internals, tooling]
situation: "writing_shell_command_for_hook_or_skill"
trigger: "shell_specific_construct_in_unverified_environment"
stakes: "silently_broken_command, tests_pass_but_real_env_fails"
actors: [agent, bash_tool]
environment: "macos, claude_code_bash_tool_is_zsh"
circumstances: "sourced_library_or_skill_command, execution_shell_not_guaranteed"
purpose: "portable_robust_tooling"
method: "bash_c_wrapper_or_delegate_to_jq_awk"
tags: [shell_compat, environment_assumption, read_ra, arrays, word_splitting, portability]

need: "avoid_shell_specific_breakage_in_hooks_and_skills"
urgency: "when_relevant"
availability: "unique"

related:
  - case-2026-04-21-bash-tool-is-zsh.md
  - case-2026-04-15-grep-set-e-crash.md
  - case-2026-04-22-pipefail-head-jq-jsonl.md
  - pattern-inside-out-blindness.md
edges:
  - specializes: pattern-inside-out-blindness.md
  - generalizes: case-2026-04-21-bash-tool-is-zsh.md

# Promotion & scope (v1.0.9)
promotion_tier: 2
scope: universal
origin_domain: shell_scripting

# Modification lineage
modification_history:
  - date: 2026-08-30
    kind: narrowed
    reason: "сигнал bsd_only_command_in_hook (отказ на Edit/Write в hooks|scripts с BSD-формой в тексте) снят: первый прогон dead-sensor — ноль срабатываний за 40 сессий; реплей по 33 расшифровкам — 14 правок с такими формами прошли мимо, 39 шли через Bash, где стоит свой сигнал bsd_only_command_written_via_shell (сигнал на Edit/Write мёртв по построению); а в дереве 10 файлов несут BSD-формы парой с GNU, и сработавший сигнал отказал бы на переносимом коде. Инвариант «BSD-форма только в паре с GNU» держит тест по дереву hooks/tests/test_bsd_forms_paired.sh — он видит результат правки любым инструментом"
    trigger_case: case-2026-08-30-signal-dead-by-construction-and-hostile-to-portable-code.md
  - date: 2026-07-29
    kind: narrowed
    reason: "сигналы сужены до Edit/MultiEdit и дополнены предикатом. При Write в payload уходит ВЕСЬ файл, и совпадение нельзя отличить от законного фрагмента в другом месте — замер: горело на 5 файлах из 6, включая portable-lib.sh, где `stat -f` стоит в запасной ветке легально. При Edit payload это изменяемый кусок: горит на трёх формах дефекта, молчит на трёх чистых правках включая русский комментарий"
    trigger_case: case-2026-07-29-signal-enumerates-cannot-predicate.md
  - date: 2026-07-29
    kind: reinforced_after_challenge
    reason: "поднят до blocker-tier — сигналы выведены из пяти ИЗМЕРЕННЫХ отказов за одну сессию (date -j, stat -f, tail -r, tr с кириллицей, диапазон [а-яё] в C.UTF-8), а не придуманы. Заявка на это лежала в escalation_hint с 2026-06-21 и полтора месяца не была закрыта"
    trigger_case: case-2026-07-29-fix-inherits-its-own-defect.md
  - date: 2026-06-21
    kind: narrowed
    reason: "limitation «grep переносимы, обёртки не требуют» сужена — системный grep может быть ugrep со строгим ERE (литеральные { падают); правило теперь покрывает не только shell, но и идентичность CLI-инструмента"
    trigger_case: case-2026-06-21-grep-is-ugrep-not-gnu.md
provenance_log:
  - date: 2026-07-29
    kind: reinforced
    reason: "dis_scan_open: повторное 'local sid' в цикле печатает sid=<значение> в stdout под zsh, чисто в bash; выдача функции разбирается потребителями, и /learn предписывает звать её через Bash-инструмент, то есть под zsh"
    trigger_case: v1.14.1 D9 root cause
  - date: 2026-07-29
    kind: reinforced
    reason: "класс дал четвёртую форму за сессию; корень оказался не в самом знании, а в том, что его сигнал детекции мог только перечислять"
    trigger_case: case-2026-07-29-signal-enumerates-cannot-predicate
  - date: 2026-08-07
    kind: reinforced
    reason: "инжект 2026-08-02: в той же сессии неэкранированный === в zsh-инлайне дважды ронял команду ((eval): not found) — семантика оболочки укусила ровно по правилу"
  - date: 2026-08-08
    kind: reinforced
    reason: "хук external-correction-gap написан по правилам переносимости: to_lower из portable-lib для кириллицы, фиксированные подстроки вместо кириллических классов, явные заглавные fallback-написания — тест зелёный в т.ч. в рамке CI"
  - date: 2026-08-08
    kind: reinforced
    reason: "accepted-alternative-gap: bash-шебанг, POSIX-совместимые конструкции, транскрипт-jq по образцу output-language-check — семантика shell не предполагается, знание соблюдено"
  - date: 2026-08-08
    kind: reinforced
    reason: "ablation-phase-guard: «$PHASE» — ёлочка вплотную к переменной, байт прилип к имени (unbound под set -u); blocker предупреждал об этом классе тем же днём — знание инжектилось и не применилось"
  - date: 2026-08-09
    kind: reinforced
    reason: "pre-commit на #!/bin/sh: убрал пайп вместо set -o pipefail — статус конвейера скрыл бы падение сборки под set -e"
  - date: 2026-08-09
    kind: reinforced
    reason: "deploy.sh получил local+disown — проверил шебанг (#!/usr/bin/env bash) и прогнал конструкции на macOS bash 3.2 перед тем как считать фикс готовым"
  - date: 2026-08-09
    kind: reinforced
    reason: "npm run lint под 'timeout 900' → zsh: command not found: timeout (macOS без coreutils); тот же класс"
  - date: 2026-08-11
    kind: reinforced
    reason: "дважды подстановка в zsh сломала заголовки curl (word splitting в ${var:+-H ...}) — выдача пустая, чуть не принял за отказ сервера; проверил прямым вызовом"
  - date: 2026-08-15
    kind: reinforced
    reason: "в compile-проходе обернул read -ra в bash -c из-за возможного zsh — прямое применение переносимости"
  - date: 2026-08-16
    kind: reinforced
    reason: "фикс канарейки: mktemp-шаблон без суффикса (macOS), счётчик в подоболочке заменён на mktemp — семантика shell учтена, тесты 16/16"
  - date: 2026-08-21
    kind: reinforced
    reason: "partial-read-guard.sh: ${FILE_PATH,,} упало на bash 3.2 (macOS) — bad substitution; заменено на tr. Ровно предсказанный класс"
  - date: 2026-08-23
    kind: reinforced
    reason: "правки в 9 хуках велись с оглядкой на переносимость: bash -n на каждом, fallback-определение is_git_commit при отсутствии библиотеки, grep -E без GNU-специфики; отдельно подтвердилось на macOS, где нет timeout(1)"
  - date: 2026-08-25
    kind: reinforced
    reason: "Написал в тесте '«$trimmed»' — bash 3.2 включил первый байт UTF-8 символа » (xc2) в имя переменной, тест упал с 'trimmed?: unbound variable' вместо того чтобы назвать нарушение. Плюс '${var: -50}' там же роняет под set -u. Оба поймал только мутационный прогон: на здоровом дереве страж был зелёный."
  - date: 2026-08-25
    kind: reinforced
    reason: "Третий раз за сессию: 'printf | grep -q' под set -o pipefail. Совершил его В ТЕСТЕ, который проверяет класс shell-дефектов, и тест из-за этого объявлял непокрытыми файлы, которые обход открывает. Метатест test_assert_no_sigpipe этот приём запрещает и поймал бы при прогоне набора — но моя проверка была написана и прочитана как верная."
  - date: 2026-08-26
    kind: reinforced
    reason: "дважды за сессию: инжектор Core написан на Python, а не shell, именно потому что tr/awk на BSD побайтовые и кириллицу не сложат; и мой же проверочный вызов упал на отсутствующем на macOS timeout — код 127 я едва не прочитал как «зависания нет»"
  - date: 2026-08-26
    kind: reinforced
    reason: "правка throttle-lib: проверка уборки в zsh снесла и защищённые семейства, в bash отработала верно — знание направило диагностику на оболочку, а не на правку"
  - date: 2026-08-27
    kind: reinforced
    reason: "26.08 в сессии babbcc5a: sed -n N,+12p — BSD sed на macOS не понимает адресацию ,+N, команда упала (sed: 1: invalid command code ,)"
    trigger_case: case-2026-08-27-auto-draft-fires-without-an-incident.md
    session: ""
  - date: 2026-08-27
    kind: reinforced
    reason: "Дважды за ход изменило код: правку теста писал python3, а не head -n -3 (BSD head отрицательный аргумент не берёт); в grep -E признака взял .{0,3} вместо класса с кириллицей и тире, который зависит от локали в BSD grep. Оба раза правило пришло инжектом до написания строки, а не после падения."
    session: ""
  - date: 2026-08-28
    kind: reinforced
    reason: "bash 3.2 не разбирает case внутри $(); zsh не делит переменную по словам"
    session: ""
  - date: 2026-08-28
    kind: reinforced
    reason: "Сработало по делу дважды за сессию: отбило timeout (на macOS его нет, вызов вернул бы 127 и прочитался как «прошло без находок») и заставило сверить herestring <<< в новом хуке — сверка показала, что shebang проекта bash и образец rules-write-bypass использует ту же конструкцию, противоречия нет"
    session: ""
  - date: 2026-08-29
    kind: reinforced
    reason: "отказало вызову timeout при прогоне набора тестов — на macOS его нет, вызов вернул бы 127, и код 127 читался бы как прошло без находок; замена на фоновый запуск сработала"
    session: ""
  - date: 2026-08-30
    kind: reinforced
    reason: "регэкспы следа вынесены в Onigurama/jq вместо grep: S, b и [^а-яё] у BSD и GNU grep разные; sed с t в BSD не работает — снят до прогона"
    session: ""
fragile: true

# Blocker-tier
blocker: true
blocker_reminder: "Команда работает только на одной системе. GNU не знает `date -j`, `stat -f`, `tail -r`, `compgen`; GNU `tr` не сворачивает кириллицу ни в какой локали; GNU grep отвергает диапазон `[а-яё]` в C.UTF-8; `file(1)` отсутствует в минимальных образах. Не-ASCII символ вплотную к синтаксису оболочки: внутри класса `[...]` он читается как диапазон БАЙТОВ, рядом с `$var` — как часть имени переменной. Бери готовое из `hooks/portable-lib.sh` (iso_epoch, file_mtime, to_lower, reverse_lines). Проверяй в контейнере: рецепт в docs/development.md."
detection_signals: |
  [
    {
      "name": "fails_on_this_machine",
      "enforcement": "deny",
      "note": "Перекроен 2026-08-28: прежний единый признак bsd_gnu_divergence_in_bash_command группировал лексемы ПО ТЕМЕ («расхождение BSD/GNU»), а отказ — свойство ПОСЛЕДСТВИЯ. В одну корзину попали `timeout` (на этой машине его нет — вызов падает сейчас) и `date -j` (на macOS работает правильно, ломается только при переносе). Одно поле enforcement не может выразить два разных последствия, поэтому корзина осталась на уровне подсказки — и знание с 29 подтверждениями и 5 замеренными нарушениями продолжало только напоминать. Разнесено по последствию: падает здесь → отказ; работает здесь, не переносится → подсказка; запись такого в файл хука → отказ (ниже). Флаги ниже валятся на BSD и законны на GNU, поэтому признак гейтится предикатом os_is: под Linux он молчит сам, а не выключается руками. Замер по корпусу 2342 вызовов: head -n - 3, compgen -G 1, sed -i голый 16. КОНТРПРИМЕР: `sed -i.bak` не ловится и это известно — он корректен на обеих системах; `sed -i ''` тоже, кавычки снимаются раньше сопоставления. Замер 28 августа 2026 по 2342 прошлым вызовам: первая редакция дала 40 отказов, из них 32 ложных. `sed -i ''` — ВЕРНАЯ форма BSD, а снятие кавычек стирало пустую строку, которая её и отличает; форма цикла внутри тела heredoc пишется в bash-файл, где она законна. Оба вида ложного отказа ушли, когда предикат стал выбирать вид команды под своё утверждение: исполнение смотрит на оболочку без тела heredoc, правильность вызова — на сырой текст.",
      "all_of": [
        {
          "tool_matches": [
            "Bash"
          ]
        },
        {
          "os_is": "bsd"
        },
        {
          "any_of": [
            {
              "shell_regex": "(^|[;&|(])[[:space:]]*head[[:space:]]+-n[[:space:]]+-"
            },
            {
              "shell_regex": "(^|[;&|(])[[:space:]]*compgen[[:space:]]+-G"
            },
            {
              "raw_command_regex": "(^|[;&|(])[[:space:]]*sed[[:space:]]+-i[[:space:]]+[^'\\\"[:space:]]"
            }
          ]
        }
      ],
      "remedy": "Форма верна на GNU и падает здесь: BSD `head` не берёт отрицательное число, `compgen` — встроенная команда bash и под zsh отсутствует, `sed -i` без аргумента съедает следующий параметр как суффикс. Замены: `head -n -N` → `sed '$d'` или python3; `compgen -G` → обычный глоб с проверкой `[ -e ]`; `sed -i` → `sed -i ''` (BSD) либо `sed -i.bak` (обе системы)."
    },
    {
      "name": "absent_on_this_machine",
      "enforcement": "deny",
      "note": "Правило о МИРЕ, а не о тексте: исполняемого нет на PATH, значит вызов падает кодом 127 здесь и сейчас. На машине, где инструмент есть, признак молчит сам. Повод: `timeout` — 6 вызовов на корпус в 2342, и один раз код 127 был почти прочитан как «зависания нет» (provenance 2026-08-26). КОНТРПРИМЕР: имя инструмента, взятое из переменной или из строки-аргумента, не ловится — сопоставление идёт по раскавыченной команде.",
      "all_of": [
        {
          "tool_matches": [
            "Bash"
          ]
        },
        {
          "any_of": [
            {
              "command_absent": "timeout"
            },
            {
              "command_absent": "sponge"
            },
            {
              "command_absent": "realpath"
            }
          ]
        }
      ],
      "remedy": "Названного инструмента нет на этой машине — вызов вернёт 127, и код 127 легко прочитать как «прошло без находок». Замены: вместо timeout — фоновый запуск с проверкой живости либо `perl -e 'alarm N; exec @ARGV'`; вместо realpath — `cd … && pwd -P` или python3; вместо sponge — временный файл и mv."
    },
    {
      "name": "zsh_no_word_split_in_for_list",
      "enforcement": "deny",
      "note": "Список for состоит РОВНО из одного простого раскрытия параметра. Под zsh — а Bash-инструмент Claude Code на macOS это zsh — такой цикл проходит ОДИН раз целой строкой; под bash делится по словам. Ошибка молчит: не падает, а даёт неверный ответ. Замер 28 августа 2026 по корпусу в 2342 вызова: форма встретилась 9 раз, из них 6 внутри `bash -c` (там верно) и 3 снаружи — все три оказались настоящими дефектами, один дал 125 ложных «неописанных» файлов вместо 19. Точность 3 из 3 на отказ, поэтому отказ. КОНТРПРИМЕР: `for x in $(cmd)` НЕ ловится и это известно — подстановку команды zsh делит, форма законна; смешанный список с глобом (`*${X}*`) тоже пропускается. Признак читает ТОЛЬКО то, что исполняет оболочка: та же форма в теле heredoc уезжает в bash-файл и там верна — 18 ложных отказов замера пришлись ровно на это.",
      "all_of": [
        {
          "tool_matches": [
            "Bash"
          ]
        },
        {
          "os_is": "bsd"
        },
        {
          "shell_regex": "for[[:space:]]+[A-Za-z_][A-Za-z0-9_]*[[:space:]]+in[[:space:]]+\\$\\{?[A-Za-z_][A-Za-z0-9_]*\\}?[[:space:]]*(;|do|$)"
        },
        {
          "none_of": [
            {
              "command_uses": "bash -c"
            },
            {
              "command_uses": "#!/usr/bin/env bash"
            },
            {
              "command_uses": "#!/bin/bash"
            }
          ]
        }
      ],
      "remedy": "Bash-инструмент на macOS — это zsh, а zsh НЕ делит простое раскрытие параметра по словам: цикл пройдёт один раз всей строкой. Ошибка не падает, а даёт неверный ответ. Замены: обернуть в `bash -c '…'`; либо `for x in ${(z)VAR}` (zsh); либо хранить список в массиве и раскрывать явно; либо `printf '%s\\n' $VAR | while read -r x`."
    },
    {
      "name": "works_here_breaks_elsewhere",
      "note": "Перекроен 2026-08-28: прежний единый признак bsd_gnu_divergence_in_bash_command группировал лексемы ПО ТЕМЕ («расхождение BSD/GNU»), а отказ — свойство ПОСЛЕДСТВИЯ. В одну корзину попали `timeout` (на этой машине его нет — вызов падает сейчас) и `date -j` (на macOS работает правильно, ломается только при переносе). Одно поле enforcement не может выразить два разных последствия, поэтому корзина осталась на уровне подсказки — и знание с 29 подтверждениями и 5 замеренными нарушениями продолжало только напоминать. Разнесено по последствию: падает здесь → отказ; работает здесь, не переносится → подсказка; запись такого в файл хука → отказ (ниже). Здесь остались формы, которые на macOS ВЕРНЫ: date -j, stat -f, tail -r. Отказывать в них нельзя — это правильный способ спросить время и права на этой машине. Уровень подсказки тут и есть верный уровень: беда наступает не при вызове, а при записи такой формы в файл, и на записи стоит отдельный отказ (bsd_gnu_token_written_into_hook_file). КОНТРПРИМЕР: вызов из скрипта, который поедет в контейнер, ничем не отличается от разового — признак этого не видит.",
      "all_of": [
        {
          "tool_matches": [
            "Bash"
          ]
        },
        {
          "any_of": [
            {
              "command_uses": "date -j"
            },
            {
              "command_uses": "stat -f"
            },
            {
              "command_uses": "tail -r"
            }
          ]
        }
      ]
    },
    {
      "name": "cyrillic_case_folding_by_tr",
      "all_of": [
        {
          "tool_matches": [
            "Edit",
            "MultiEdit",
            "Write",
            "Bash"
          ]
        },
        {
          "any_of": [
            {
              "file_path_regex": "(^|/)(hooks|scripts)/.*\\.sh$"
            },
            {
              "tool_input_regex": "(hooks|scripts)/[^ ]*\\.(sh|bash)"
            }
          ]
        },
        {
          "any_of": [
            {
              "tool_input_contains": "[:upper:]"
            },
            {
              "tool_input_regex": "LC_ALL=C[^|;]*tr[ ]+-c"
            },
            {
              "heredoc_body_regex": "LC_ALL=C[^|;]*tr[ ]+-c"
            }
          ]
        }
      ]
    },
    {
      "name": "non_ascii_adjacent_to_shell_syntax",
      "all_of": [
        {
          "tool_matches": [
            "Edit",
            "MultiEdit",
            "Write"
          ]
        },
        {
          "file_path_regex": "(^|/)(hooks|scripts)/.*\\.(sh|bash)$"
        },
        {
          "any_of": [
            {
              "tool_input_regex": "(sed|grep|tr).*\\[[^]]*([^ -~]|\\\\u[0-9a-fA-F]{4})"
            },
            {
              "tool_input_regex": "\\$\\{?[A-Za-z_][A-Za-z0-9_]*\\}?([^ -~]|\\\\u[0-9a-fA-F]{4})"
            },
            {
              "tool_input_regex": "\\[[^]]*\\\\+[xdwsSWD]"
            }
          ]
        }
      ]
    },
    {
      "name": "bsd_gnu_token_written_into_hook_file",
      "enforcement": "deny",
      "note": "Отказ, а не напоминание (2026-08-28, поправка собеседника «нужен стопор, который будет заставлять»). Мишень узкая и измеренная: за шесть сессий 10 команд записали такой признак в файл под hooks|scripts против 35 разовых команд на своей машине. Разовые остаются с тихим напоминанием — запускать stat -f на macOS не ошибка; ошибка — класть его в файл, который поедет на другую систему. Область признака 28 августа 2026 переведена с tool_input_regex на heredoc_target_regex: прежняя горела на ЛЮБОМ пути hooks/…sh в команде, включая путь запускаемого стража, и первый же живой отказ пришёл на запись пробника в песочницу. Предмет проверки — файл, который создаётся, а не то, что упомянуто рядом.",
      "all_of": [
        {
          "tool_matches": [
            "Bash"
          ]
        },
        {
          "heredoc_target_regex": "(hooks|scripts)/[^ ]*\\.(sh|bash|py)"
        },
        {
          "any_of": [
            {
              "heredoc_body_regex": "(^|[|;&(]|[[:space:]])date -j"
            },
            {
              "heredoc_body_regex": "(^|[|;&(]|[[:space:]])stat -f"
            },
            {
              "heredoc_body_regex": "(^|[|;&(]|[[:space:]])tail -r"
            },
            {
              "heredoc_body_regex": "(^|[|;&(]|[[:space:]])compgen -G"
            },
            {
              "heredoc_body_regex": "(^|[|;&(]|[[:space:]])timeout "
            },
            {
              "heredoc_body_regex": "head -n -"
            },
            {
              "heredoc_body_regex": "sed -i[[:space:]]"
            }
          ]
        }
      ]
    },
    {
      "name": "bsd_only_command_written_via_shell",
      "enforcement": "deny",
      "all_of": [
        {
          "tool_matches": [
            "Bash"
          ]
        },
        {
          "heredoc_target_regex": "(hooks|scripts)/[^ ]*\\.(sh|bash)"
        },
        {
          "any_of": [
            {
              "heredoc_body_regex": "(sed|grep|tr).*\\[[^]]*([^ -~]|\\\\u[0-9a-fA-F]{4})"
            },
            {
              "heredoc_body_regex": "\\$\\{?[A-Za-z_][A-Za-z0-9_]*\\}?([^ -~]|\\\\u[0-9a-fA-F]{4})"
            },
            {
              "heredoc_body_regex": "\\[[^]]*\\\\+[xdwsSWD]"
            }
          ]
        }
      ],
      "note": "Область признака 28 августа 2026 переведена с tool_input_regex на heredoc_target_regex: прежняя горела на ЛЮБОМ пути hooks/…sh в команде, включая путь запускаемого стража, и первый же живой отказ пришёл на запись пробника в песочницу. Предмет проверки — файл, который создаётся, а не то, что упомянуто рядом."
    }
  ]
# Escalation (demand зафиксирован 2026-06-21, без инкремента confirmed — двойной учёт)
escalation_mechanism_needed: false   # закрыто 2026-07-29: поднят до blocker-tier с измеренными сигналами
escalation_hint: "2026-06-21 (ClaudSoul, сессия f7715c0f): собеседник прямо требует инженерного решения — «кавычки в zsh постоянно возникающая проблема практически везде, с ней нужно что-то делать. При активации в другом проекте …». Второе+ напоминание о том же правиле = знание не держится на уровне text rule (см. principle-knowledge-in-the-world). Кандидат на blocker-tier / activator: detection_signals на Bash с read -ra / -a / небезопасным quoting → inject напоминания об обёртке bash -c. confirmed_count НЕ инкрементирован: проявление из той же сессии, что уже в source_cases (case-2026-06-20-zsh-nested-quotes, case-2026-06-21-grep-is-ugrep-not-gnu)."
---

## Правило

В коде хуков (`*-lib.sh`, `*.sh`) и в командах, которые скилл просит выполнить, **не полагайся на семантику конкретной оболочки**. Среда исполнения не гарантирована: Bash-инструмент Claude Code на macOS — это zsh (`$SHELL=/bin/zsh`), а sourced-библиотека может быть подключена в bash, zsh или хост-шеле.

Конкретно избегать (или оборачивать в `bash -c '...'`):
- `read -ra` / `read -a` — массивы (в zsh: `bad option: -a`)
- word-splitting unquoted скаляра (`for x in $var`) — в zsh `SH_WORD_SPLIT` выключен по умолчанию
- bash-массивы `${arr[@]}`, `mapfile`, `local -n`
- `[[ ... ]]` с regex-семантикой bash

**Делегируй парсинг в `jq` / `awk` / `sed`** — они одинаковы во всех оболочках.

## Why (два проявления)

1. **2026-04-21** — реализация `detection-signals-lib.sh` (blocker-tier): `for t in $allowed` полагался на bash word-splitting, в zsh не разбивал → тест падал. Мета-ирония: сбой при имплементации защиты от `pattern-inside-out-blindness`.
2. **2026-06-14** — команда поиска корней в процедуре `/compile` v1.1.0: `IFS=':' read -ra _r` → `bad option: -a` в zsh, массив пуст, `find` нашёл 0 файлов. Поймано тестом до записи в скилл (verify-before-acting).

3. **2026-06-21** — фильтрация вывода тестов через `grep -vE` со сложным ERE (литеральные `{`/`}`): дважды `ugrep: invalid repeat/syntax`. Системный `grep` на машине — **ugrep**, не GNU grep; ugrep строг к ERE (малформленный интервал `{` отвергает, GNU трактует как литерал). Вывод тестов терялся в умершем пайпе. Расширяет правило за рамки оболочки — на **идентичность CLI-инструмента**: имя `grep` это тоже бренд, не спецификация реализации. См. `case-2026-06-21-grep-is-ugrep-not-gnu.md`.

Общий корень — `pattern-inside-out-blindness`: фокус на внутренней логике команды, слепота к внешнему контейнеру (в какой оболочке/каким бинарём она исполняется). Имя «Bash tool» / «grep» — бренд, не спецификация.

## How to apply

- Любую команду со встроенными массивами/word-splitting — либо POSIX-переносимо, либо `bash -c '...'`.
- Перед тем как положиться на семантику shell — проверь среду один раз: `echo $SHELL; echo $ZSH_VERSION`.
- Команду для скилла/хука **тестируй до** записи как «готово».
- Парсинг структур — через `jq`/`awk`, не через shell-конструкции.

## Limitations

- Простые POSIX-команды (`grep`, `sed`, `find`, пайпы) с **простыми** паттернами переносимы. НО (уточнено 2026-06-21): сам бинарь `grep` может быть **ugrep** (строгий ERE) — сложный ERE с литеральными `{`/`}` или нестандартными конструкциями падает там, где GNU grep толерантен. Для извлечения сводки используй фиксированные подстроки (`grep -E "стр1|стр2"`) или читай сохранённый файл; литеральные скобки экранируй (`\{`); структуры парси `jq`/`awk`.
- Внутри явного `#!/bin/bash` скрипта, запускаемого как файл (а не source/Bash-инструмент), bash-семантика гарантирована — правило про неопределённую среду, не про любой bash-код.
