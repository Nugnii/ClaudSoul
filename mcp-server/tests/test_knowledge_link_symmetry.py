"""Ссылка кейс → паттерн обязана быть двусторонней.

Повод. Триаж 35 кейсов, не вошедших ни в один паттерн (2026-07-29), искал пропущенные
обобщения и не нашёл ни одного: все 11 предложенных кластеров были отклонены — где-то
участники оказались одним эпизодом, записанным дважды, где-то класс был уже покрыт.
Зато нашлось другое: **23 односторонние ссылки**. Кейс объявляет `confirms:` или
`specializes:` в сторону паттерна, а паттерн его в `source_cases` не перечисляет.

Почему это не косметика. Обход графа знаний идёт от паттерна вниз — «на чём это
основано». Кейс, который виден только со своей стороны, для такого обхода не существует:
паттерн выглядит основанным на трёх случаях, когда их девять. Это ровно `pattern-
measurement-validity` — счётчик, считающий не то, что заявлено.

Почему проверкой. Ссылки проставляются руками при записи знания, в двух разных файлах.
Расхождение накопилось за три месяца молча — ни один прогон его не видел.
"""

import sys
from pathlib import Path

import pytest

LESSONS = Path.home() / ".claude" / "global-lessons"
# Seed из репозитория — корпус, который есть ВЕЗДЕ, включая CI. Рабочая база личная и
# наружу не едет (`scripts/publish-public.sh` её вычищает), а на раннере её не существует
# никогда: шага установки ClaudSoul в `.github/workflows/tests.yml` нет.
SEED = Path(__file__).resolve().parents[2] / "knowledge"

# Инвариант считается ОДНИМ источником — `hooks/lib/link_symmetry.py` (D312). Прежде
# здесь жила своя копия, спрашивавшая «имя кейса not in текст родителя»: имя лежит в
# файле и помимо `source_cases` (в `provenance_log.trigger_case`, в `related`, в прозе),
# и подстрока давала 1 нарушение там, где разбор поля даёт 18. Вторая копия того же
# кода жила в `scripts/backlog-recheck.sh` — две копии ошибались согласованно, то есть
# их независимость была мнимой. Независимость держится отрицательным контролем ниже,
# а не повторением кода.
_LIB = Path(__file__).resolve().parents[2] / "hooks" / "lib"
if str(_LIB) not in sys.path:
    sys.path.insert(0, str(_LIB))

link_symmetry = pytest.importorskip(
    "link_symmetry", reason="нет hooks/lib/link_symmetry.py — инвариант считать нечем"
)


def _parents() -> dict[str, str]:
    if not LESSONS.is_dir():
        return {}
    out = {}
    for p in list(LESSONS.glob("pattern-*.md")) + list(LESSONS.glob("principle-*.md")):
        out[p.name] = p.read_text(errors="replace")
    return out


@pytest.mark.skipif(not LESSONS.is_dir(), reason="рабочая база знаний недоступна")
def test_case_to_pattern_links_are_bidirectional():
    """Если кейс ссылается на паттерн, паттерн обязан перечислять кейс."""
    bad, unread = link_symmetry.asymmetric(LESSONS)
    assert not bad, "односторонние ссылки (кейс видит паттерн, паттерн кейса — нет):\n" + "\n".join(
        f"  {c} -{k}-> {t}" for c, k, t in bad
    )
    # «Не разобрали» — не «чисто»: родитель, чей source_cases прочитать не удалось,
    # молча уменьшал бы число нарушений (род B реестра дефектов).
    assert not unread, "родители, чей source_cases не разобрать:\n" + "\n".join(f"  {u}" for u in unread)


def test_detector_fires_on_a_planted_violation(tmp_path):
    """Отрицательный контроль БЕЗ личной базы: детектор обязан найти подложенное нарушение.

    Повод (D313). Обе проверки этого файла стояли под одним `skipif` по наличию
    `~/.claude/global-lessons`, а в `.github/workflows/tests.yml` шага установки ClaudSoul
    нет — значит на раннере базы не существует НИКОГДА. Замер 5 сентября 2026 эмуляцией
    условий CI (пустой HOME): «2 skipped in 0.00s», код возврата 0. Прибор поставлен
    закрытием D12 как поддержание инварианта и в CI не смотрел ни разу за всё время жизни;
    «зелёный CI» об инварианте не говорил ничего. Хуже: `skipif` гасил и саму проверку, и её
    отрицательный контроль — подпорка исчезала ровно тогда, когда исчезало подпираемое.

    Здесь предмет создаётся, а не ищется, поэтому проверка исполняется всюду одинаково.
    """
    (tmp_path / "pattern-x.md").write_text(
        "---\nsource_cases: []\n---\nпаттерн без обратной ссылки\n", encoding="utf-8")
    (tmp_path / "case-y.md").write_text(
        "---\nedges:\n  - specializes: pattern-x.md\n---\nкейс ссылается вверх\n", encoding="utf-8")
    bad, unread = link_symmetry.asymmetric(tmp_path)
    assert bad, "детектор не нашёл подложенную одностороннюю ссылку — считать инвариант нечем"
    assert not unread, f"родитель не разобран: {unread}"


