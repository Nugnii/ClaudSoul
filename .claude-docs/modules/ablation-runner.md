# Модуль: ablation-runner (запускалка теневых троек)

**Назначение.** Исполняемая часть prereg-протокола `docs/ablation-protocol.md`
(D64; протокол 1.4): журнал задач с механическим правилом входа,
детерминированный сэмплер с публичной случайностью, заморозка task package,
песочницы ТРЁХ плеч (full / core / vanilla) и анализ трёх контрастов. Всё состояние — приватно в `ABLATION_DIR` (default `~/.claude/ablation`),
в публичный снимок уходит только воронка числами.

**Файлы.**
| Файл | Роль | Протокол |
|---|---|---|
| `scripts/ablation/journal.sh` | append-only журнал: register / classify (однократно) / show / funnel | §3–§4 |
| `scripts/ablation/sampler.py` | HMAC-SHA256(salt, domain-sep msg) + NIST beacon; commitment-сверка; verify | §5 |
| `scripts/ablation/snapshot.sh` | заморозка пакета: repo.tar + knowledge.tar + runtime.tar + core-runtime.tar + manifest c hash | §6 |
| `scripts/ablation/env-diff.sh` | манифест treatment: full/core/vanilla; для core проверка двусторонняя (есть знания — нет policy); расхождение = infrastructure_failure | §6 |
| `scripts/ablation/core/inject.py` | инжектор плеча Core: top-k по лексической близости, без confidence/blocker/аналогий/decay. Код обвязки, не ClaudSoul — с policy не замораживается | §2, §6, §12 |
| `scripts/ablation/core/settings.json` | регистрация инжектора и больше ничего — весь treatment плеча Core | §6 |
| `scripts/ablation/dry-run-activator.sh` | предзадачный признак would_surface (однократно) | §7 |
| `scripts/ablation/shadow-run.sh` | песочница плеча (HOME+worktree из снимка), таймаут 90м, `--smoke` | §2, §9, §11 |
| `scripts/ablation/pair-analyze.py` | exact McNemar + Agresti–Min CI + правило трёх исходов; Δ_all, Δ_structure (гейт иерархии), Δ_memory, Δ_surface | §11 |
| `scripts/ablation/checker.sh` | чекер вне песочниц: hash до запусков, сверка перед каждым прогоном; исходы success/blocked/objective_failure/timeout | §9 |
| `scripts/ablation/pair.sh` | завершение тройки (все три плеча обязательны; бинаризация → pairs.jsonl) и аннулирование целиком с лимитом 2 повторов | §9 |
| `scripts/ablation/parse-transcript.py` | метрики плеча: токены/время/ходы + all/failed commands из транскриптов песочницы | §8.1 |
| `scripts/ablation/freeze-policy.sh` | старт фазы: annotated тег + read-only frozen runtime с hash-манифестом + маркер active-phase.json (решение владельца) | §6 |
| `scripts/ablation/phase.sh` | состояние фазы: status / close (событие phase_closed, маркер снят) — помнить не нужно никому | §6 |
| `hooks/ablation-phase-guard.sh` | при активной фазе: сигнал раз в сессию + СТОП на деплой установленной policy; без фазы молчит | §6 |

**Зависимости.** jq, python3 (stdlib), git, tar; соль — `scripts/publish/ablation-salt.txt`
(вне публичного снимка), commitment зашит в sampler.py и сверяется на каждом решении.

**Правила.** Журнал append-only; классификация и dry-run — по одному разу на
задачу; снимок и прогон плеча неизменяемы (повтор тройки — только целиком, все
три плеча); тройка с недостающим плечом не завершается;
δ=0.20 и CI=95% — константы кода, не флаги (§11: параметры заморожены).

**Тесты.** `hooks/tests/test_ablation_{journal,sampler,analyze,runner}.sh` — 53
проверки, всё оффлайн (beacon — фикстурой).

**Границы (осознанные).** Полная RSA-проверка certificate beacon — внешний шаг
(связка outputValue == SHA-512(signatureValue) проверяется `sampler.py
verify-pulse`); enforcement потолка токенов на лету — по первой живой паре при
необходимости (таймаут 90 мин действует); строка в `scripts/measurements.tsv` —
только с первой завершённой парой. Повтор после annul: события текущей попытки
скоупятся «после последнего pair_annulled», журнал остаётся append-only.
