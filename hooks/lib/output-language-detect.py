#!/usr/bin/env python3
"""Detect mixed-alphabet tokens in assistant output.

Reads assistant message text from stdin, prints one mixed-alphabet token
per line (capped at 10). A mixed-alphabet token is a single word that
contains both Cyrillic and Latin letters (e.g. "trёх", "fix'ом").

Exclusions (to avoid false positives):
  - fenced code blocks ``` ``` and inline code ``
  - filesystem paths (contain "/")
  - URLs (http://, https://, mailto:)
  - HTML tags <...>
  - markdown link targets [text](url) — text kept, url dropped
  - tokens containing digits or underscore (identifier-like)
  - hyphenated composites where every part is single-alphabet: "dev-БД",
    "API-роут", "Telegram-бот". These are normal Russian technical compounds,
    not the error the rule targets. Before this exclusion they were 94% of all
    hits (2524 of 2689), drowning the 79 real ones — the detector reported
    34 times more noise than signal, and every metric built on it was wrong.
    The apostrophe does NOT split a token: "fix'ом" stays a violation.
"""
import re
import sys


def is_mixed(token: str) -> bool:
    """True if the token mixes alphabets inside a single word.

    A hyphen is a word boundary in Russian compounds ("dev-БД"), so mixing
    that disappears once the token is split on "-" is not a violation.
    An apostrophe is not a boundary: "fix'ом" is one word and is a violation.
    """
    for part in token.split("-"):
        has_lat = bool(re.search(r"[A-Za-z]", part))
        has_cyr = bool(re.search(r"[А-Яа-яЁё]", part))
        if has_lat and has_cyr:
            return True
    return False


def main() -> None:
    text = sys.stdin.read()
    # Strip fenced code blocks and inline code
    text = re.sub(r"```.*?```", " ", text, flags=re.DOTALL)
    text = re.sub(r"`[^`]+`", " ", text)
    # Strip markdown link targets [text](url) — keep text, drop url
    text = re.sub(r"\]\([^)]+\)", "]", text)
    # Strip URLs
    text = re.sub(r"https?://\S+", " ", text)
    text = re.sub(r"mailto:\S+", " ", text)
    # Strip HTML tags
    text = re.sub(r"<[^>]+>", " ", text)
    # Tokenize: sequences of letters, apostrophes, and hyphens (no digits, no _)
    tokens = re.findall(r"[A-Za-zА-Яа-яЁё][A-Za-zА-Яа-яЁё'’\-]*", text)
    seen: set[str] = set()
    out: list[str] = []
    for t in tokens:
        if t in seen:
            continue
        if is_mixed(t):
            seen.add(t)
            out.append(t)
    for t in out[:10]:
        print(t)


if __name__ == "__main__":
    main()