def test_seed_corpus_is_present_and_parsed():
    """Seed из репозитория разобран, и «предмета нет» отличимо от «нарушений нет».

    Корпус, который в CI ЕСТЬ. Нулевое число нарушений на нём засчитывается только вместе
    с непустым числом просмотренных родителей — иначе зелёный вердикт неотличим от пустого
    универсума (тот же класс, что D302).
    """
    assert SEED.is_dir(), f"seed-корпус отсутствует: {SEED}"
    parents = list(SEED.glob("pattern-*.md")) + list(SEED.glob("principle-*.md"))
    assert parents, "в seed нет ни одного родителя — проверять нечего, и это отказ, а не успех"
    bad, unread = link_symmetry.asymmetric(SEED)
    assert not unread, f"родители seed, чей source_cases не разобрать: {unread}"
    assert not bad, "односторонние ссылки в seed:\n" + "\n".join(f"  {c} -{k}-> {t}" for c, k, t in bad)


@pytest.mark.skipif(not LESSONS.is_dir(), reason="рабочая база знаний недоступна")
def test_detector_can_fire():
    """Отрицательный контроль: проверка обязана уметь найти нарушение.

    Без него зелёный результат выше означал бы либо «нарушений нет», либо «regexp
    ничего не матчит» — а это разные вещи, и различить их снаружи нельзя.
    """
    parents = _parents()
    assert parents, "паттернов не найдено — проверке не с чем работать"

    # Ребро читается разбором поля, а не строкой файла (D319), поэтому образец —
    # frontmatter целиком: строка `- confirms: …` в прозе ребром не является.
    sample = "---\nedges:\n  - confirms: pattern-nonexistent-probe.md\n---\n"
    assert link_symmetry.parent_edges(sample), "форма ребра не распознаётся"

    # мишень существует, но кейс в ней не упомянут → нарушение должно детектироваться
    target = next(iter(parents))
    assert link_symmetry.listed(parents[target], "case-probe-not-in-base.md") is False, (
        "заведомое нарушение не распознано — проверка ничего не измеряет"
    )

    # ТОТ ЖЕ КОНТРАКТ У РЁБЕР (D333, 9 сентября 2026). `parent_edges` возвращал пустой
    # список и при отказе разбора, и при «рёбер нет» — и писатель встречных ссылок
    # (единственный механизм, который их создаёт) молчал при битой шапке, выдавая молчание
    # за «дописывать нечего». Инвариант при этом зелен: он проверяет записанное и не
    # спрашивает, почему записей нет. Обе стороны названы явно.
    assert link_symmetry.parent_edges("---\nedges:\n  - specializes: [\n---\nтело\n") is None, (
        "битая шапка отдаёт не None — «не разобрать» неотличимо от «рёбер нет»"
    )
    assert link_symmetry.parent_edges("---\nconfidence: 1\n---\nтело\n") == [], (
        "целая шапка без рёбер обязана давать пустой список, а не None"
    )

    # и обратная сторона контроля: разбор ОТЛИЧАЕТ «нет в списке» от «не смог прочитать»
    assert link_symmetry.listed("тело без frontmatter", "case-any.md") is None, (
        "отказ разбора неотличим от отсутствия — счёт нарушений занижался бы молча"
    )


def test_edge_target_without_md_is_recognized(tmp_path):
    """Цель ребра без `.md` — законная форма, и инвариант обязан её видеть (D319).

    Договор формата (`knowledge/META.md:161-165`) говорит «имя кейса»/«имя родителя» и
    расширения не требует. До 6 сентября 2026 `parent_edges` читал поле `edges` шаблоном
    строки с обязательным `\\S+\\.md`, тогда как `source_cases` РОДИТЕЛЯ разбирался YAML-ом:
    один модуль читал две стороны одной связи двумя разными способами. Замер 6 сентября
    2026 по рабочей базе: рёбер родительства 222, шаблон видел 190 — невидимых 32 (14%).
    «Не распознал ребро» неотличимо от «нарушений нет».

    Здесь же — отрицательный контроль на противоположную ошибку: разбор, признающий
    ребром что угодно, даёт ложные нарушения. Поэтому рядом с формой без `.md` лежат
    четыре формы, которые считаться НЕ должны.
    """
    (tmp_path / "pattern-x.md").write_text(
        "---\nsource_cases: []\n---\nпаттерн без обратной ссылки\n", encoding="utf-8")
    (tmp_path / "case-y.md").write_text(
        "---\nedges:\n  - specializes: pattern-x\n---\nкейс ссылается вверх без .md\n",
        encoding="utf-8")
    bad, unread = link_symmetry.asymmetric(tmp_path)
    assert not unread, f"родитель не разобран: {unread}"
    assert bad == [("case-y.md", "specializes", "pattern-x.md")], (
        f"ребро без .md не увидено либо названо не так: {bad}")

    # Формы цели, которые обязаны распознаваться: голое имя, имя с расширением, путь.
    assert link_symmetry.parent_edges(
        "---\nedges:\n"
        "  - specializes: pattern-a\n"
        "  - confirms: principle-b.md\n"
        "  - extends: ../global-lessons/pattern-c\n"
        "  - generalizes: dir/principle-d.md\n"
        "---\n"
    ) == [
        ("specializes", "pattern-a.md"),
        ("confirms", "principle-b.md"),
        ("extends", "pattern-c.md"),
        ("generalizes", "principle-d.md"),
    ], "законная форма цели не распознана"

    # Формы, которые распознаваться НЕ должны — иначе «ребром» станет любая строка.
    assert link_symmetry.parent_edges(
        "---\nedges:\n"
        "  - caused_by: pattern-not-parenthood\n"      # вид не объявляет родительства
        "  - similar_to: principle-not-parenthood\n"
        "  - specializes: case-not-a-parent\n"         # цель не паттерн и не принцип
        "  - specializes: entity-not-a-parent.md\n"
        "---\n"
        "\n- specializes: pattern-in-prose\n"          # вне frontmatter не судим
    ) == [], "ребром признано то, что им не является"
