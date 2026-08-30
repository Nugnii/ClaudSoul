# Модуль: со-эволюционное знание (мост L2↔L7)

**Назначение.** Мерить долю и глубину знаний, рождённых в совместном мышлении, против solo.

**Файлы.** `hooks/co-cognition-lib.sh`, секция «Co-cognition health (L2↔L7)» в `metrics-collector.sh`.

**Зависимости.** Поля `origin` / `trigger_for_co_cognition` в frontmatter знаний (пишут /learn и /retro); тренд доли считает /knowledge-audit по `.audit-history.json`.

**Правила.** Знаменатель — только знаниевое ядро (case/pattern/principle), второй контур не входит. Атрибуция полей не зависит от их порядка во frontmatter. Кавычки в значениях триггера нормализуются. Измеренный ноль ≠ «не измеряли». Тест: test_co_cognition_lib.
