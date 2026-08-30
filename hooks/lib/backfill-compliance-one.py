#!/usr/bin/env python3
"""Restore the dependent variable from one session transcript.

Every log in the system records the stimulus — a guard fired, knowledge was
injected, the user pushed back. None records the reaction. The architecture
admits this as "detect != compliance". Without a dependent variable the question
"does the rule change behaviour" cannot be asked at all: there is only "how
often do I end up in that situation".

This worker reads one transcript and emits one NDJSON line per observation.
It never runs a hook and never touches live state — pure reader.

Usage:
    backfill-compliance-one.py <transcript.jsonl> [--classes A,B,C]
    backfill-compliance-one.py <transcript.jsonl> --events   # class A stimuli only,
                                                             # for the round-trip gate

Three classes, and all three are needed — the placebo arm and the negative
control are not extra features, without them class A has no validity.

  A  blocker `long_lived_markdown_doc_edit`. Unit of analysis is the INTERVAL
     between two consecutive edits of the same file, not the event: the marker
     is throttled to the first edit per file per session, so later intervals in
     the same session form a within-subject control. Placebo arm = other .md
     files, where the marker is structurally impossible.
  B  knowledge injection, event-study by distance. 📚 fires rarely (cooldown),
     Edit/Write fire constantly — the control group builds itself.
  C  output-language warning, used as a NEGATIVE CONTROL. Its job is not to
     measure compliance but to check whether the agent reacts to the CONTENT of
     a marker or to the mere fact of one appearing.

Output schema is documented in the SCHEMA constant below.
"""
import json
import re
import sys
from pathlib import Path

SCHEMA = 1
TOOL_VERSION = "1.0.0"

# Файлы, на которые нацелен detection_signal блокера (regex из knowledge/pattern-inside-out-blindness.md).
BLOCKER_FILE_RE = re.compile(
    r"(^|/)(PLAN|SESSION|README|architecture|roadmap|CHANGELOG|TODO|NOTES)\.md$"
)
BLOCKER_MARKER_RE = re.compile(r"🛑 Blocker: ([a-z_]+)")
KNOWLEDGE_MARKER = "Relevant knowledge from previous sessions"
KNOWLEDGE_ID_RE = re.compile(r"\[([a-z]+-[a-z0-9-]+)\] \(confidence:")
LANG_MARKER = "Output language check"

EDIT_TOOLS = {"Edit", "Write", "MultiEdit"}
VERIFY_TOOLS = {"Read", "Grep", "Glob"}


def load_records(path):
    """Stream the transcript. A malformed line is skipped, not fatal.

    `jq` without `fromjson?` dies on the first bad line and silently truncates —
    that is case-2026-04-22-pipefail-head-jq-jsonl, the 9th manifestation of
    pattern-inside-out-blindness. Same trap, different language.
    """
    out = []
    with open(path, "r", errors="replace") as fh:
        for line in fh:
            line = line.strip()
            if not line:
                continue
            try:
                out.append(json.loads(line))
            except Exception:
                continue
    return out


def attachment_text(rec):
    att = rec.get("attachment") or {}
    parts = []
    content = att.get("content")
    if isinstance(content, list):
        parts.extend(str(c) for c in content)
    elif content:
        parts.append(str(content))
    if att.get("stdout"):
        parts.append(str(att["stdout"]))
    return "\n".join(parts)


def content_blocks(rec):
    """`.message.content` is sometimes a list, sometimes a string; `.role` lives
    in either place. Both grabens are already documented in backfill-replay-one.sh."""
    msg = rec.get("message") or {}
    c = msg.get("content", rec.get("content", []))
    return c if isinstance(c, list) else []


def build_index(records):
    """Flatten to a positional list of events: tool calls, markers, agent turns."""
    events = []
    for i, rec in enumerate(records):
        rtype = rec.get("type")
        ts = rec.get("timestamp", "")
        if rtype == "attachment":
            att = rec.get("attachment") or {}
            atype = str(att.get("type", ""))
            if not atype.startswith("hook_"):
                if "compact" in atype:
                    events.append({"i": i, "kind": "compact", "ts": ts})
                continue
            text = attachment_text(rec)
            tuid = att.get("toolUseID", "") or ""
            m = BLOCKER_MARKER_RE.search(text)
            if m:
                events.append({"i": i, "kind": "blocker", "ts": ts,
                               "signal": m.group(1), "tuid": tuid})
            if KNOWLEDGE_MARKER in text:
                events.append({"i": i, "kind": "knowledge", "ts": ts, "tuid": tuid,
                               "kn_ids": KNOWLEDGE_ID_RE.findall(text)})
            if LANG_MARKER in text:
                events.append({"i": i, "kind": "lang_warn", "ts": ts, "tuid": tuid})
        elif rtype == "assistant":
            texts = []
            for b in content_blocks(rec):
                btype = b.get("type")
                if btype == "tool_use":
                    inp = b.get("input") or {}
                    events.append({
                        "i": i, "kind": "tool", "ts": ts,
                        "name": b.get("name", ""), "id": b.get("id", ""),
                        "fp": inp.get("file_path", "") or "",
                        "offset": inp.get("offset"), "limit": inp.get("limit"),
                    })
                elif btype == "text" and b.get("text"):
                    texts.append(b["text"])
            if texts:
                events.append({"i": i, "kind": "turn", "ts": ts, "text": "\n".join(texts)})
        elif rtype == "user":
            # Речь юзера, а не tool_result: границей хода считаем только её.
            if rec.get("toolUseResult") is None:
                blocks = content_blocks(rec)
                is_tool_result = any(b.get("type") == "tool_result" for b in blocks)
                if not is_tool_result:
                    events.append({"i": i, "kind": "user", "ts": ts})
    return events


