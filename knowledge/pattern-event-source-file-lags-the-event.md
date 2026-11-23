---
name: Файл источника события отстаёт от события
description: Страж на событии чужого процесса судит по файлу, который этот процесс дописывает уже ПОСЛЕ события; фикстуры и корпус готовых файлов гонку не видят, починка по одному пути сдачи оставляет другие
type: pattern
outcome: error
confidence: 2
impact: 4
intensity: 3
confirmed_count: 1
contradicted_count: 0
last_confirmed: 2026-11-05
source_cases:
  - case-2026-10-28-ranges-from-copy-text-from-live-file.md
  - case-2026-10-27-probe-green-by-winning-a-race-with-background.md
  - case-2026-09-18-transcript-lags-behind-the-event.md
  - case-2026-10-03-race-fix-covered-one-delivery-path.md
  - 2026-10-19-biznes-sovetnik-komunikat.md
  - 2026-10-19-biznes-sovetnik-export-mid-write.md
source_session: ""
status: active
scope: universal
promotion_tier: 2

domain: [hooks, verification, tooling]
situation: "механизм на событии харнесса (SubagentStop, Stop, PreToolUse) решает по файлу, который пишет процесс-источник события"
trigger: "решение страж принимает по последнему блоку, строке или результату в файле, а событие приходит раньше, чем процесс её дописал"
stakes: "ложная тревога на каждом успешном прогоне или молча пропущенный настоящий отказ"
actors: [agent]
environment: "хуки Claude Code: расшифровка агента, расшифровка сессии, журналы, которые дописывает тот же процесс"
circumstances: "фикстуры и корпус живых файлов зелёные — там файл уже дописан; гонку показывает только мир"
purpose: "судить исход по тому, что произошло, а не по тому, что успело записаться"
method: "перечислить ВСЕ пути, которыми процесс сдаёт результат; для каждого — источник без гонки: поле харнесса либо ожидание записи с id именно этого шага, с пределом и названным исходом по пределу"
tags: [race, end-to-end, fixture-vs-world, delivery-path]

need: avoid_regression
urgency: when_relevant
availability: unique

related: [pattern-fixture-form-not-taken-from-the-world, pattern-subject-of-measurement-mismatch]
edges:
  - similar_to: pattern-fixture-form-not-taken-from-the-world
origin: solo
preceded_artifact: "no"
provenance_log:
  - date: 2026-10-19
    kind: reinforced
    reason: "19.10.2026 Biznes-sovetnik: сводный текст ustawy o cudzoziemcach от Сейма (на 07.04.2026) показывал как будущие нормы, которые komunikat MSWiA M.P. 2026 poz. 370 ввёл с 27.04.2026 (art. 105–106l, 108, 218a–219i, 222a–222g). Исходящий документ процитировал отменённую редакцию art. 219 ust. 2; поймала линза-сверщик ревью. Носители поправлены, пункт долга с проверкой заведён"
    trigger_case: 2026-10-19-biznes-sovetnik-komunikat
    session: ""
  - date: 2026-10-19
    kind: reinforced
    reason: "19.10.2026 Biznes-sovetnik, второй случай за день: HTML-экспорт Telegram чата клиента разобран, пока ещё дописывался (118 КБ/173 сообщения против итоговых 674 КБ/1 221). Карточка, разбор и черновик плана стояли на неполной переписке; поправлено по архивной копии, правило записано в память проекта arhiv-ukladyvayu-sam"
    trigger_case: 2026-10-19-biznes-sovetnik-export-mid-write
    session: ""
  - date: 2026-10-27
    kind: reinforced
    reason: "27 октября 2026: канарейка на Stop судила расшифровку без итога хода — реплей среза до итога даёт ту же тревогу, с итогом — тишина (D1159)"
    session: ""
  - date: 2026-10-28
    kind: reinforced
    reason: "проба читала mtime кэша до конца фоновой пересборки и зеленела, выигрывая гонку (D1114)"
    trigger_case: case-2026-10-27-probe-green-by-winning-a-race-with-background.md
    session: ""
  - date: 2026-10-30
    kind: reinforced
    reason: "D1169 r2: номера строк из стабильной копии, строки из живого бэклога — сдвиг писателем между чтениями"
    trigger_case: case-2026-10-28-ranges-from-copy-text-from-live-file
    session: ""
  - date: 2026-11-05
    kind: reinforced
    reason: "D1210, 5 ноября 2026: пять стражей Stop судили файл расшифровки, не догнавший итог; проба probe_D1210 — итог только в поле входа выпадал из суда у всех пяти"
    session: ""
instrument_verdict: candidate   # PreToolUse Write|Edit хука hooks/*.sh, чей текст читает transcript_path без last_assistant_message и transcript_stop_bound; пути закрыты поимённо (D1159, D1250); точность не мерена
instrument_assessed: 2026-11-10
---

Файл, который пишет процесс-источник события, на момент события может ОТСТАВАТЬ. Страж,
решающий по такому файлу, обязан знать, ЧЕМ процесс сдаёт результат, и для каждого пути сдачи
брать ответ из источника без гонки.

**Why:** два случая в одном стороже. 18 сентября 2026 (D450) агент ответил текстом, а страж
SubagentStop прочитал последним блоком вызов — строка ответа легла в файл после события;
починка взяла поле харнесса `last_assistant_message`. 3 октября 2026 (D510) агент сдал отчёт
ВЫЗОВОМ `SubagentHandback`: поле пусто (последний блок — вызов), а строка результата сдачи
легла через 0,23 с после события — второй путь сдачи остался в той же гонке. Оба раза фикстуры
и корпус живых файлов были зелёными: там файл уже дописан.

**How to apply:**
1. Перечень путей сдачи результата (текст, структурированный ответ, сдача отчёта, …) — до починки.
2. Для каждого — источник без гонки: поле от харнесса, если оно описывает этот путь; иначе
   ожидание записи с id именно этого шага, с пределом и исходом по пределу, названным вслух.
3. В тесте гонку разыгрывает подменённый через PATH `sleep`, дописывающий запись в момент
   ожидания: без таймингов, и страж, не ждущий, на нём краснеет.
4. После переноса — сквозной прогон в мире: фикстура гонку не покажет.

**Limitations:** ожидание — цена на каждом событии своего пути (здесь до 2 с, обычно 0,1 с).
Где харнесс отдаёт поле для пути, поле лучше ожидания.
