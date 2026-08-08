# Модуль: гэп-разбор внешней правки (external-correction-gap)

**Назначение.** Классифицировать принятую внешнюю поправку как пойманный чужими руками собственный промах, а не только как прогресс артефакта: перед «вшил» — разбор «катчабельно ли внутренним знанием» + цепочка «почему не поймал сам» + запись в Predictions.

**Файлы.** `hooks/external-correction-gap.sh` (UserPromptSubmit, advisory), тест `hooks/tests/test_external_correction_gap.sh` (9 проверок), регистрация в `install.sh` (HOOKS_CONFIG → UserPromptSubmit).

**Зависимости.** `throttle-lib.sh` (per-session dedup), `portable-lib.sh` (to_lower для кириллицы), `paths-lib.sh` (STATE_DIR); состояние `intrusiveness-${SID}.json` (AP2: distressed → silent).

**Правила.** Сигнал узкий по решению — только маркеры пересланной рецензии (рецензент/рецензи/вердикт/оценщик/reviewer); «сделай ревью» — просьба к агенту, не ловится намеренно. Один инжект на сессию. Уровень embedded-ness — 2 (activator injection); подъём до blocker-tier — по критериям META (confirmed_count ≥ 5). Происхождение: инцидент 2026-08-08 — 4 из 7 поправок рецензента были катчабельны инжектированным в ту же сессию знанием (pattern-inside-out-blindness), гэп-разбор не случился, поле Predictions заполнено без разбора; error-tracker такое не видит — он считает упавшие команды, а дизайн-промах не оставляет машинного следа.
