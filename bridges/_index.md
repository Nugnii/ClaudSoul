# Inter-Layer Bridges — Complete Index

> 15 inter-layer мостов L2-L7 + 1 within-layer (L2↔L2 cross-contour). L1 (Persistence) = global workspace (шина данных).

## Теоретическое основание

**Global Workspace Theory (Baars, 1988):** В мозге специализированные модули работают параллельно. Когда информация попадает в "глобальное рабочее пространство", она бродкастится ВСЕМ модулям. Мост между любыми двумя модулями возможен, если есть общее пространство broadcast.

В ClaudSoul global workspace = L1 (файлы, SESSION.md, registry). Следствие: все мосты между L2-L7 **теоретически возможны**. Вопрос — не "можно ли?", а "что даёт?".

## Условия существования моста

| # | Условие | Формулировка |
|---|---------|-------------|
| 1 | **Dataflow** | Слой A производит данные, потребляемые слоем B |
| 2 | **Feedback cycle** | Потребление B-ём данных A меняет поведение A |
| 3 | **Emergence** | На пересечении возникает навык, отсутствующий в каждом слое |
| 4 | **Operationalizability** | Мост описывается как конкретный процесс |

Все 15 пар L2-L7 удовлетворяют всем 4 условиям.

## Полная карта (16 мостов: 15 inter-layer L2-L7 + 1 within-layer)

### L2 (Knowledge) — 4 inter-layer моста + 1 within-layer

| Мост | С кем | Навык | Статус |
|------|-------|-------|--------|
| [L2↔L3](L2-L3-knowledge-from-communication.md) | Communication | Обучение на диалоге | ✅ Реализован |
| [L2↔L4](L2-L4-anticipatory-learning.md) | Trajectory | **Антиципаторное обучение** — учить то, что понадобится | Спроектирован |
| [L2↔L5](L2-L5-metacognition-of-knowledge.md) | Meta-Cognition | Самоочищение базы знаний | ✅ Реализован |
| [L2↔L6](L2-L6-proactive-intensity.md) | Prediction | Предсказание ошибки до действия | Спроектирован |
| [L2↔L7](L2-L7-co-evolutionary-knowledge.md) | Co-Cognition | **Со-эволюционное знание** | Реализован (v1.20.0) |
| [L2↔L2](L2-L2-cross-contour.md) | L2 (entity контур) | **Кросс-контурная аналогия** — между знаниевым и entity контурами L2 | ✅ Реализован v1.6 |

### L3 (Communication) — 4 моста

| Мост | С кем | Навык | Статус |
|------|-------|-------|--------|
| [L3↔L4](L3-L4-trajectory-from-communication.md) | Trajectory | Понимание направления мысли | ⚡ Неявный |
| [L3↔L5](L3-L5-communication-quality.md) | Meta-Cognition | **Мониторинг качества коммуникации** | Спроектирован |
| [L3↔L6](L3-L6-communicative-prediction.md) | Prediction | Выбор формулировки + каскадная верификация + **4D gate** (confidence × value × cost × state) | Формализован v1.3 |
| [L3↔L7](L3-L7-shared-language.md) | Co-Cognition | **Совместный язык** | Реализован (v1.21.0) |

### L4 (Trajectory) — 3 моста

| Мост | С кем | Навык | Статус |
|------|-------|-------|--------|
| [L4↔L5](L4-L5-prediction-calibration.md) | Meta-Cognition | **Калибровка предсказаний** | Реализован (v1.19.0) |
| [L4↔L6](L4-L6-prediction-from-trajectory.md) | Prediction | Готовность к следующему запросу | ⚡ Неявный |
| [L4↔L7](L4-L7-trajectory-steering.md) | Co-Cognition | **Управление траекторией** | Спроектирован |

### L5 (Meta-Cognition) — 2 моста

| Мост | С кем | Навык | Статус |
|------|-------|-------|--------|
| [L5↔L6](L5-L6-adaptive-prediction.md) | Prediction | **Адаптивное предсказание** | Спроектирован |
| [L5↔L7](L5-L7-meta-co-cognition.md) | Co-Cognition | **Мета-со-когниция** | Спроектирован |

### L6 (Prediction) — 1 мост

| Мост | С кем | Навык | Статус |
|------|-------|-------|--------|
| [L6↔L7](L6-L7-co-cognition-through-prediction.md) | Co-Cognition | Генеративное мышление | ⚡ Неявный |

### L1 (Persistence) — особый случай

L1 = **global workspace** (broadcast medium). Не когнитивный слой, а инфраструктура. Все слои читают из L1 и пишут в L1. Это не мосты, а **шина данных**. Активная роль L1 реализуется ЧЕРЕЗ мосты других слоёв (registry → L5, SESSION.md → L4, git → L2).

## Статистика

- Всего мостов: **16** (15 inter-layer L2-L7 + 1 within-layer L2↔L2)
- Реализовано: **6** (L2↔L3, L2↔L5, L2↔L2, L4↔L5, L2↔L7, L3↔L7)
- Формализован: **1** (L3↔L6)
- Неявно работают: **3** (L3↔L4, L4↔L6, L6↔L7)
- Спроектировано: **6** (L2↔L4, L2↔L6, L3↔L5, L4↔L7, L5↔L6, L5↔L7)
