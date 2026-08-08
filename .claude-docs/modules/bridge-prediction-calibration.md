# Модуль: калибровка предсказаний (мост L4↔L5)

**Назначение.** Считать точность предсказаний из SESSION.md по типам и возвращать рекомендации калибровки confidence в канал метрик.

**Файлы.** `hooks/prediction-calibration-lib.sh`, секция «Prediction calibration (L4↔L5)» в `metrics-collector.sh` → `state/metrics.md`.

**Зависимости.** Таблицы `### Predictions` в SESSION.md проектов (корни — `PRED_SCAN_ROOTS`); канал `- ⚠️`-строк читает knowledge-activator.

**Правила.** Формула одна: accuracy = (exact + 0.5×adjacent) / решённых; pending не считается. Тип — в номере записи (`P3:need`, topic|reaction|need|action); старые строки — untyped, история не переписывается. Гейты выборки: секций < 5 или тип с n < 5 — вердикт не выносится; «не измеряли» отличимо от нулей. Пороги правила: < 40% — снижать confidence типа, > 80% — повышать. Тест: test_metrics_predictions (файлы с пробелами в путях — регресс).
