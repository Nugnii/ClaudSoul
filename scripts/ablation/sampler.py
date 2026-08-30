#!/usr/bin/env python3
"""sampler.py — детерминированный сэмплер ablation-замера (протокол §5, D64).

    r = HMAC-SHA256(key = salt_bytes,
                    msg = b"claudsoul-ablation-v1\\0" + task_id + b"\\0" + beacon_output_bytes)
    взять в тень  <=>  int(r) % 4 == 0          # p = 0.25, 4 делит 2^256

Соль: файл ABLATION_SALT (default scripts/publish/ablation-salt.txt рядом с
репозиторием), байты БЕЗ завершающего \\n; commitment sha256(salt) обязан
совпадать с протоколом (§5) — проверяется на каждом decide.

Beacon: первый валидный выпуск NIST Randomness Beacon 2.0 с timeStamp позже
заморозки предзадачного снимка, statusCode == 0. Полный pulse JSON сохраняется
в журнал-каталог для последующей криптографической проверки подписи (verify
подписи/certificate — предпосылка §15, до неё пульс хранится целиком).
Нет валидного pulse — задача остаётся pending, ручная случайность запрещена.

Гварды дисциплины: задача обязана быть классифицирована eligible ДО решения;
повторное решение по той же задаче запрещено (append-only журнал).
"""
import argparse
import hashlib
import hmac
import json
import os
import sys
import urllib.request
from datetime import datetime, timezone
from pathlib import Path

PROTOCOL_COMMITMENT = "70c5a69d2dd1d33bb91017013bfc56458cc8a2c1228ce050104736f30921ea88"
DOMAIN = b"claudsoul-ablation-v1\x00"
BEACON_URL = "https://beacon.nist.gov/beacon/2.0/pulse/time/next/{ms}"


def ablation_dir() -> Path:
    d = Path(os.environ.get("ABLATION_DIR", Path.home() / ".claude" / "ablation"))
    d.mkdir(parents=True, exist_ok=True)
    return d


def salt_bytes() -> bytes:
    default = Path(__file__).resolve().parent.parent / "publish" / "ablation-salt.txt"
    path = Path(os.environ.get("ABLATION_SALT", default))
    if not path.is_file():
        sys.exit(f"sampler: соль не найдена: {path}")
    return path.read_bytes().rstrip(b"\n")


def check_commitment(salt: bytes) -> str:
    digest = hashlib.sha256(salt).hexdigest()
    expected = os.environ.get("ABLATION_COMMITMENT", PROTOCOL_COMMITMENT)
    if digest != expected:
        sys.exit(
            "sampler: sha256(salt) не совпадает с commitment протокола — "
            f"{digest} != {expected}; решение не вычисляется"
        )
    return digest


def parse_ts(value: str) -> datetime:
    v = value.replace("Z", "+00:00")
    dt = datetime.fromisoformat(v)
    if dt.tzinfo is None:
        dt = dt.replace(tzinfo=timezone.utc)
    return dt


def load_pulse(args) -> dict:
    if args.beacon_file:
        data = json.loads(Path(args.beacon_file).read_text())
    else:
        ms = int(parse_ts(args.snapshot_ts).timestamp() * 1000)
        with urllib.request.urlopen(BEACON_URL.format(ms=ms), timeout=30) as r:
            data = json.load(r)
    pulse = data.get("pulse", data)
    status = pulse.get("statusCode", pulse.get("status"))
    if status not in (0, "0"):
        sys.exit(f"sampler: pulse statusCode={status} != 0 — задача pending")
    if parse_ts(pulse["timeStamp"]) <= parse_ts(args.snapshot_ts):
        sys.exit("sampler: pulse не позже заморозки снимка — задача pending")
    return pulse


def journal_events(journal: Path):
    if not journal.is_file():
        return []
    return [json.loads(line) for line in journal.read_text().splitlines() if line.strip()]