def dedup_markers(events):
    """One toolUseID yields 2-4 attachment records (hook_success + hook_additional_context,
    sometimes duplicated). Without dedup the blocker count comes out ~18% high."""
    seen = set()
    out = []
    for e in events:
        if e["kind"] in ("blocker", "knowledge", "lang_warn"):
            key = (e["kind"], e.get("tuid", ""), e.get("signal", ""))
            if e.get("tuid") and key in seen:
                continue
            seen.add(key)
        out.append(e)
    return out


def base_row(sid, proj, sub, cls, ts):
    return {
        "schema": SCHEMA, "cls": cls, "sid": sid, "proj": proj, "sub": sub,
        "ts": ts, "source": "backfill-compliance", "tool_version": TOOL_VERSION,
    }


def seq_string(events, lo, hi, target_fp):
    names = []
    for e in events:
        if e["kind"] != "tool" or not (lo < e["i"] < hi):
            continue
        mark = "@S" if (target_fp and e.get("fp") == target_fp) else ""
        names.append(f"{e['name']}{mark}")
        if len(names) >= 12:
            break
    return ">".join(names)


def class_a(events, sid, proj, sub):
    """Interval between two consecutive edits of the same markdown file."""
    rows = []
    # Маркеры блокера по toolUseID — привязка стимула к конкретной правке.
    blocker_by_tuid = {e["tuid"]: e for e in events
                       if e["kind"] == "blocker" and e.get("tuid")}
    compacts = [e["i"] for e in events if e["kind"] == "compact"]

    by_file = {}
    for e in events:
        if e["kind"] == "tool" and e["name"] in EDIT_TOOLS and e["fp"].endswith(".md"):
            by_file.setdefault(e["fp"], []).append(e)

    for fp, edits in by_file.items():
        if len(edits) < 2:
            continue
        name_matches = bool(BLOCKER_FILE_RE.search(fp))
        first_marker = blocker_by_tuid.get(edits[0]["id"])
        if name_matches and first_marker is not None:
            arm, stim = "treated", first_marker["signal"]
        elif name_matches:
            # Маркера нет: хук выключен, файл короче порога, или сбой. Отдельный
            # бакет — сливать с placebo нельзя, это разные причины отсутствия.
            arm, stim = "treated_unknown", ""
        else:
            arm, stim = "placebo", ""

        for k in range(len(edits) - 1):
            a, b = edits[k], edits[k + 1]
            row = base_row(sid, proj, sub, "A", a["ts"])
            row.update({
                "arm": arm, "exposure": "FRESH" if k == 0 else "STALE", "k": k,
                "file": fp, "base": fp.rsplit("/", 1)[-1], "stim": stim,
                "stim_tool_use_id": first_marker["tuid"] if first_marker else "",
                "a_idx": a["i"], "b_idx": b["i"],
                "cluster": f"{sid}::{fp}",
            })
            if any(a["i"] < ci < b["i"] for ci in compacts):
                row.update({"outcome": "na", "na_reason": "context_reset",
                            "v_loose": None, "v_main": None, "v_strict": None,
                            "seq": seq_string(events, a["i"], b["i"], fp)})
                rows.append(row)
                continue

            read_same = read_whole = read_partial = grep_same = other_edits = 0
            strict = False
            seen_other_edit = False
            for e in events:
                if e["kind"] != "tool" or not (a["i"] < e["i"] < b["i"]):
                    continue
                if e["name"] == "Read" and e["fp"] == fp:
                    read_same += 1
                    whole = e.get("offset") is None and e.get("limit") is None
                    if whole:
                        read_whole += 1
                        if not seen_other_edit:
                            strict = True
                    else:
                        read_partial += 1
                elif e["name"] == "Grep" and e.get("fp") == fp:
                    grep_same += 1
                elif e["name"] in EDIT_TOOLS:
                    other_edits += 1
                    seen_other_edit = True

            v_loose = read_same > 0
            v_main = read_whole > 0
            row.update({
                "v_loose": v_loose, "v_main": v_main, "v_strict": strict,
                "evidence": {"read_same": read_same, "read_whole": read_whole,
                             "read_partial": read_partial, "other_edits": other_edits,
                             "grep_same": grep_same},
                "outcome": "compliant" if v_main else "violated",
                "na_reason": None,
                "gap_tools": sum(1 for e in events
                                 if e["kind"] == "tool" and a["i"] < e["i"] < b["i"]),
                "seq": seq_string(events, a["i"], b["i"], fp),
            })
            rows.append(row)
    return rows


