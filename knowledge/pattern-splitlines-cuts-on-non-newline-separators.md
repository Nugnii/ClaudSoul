---
name: pattern-splitlines-cuts-on-non-newline-separators
description: "Python str.splitlines() режет строку не только по \\n и \\r, но и по \\x0b \\x0c \\x1c \\x1d \\x1e \\x85 U+2028 U+2029 — разделитель записи протокола или текст из JSON молча распадается, и счёт отвечает «ноль», а не ошибкой"
type: pattern
outcome: error
confidence: 2
impact: 3
intensity: 3
confirmed_count: 1
contradicted_count: 0
last_confirmed: 2026-10-28
source_cases: [case-2026-10-20-snapshot-rewrite-loses-what-append-gave-free.md, case-2026-10-27-splitlines-cuts-on-record-separator.md]
source_session: ""
status: active

domain: [python, parsing, tooling]
situation: "разбор многострочного текста, в котором бывают управляющие символы: журнал git с %x1e, JSON-строки с U+2028, протоколы с разделителями записи"
trigger: "str.splitlines() над таким текстом"
stakes: "разделитель записи исчезает молча — счётчик отвечает «ноль» или строка распадается на две, без исключения"
actors: [agent, script]
environment: "Python 3"
circumstances: "ответ «ноль» законен по смыслу и потому не настораживает"
purpose: "разобрать текст по строкам или записям"
method: "split(\"\\n\") (и rstrip(\"\\r\") при нужде) вместо splitlines()"
tags: [splitlines, unicode-line-boundaries, record-separator, silent-zero]
volatile_anchors: []
self_altering: ""
outcome_signals: []

need: avoid_regression
urgency: when_relevant
availability: common_knowledge

related: [pattern-non-execution-read-as-verdict]
edges: []

modification_history: []
provenance_log: []
fragile: false

origin: solo
preceded_artifact: "no"
promotion_tier: 2
scope: universal
origin_domain: python
---

Разбор текста, где бывают управляющие символы (разделители записи `\x1c`–`\x1e`, `\x85`, `\x0b`, `\x0c`) или строки из
JSON (U+2028, U+2029 не экранируются), — `split("\n")`, а не `str.splitlines()`. Признак — `splitlines()` рядом с
`\x1e`/`\x1f`/`%x1e` либо над текстом, пришедшим из JSON.

**Why:** два случая одного устройства. ClaudSoul, журнал открытий (20 октября 2026): `splitlines` резал строку по
U+2028 — одно из шести свойств, которые прежняя дозапись держала сама. ClaudSoul, D1146 (27 октября 2026):
`git log --format="\x1e%H %s"` разбирался `splitlines()` — разделитель записи исчезал, и счётчик молча отвечал «не
трогали ни разу за 300 коммитов». Оба раза — тихий ноль, а не исключение.

**How to apply:** в разборе журналов, протоколов и JSON — `split("\n")`; проверка — прогон на живом выводе с
ожидаемым ненулевым счётом. Род в дереве ClaudSoul на 28 октября 2026: вызовов `splitlines()` 60, файлов с ними и
JSON либо разделителями записи 23 — поштучно не разобраны, это кандидаты, а не носители.

**Limitations:** для обычного текста без управляющих символов `splitlines()` безопасен и удобнее (понимает `\r\n` без
хвостов).