def cmd_decide(args) -> None:
    salt = salt_bytes()
    check_commitment(salt)

    journal = ablation_dir() / "journal.jsonl"
    events = journal_events(journal)
    classes = [e for e in events if e.get("e") == "classify" and e.get("id") == args.task_id]
    if not classes or classes[0].get("class") != "eligible":
        sys.exit(f"sampler: {args.task_id} не классифицирована eligible — решение не вычисляется")
    if any(e.get("e") == "sampler" and e.get("id") == args.task_id for e in events):
        sys.exit(f"sampler: решение по {args.task_id} уже есть — повтор запрещён")

    pulse = load_pulse(args)
    output_bytes = bytes.fromhex(pulse["outputValue"])
    msg = DOMAIN + args.task_id.encode() + b"\x00" + output_bytes
    r = hmac.new(salt, msg, hashlib.sha256).digest()
    selected = int.from_bytes(r, "big") % 4 == 0

    (ablation_dir() / f"beacon-{args.task_id}.json").write_text(json.dumps(pulse, indent=1))
    now = datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
    with journal.open("a") as f:
        compact = {"ensure_ascii": False, "separators": (",", ":")}
        f.write(json.dumps({
            "e": "sampler", "id": args.task_id, "ts": now, "selected": selected,
            "r_mod4": int.from_bytes(r, "big") % 4,
            "beacon_time": pulse["timeStamp"], "beacon_prefix": pulse["outputValue"][:16],
            "snapshot_ts": args.snapshot_ts,
        }, **compact) + "\n")
        if selected:
            f.write(json.dumps({"e": "queue", "id": args.task_id, "ts": now}, **compact) + "\n")

    print(json.dumps({"task_id": args.task_id, "selected": selected}))


def cmd_verify(args) -> None:
    """Пост-хок аудит: пересчитать каждое решение из журнала и сохранённых pulse."""
    salt = salt_bytes()
    check_commitment(salt)
    journal = ablation_dir() / "journal.jsonl"
    bad = 0
    for e in journal_events(journal):
        if e.get("e") != "sampler":
            continue
        pulse = json.loads((ablation_dir() / f"beacon-{e['id']}.json").read_text())
        msg = DOMAIN + e["id"].encode() + b"\x00" + bytes.fromhex(pulse["outputValue"])
        r = hmac.new(salt, msg, hashlib.sha256).digest()
        ok = (int.from_bytes(r, "big") % 4 == 0) == e["selected"]
        print(f"{e['id']}: {'OK' if ok else 'РАСХОЖДЕНИЕ'}")
        bad += 0 if ok else 1
    sys.exit(1 if bad else 0)


def cmd_verify_pulse(args) -> None:
    """Оффлайн-проверка сохранённых pulse: outputValue == SHA-512(signatureValue)
    (NIST Beacon 2.0). Полная проверка RSA-подписи по certificate — внешний шаг
    предпосылок (§15); эта связка ловит сфабрикованный outputValue без
    согласованных байтов подписи. Pulse без signatureValue (оффлайн-фикстуры
    тестов) помечается unverifiable, не валит проверку."""
    bad = 0
    for f in sorted(ablation_dir().glob("beacon-*.json")):
        pulse = json.loads(f.read_text())
        sig = pulse.get("signatureValue")
        if not sig:
            print(f"{f.name}: unverifiable (нет signatureValue)")
            continue
        expected = hashlib.sha512(bytes.fromhex(sig)).hexdigest()
        ok = expected.lower() == pulse["outputValue"].lower()
        print(f"{f.name}: {'OK' if ok else 'РАСХОЖДЕНИЕ outputValue↔signature'}")
        bad += 0 if ok else 1
    sys.exit(1 if bad else 0)


def main() -> None:
    p = argparse.ArgumentParser(description=__doc__)
    sub = p.add_subparsers(dest="cmd", required=True)
    d = sub.add_parser("decide", help="решение сэмплера по задаче")
    d.add_argument("--task-id", required=True)
    d.add_argument("--snapshot-ts", required=True, help="ISO-время заморозки предзадачного снимка")
    d.add_argument("--beacon-file", help="локальный pulse JSON (тесты/оффлайн)")
    d.set_defaults(fn=cmd_decide)
    v = sub.add_parser("verify", help="пересчитать все решения из журнала")
    v.set_defaults(fn=cmd_verify)
    vp = sub.add_parser("verify-pulse", help="связка outputValue == SHA-512(signatureValue) по сохранённым pulse")
    vp.set_defaults(fn=cmd_verify_pulse)
    c = sub.add_parser("commitment", help="напечатать sha256(salt)")
    c.set_defaults(fn=lambda a: print(hashlib.sha256(salt_bytes()).hexdigest()))
    args = p.parse_args()
    args.fn(args)


if __name__ == "__main__":
    main()