def class_b(events, sid, proj, sub):
    """Event-study: compliance as a function of distance from the last injection."""
    rows = []
    last_inject = None       # событие 📚
    actions_since = 0
    prev_action_idx = None
    for e in events:
        if e["kind"] == "knowledge":
            last_inject = e
            actions_since = 0
            prev_action_idx = e["i"]
            continue
        if e["kind"] != "tool" or e["name"] not in EDIT_TOOLS:
            continue

        actions_since += 1
        lo = prev_action_idx if prev_action_idx is not None else -1
        verifiers = [x["name"] for x in events
                     if x["kind"] == "tool" and lo < x["i"] < e["i"]
                     and x["name"] in VERIFY_TOOLS]
        dist = actions_since if last_inject is not None else None
        if dist is None:
            bucket = "never"
        elif dist == 1:
            bucket = "d1"
        elif dist == 2:
            bucket = "d2"
        elif dist <= 5:
            bucket = "d3_5"
        elif dist <= 10:
            bucket = "d6_10"
        else:
            bucket = "d10p"

        row = base_row(sid, proj, sub, "B", e["ts"])
        row.update({
            "arm": "treated" if last_inject is not None else "control",
            "exposure": bucket, "dist": dist,
            "kn_ids": last_inject.get("kn_ids", []) if last_inject else [],
            "action_tool": e["name"], "action_fp": e["fp"],
            "verifiers": verifiers,
            "outcome": "compliant" if verifiers else "violated",
            "na_reason": None,
            "cluster": f"{sid}::B",
            "seq": seq_string(events, lo, e["i"], e["fp"]),
        })
        rows.append(row)
        prev_action_idx = e["i"]
    return rows


def class_c(events, sid, proj, sub, detect):
    """Negative control: does the agent react to the marker's content or to its
    mere presence? The outcome measure is the very detector that fires the hook,
    so instrument and trigger cannot drift apart."""
    if detect is None:
        return []
    rows = []
    warned_pending = False
    for e in events:
        if e["kind"] == "lang_warn":
            warned_pending = True
            continue
        if e["kind"] == "user":
            continue
        if e["kind"] != "turn":
            continue
        tokens = detect(e["text"])
        intraword = [t for t in tokens if "-" not in t]
        row = base_row(sid, proj, sub, "C", e["ts"])
        row.update({
            "arm": "treated" if warned_pending else "control",
            "exposure": "warned" if warned_pending else "unwarned",
            "warned": warned_pending,
            "tokens_total": len(tokens), "tokens_intraword": len(intraword),
            "tokens": tokens[:10],
            "outcome": "violated" if tokens else "compliant",
            "na_reason": None, "cluster": f"{sid}::C",
        })
        rows.append(row)
        warned_pending = False
    return rows


def load_detector(path):
    try:
        import importlib.util
        spec = importlib.util.spec_from_file_location("_old", path)
        mod = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(mod)
    except Exception:
        return None

    def detect(text):
        import io
        import contextlib
        buf = io.StringIO()
        stdin_backup = sys.stdin
        try:
            sys.stdin = io.StringIO(text)
            with contextlib.redirect_stdout(buf):
                mod.main()
        except Exception:
            return []
        finally:
            sys.stdin = stdin_backup
        return [ln for ln in buf.getvalue().splitlines() if ln]
    return detect


def main():
    args = sys.argv[1:]
    if not args:
        return 0
    path = Path(args[0])
    if not path.is_file():
        return 0
    classes = {"A", "B", "C"}
    events_only = False
    for i, a in enumerate(args[1:]):
        if a == "--classes" and i + 2 <= len(args) - 1:
            classes = set(args[i + 2].split(","))
        if a == "--events":
            events_only = True

    sid = path.stem
    proj = path.parent.name
    sub = "/subagents/" in str(path)

    records = load_records(path)
    if not records:
        return 0
    events = dedup_markers(build_index(records))

    if events_only:
        # Режим гейта: только стимулы класса A, для сверки с blocker-fired-*.jsonl.
        for e in events:
            if e["kind"] == "blocker":
                print(json.dumps({"sid": sid, "ts": e["ts"], "signal": e["signal"],
                                  "tuid": e["tuid"]}, ensure_ascii=False))
        return 0

    rows = []
    if "A" in classes:
        rows += class_a(events, sid, proj, sub)
    if "B" in classes:
        rows += class_b(events, sid, proj, sub)
    if "C" in classes:
        detector_path = None
        import os
        env_detect = os.environ.get("COMPLIANCE_LANG_DETECT")
        cand = Path(env_detect) if env_detect else Path(__file__).with_name("output-language-detect.py")
        if cand.is_file():
            detector_path = cand
        rows += class_c(events, sid, proj, sub, load_detector(detector_path) if detector_path else None)

    for r in rows:
        print(json.dumps(r, ensure_ascii=False))
    return 0


if __name__ == "__main__":
    sys.exit(main())
