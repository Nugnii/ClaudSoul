#!/usr/bin/env python3
"""green_D446.py <src> <dst> - miniature fix of a COPY of ROOTS.md (D446)."""
import os
import re
import subprocess
import sys

FRAC_LINE = re.compile(r"(\*\*Дробь\.\*\*\s*)(\d+)(\s*из\s*)(\d+)")
HEADER_RE = re.compile(r"(?m)^(## R\d+ )")
ROOT_IDS = ("R1", "R2", "R3")


def carrier_count(repo, root_id):
    probe = os.path.join(repo, "scripts", "probes", root_id + ".sh")
    p = subprocess.run(["bash", probe], cwd=repo, capture_output=True, text=True, timeout=60)
    return len([line for line in p.stdout.split("\n") if line.strip()])


def put_text(path, text):
    data = text.encode("utf-8")
    fd = os.open(path, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o644)
    try:
        os.write(fd, data)
    finally:
        os.close(fd)


def main():
    src, dst = sys.argv[1], sys.argv[2]
    repo = os.environ.get("CLAUDSOUL_REPO") or os.path.dirname(os.path.abspath(src))
    text = open(src, encoding="utf-8").read()
    parts = HEADER_RE.split(text)
    out = [parts[0]]
    patched = {}
    i = 1
    while i < len(parts):
        header = parts[i]
        body = parts[i + 1] if i + 1 < len(parts) else ""
        m = re.match(r"## (R\d+) ", header)
        rid = m.group(1) if m else None
        if rid in ROOT_IDS:
            n = carrier_count(repo, rid)
            new_body, cnt = FRAC_LINE.subn(
                lambda mo, n=n: mo.group(1) + str(mo.group(2)) + mo.group(3) + str(n),
                body,
                count=1,
            )
            assert cnt == 1, "green_D446: anchor missing for " + rid
            body = new_body
            patched[rid] = n
        out.append(header)
        out.append(body)
        i += 2
    missing = set(ROOT_IDS) - set(patched)
    assert not missing, "green_D446: roots missing: " + repr(sorted(missing))
    put_text(dst, "".join(out))
    return 0


if __name__ == "__main__":
    sys.exit(main())
