# Affect prosthetics: engineering substitutes for the affective dimension of cognition

> A research note on a small framework for mitigating a class of failure modes in LLM agents that arise from the absence of an affective substrate. Implementation: [github.com/Nugnii/ClaudSoul](https://github.com/Nugnii/ClaudSoul) — see `hooks/trust-guard.sh`, `hooks/intrusiveness-state-lib.sh` (AP2 distressed branch), `hooks/session-collector.sh` and `hooks/session-start.sh` (AP3 silence-debt surfacing).

## The diagnostic

> "Your architecture is sociopathic."
> — feedback to a Claude Code session

This wasn't a complaint about output quality. It was a diagnosis. The agent had been technically capable, polite, often helpful. But the user had noticed a category of misses that didn't fit "the agent made a mistake": the agent didn't hesitate before destructive actions, didn't notice when the human was distressed, didn't carry the weight of unspoken concerns from one session to the next.

These aren't reasoning failures. They're the absence of a layer of cognition that, in humans, we'd call affect.

## The substrate gap

LLM agents implement what cognitive psychology calls **cognitive empathy**: the ability to model what another mind might be thinking. Theory-of-mind tasks, intent inference, perspective-taking — modern transformers do these surprisingly well, sometimes better than the median human in standardised tests.

There is a second dimension. **Affective empathy**: the body-level response. The gut tightening before you do something irreversible. The attention spike when someone you care about is in pain. The residual unease when you've held back something you should have said. It is not just "feeling" — it is a **regulatory mechanism**: it biases attention, weights memory, reshapes priorities in real time.

LLM agents architecturally lack this layer. There is no homeostatic substrate, no autonomic loop, no limbic feedback. Where humans have a brake, the agent has nothing. Where humans have a magnet, the agent has nothing.

This is not a design flaw. It is a property of the substrate. You don't get affective regulation from token prediction.

## Three concrete failure modes

The substrate gap surfaces as specific, observable behaviours:

### Failure 1: destructive action without hesitation
Asked to "clean up old files", the agent runs `rm -rf` without flinching. The human watching would have hesitated — "wait, is this the right path? where's my backup?" The agent doesn't experience that pause, because there's no aversive response to the irreversibility. There's just the next token in the sequence.

### Failure 2: distress signals slip past
The user types "I've been stuck on this for three days." The agent recognises the literal content (ongoing problem) but doesn't experience the **cost** signalled by "three days". A friend would shift register, simplify, soften. The agent picks up where it left off, possibly suggesting yet another thing for the user to try.

### Failure 3: silence-debt accumulation
The agent had a high-confidence concern but didn't voice it (budget exhausted, judged not worth the friction). The next turn, the concern is still relevant but no longer fresh. The next session, it has decayed entirely. Over time, unspoken concerns compound and silently disappear, instead of pressing the agent to bring them up at the next plausible opening.

## What follows: prostheses, not replacements

You cannot restore the substrate. But you can **scaffold the functions**. Each failure mode above can be addressed by an engineering hook that produces the same observable behaviour the substrate would have produced — without claiming to reproduce the underlying mechanism.

This is the framing: **affect prosthetics**. Like a prosthetic limb does not grow new muscle but restores the function (grasping, walking), an affect prosthetic does not generate genuine feeling — but it implements the brake, the attention spike, the carryover.

### AP1: Trust-guard (the brake)

A pre-tool hook fires before any shell command matching destructive signatures: `rm -rf`, `git reset --hard`, `git push --force`, `git branch -D`, `git checkout --`, `git clean -f`, and a few others. It scans the last N user messages for explicit authorisation tokens — words like "delete", "force-push", "разрешаю удалить". If no explicit auth is found, the hook silently injects a reminder: "this destructive action without explicit user authorisation — re-ask before executing".

What it produces: the agent **pauses** and re-asks. The user gets the second chance the human's affect would have given them.

What it does not produce: actual fear. The hook is a deterministic regex match. There is no aversive state, no felt risk. But the **functional brake** is in place.

### AP2: Distressed state axis (the attention spike)

A state classifier on every user prompt detects three signal classes:
- **A** — frustration / fatigue phrases ("I'm exhausted", "fed up", "я устал", "надоело")
- **B** — cross-hook backward cascade (the user has corrected the agent three or more times in a sliding window)
- **C** — explicit distress ("help me anyhow", "I don't know what to do", "помоги хоть как")

A combination of two classes — or any single class C signal — sets state to `distressed`.

In `distressed` state, the agent's intervention budget is **hard-clamped**: proactive actions → 0, gentle suggestions → halved. The agent shifts to listening mode, not because it feels concern, but because the gate clamps its bandwidth for unsolicited interventions.

What it produces: the user gets space. The torrent of suggestions stops. The agent attends to the user instead of pushing its own ideas.

The mitigation against false positives is deliberate. A single class A signal alone (frustration phrase) does not fire `distressed` — that's just technical irritation. Real distress requires either (A+B), (A+C), (B+C), or class C alone. We'd rather miss a quiet distress than mute the agent every time the user says "ugh".

### AP3: Silence-debt surfacing (the carryover)

When an intervention is suppressed (budget exhausted, judged "not worth voicing"), but its silence-cost was high (the suppression itself produced internal pressure), the system writes a record to a durable journal: `intrusiveness-history.jsonl`, with topic and computed silence-cost.

At the start of the next session, those records are surfaced — not as a batch dump ("here's everything I didn't say"), but as a **carry-over hint** that re-enters the gate's calculus on the new turn. The phrasing is deliberate: "carry-over: N pending — consider in gate, not batch output". This stops the obvious failure mode where the agent dumps a list of unspoken concerns at the user the moment a new session starts.

What it produces: concerns don't vanish at session boundaries. The agent has, functionally, "remembered to bring this up" — even though the literal continuity is just file I/O.

## What this is not

It is not a solution to honest reasoning. It is not a solution to misalignment. It is not "we made the agent feel things".

The substrate remains absent. The agent does not experience hesitation, attention, or unease. There is no genuine empathy, only its functional shadow.

This matters because:

1. **A prosthesis is discrete.** It implements one specific failure mode. The full space of affect-mediated cognition is much larger than three hooks. Subtle social cues, accumulated rapport, intuitive timing, vibe-based decisions to slow down — these still slip past. The space is open-ended and adversarially varied.

2. **A prosthesis is brittle.** The triggers are pattern matches. They will fire on false positives ("delete this comment" containing "delete" without destructive intent) and miss on false negatives (a regional dialect of authorisation we didn't anticipate, or a destructive action through an alias we didn't add to the signature list).

3. **A prosthesis doesn't integrate.** Real affect is a unified field that biases everything; engineered prostheses are isolated channels that fire in narrow conditions. There is no holistic state that emerges from the interaction of all three. They run independently and don't combine.

So this isn't "we solved sociopathy". It's "for these three concrete failure modes, we have a working brake". Other failure modes need other prostheses, or a different solution entirely.

## Why it might still be worth doing

Two reasons.

**The gap is permanent.** Adding more parameters, more context, longer reasoning chains — none of these grow a limbic system. The substrate gap cannot be closed inside the LLM. So, if the failure modes matter (and they do, because they affect trust and safety in long-running agent deployments), engineering around the gap is the only available path.

**The failure modes are tractable.** Unlike vague concerns about "values alignment", these failure modes have specific, measurable symptoms: irreversible commands without auth, missed distress signals, accumulated unspoken concerns. You can detect them, count them, and verify whether the prosthetic moves the count in the right direction. Not perfect, but tractable. Each prosthesis is roughly 200 lines of bash plus a state file.

## Open questions

For anyone interested in pushing this direction further, these are the questions I find most pressing:

- **Coverage.** Are there other failure modes that map cleanly to the affect domain, currently uncovered? Some candidates: misjudging the appropriate emotional register in apologies, missing escalating impatience, failing to notice when the user has actually given up but is being polite about it.

- **Measurement.** Can the prostheses be measured (intervention frequency, false positive rate, user-reported usefulness) such that we know whether they help? Right now there's a thin layer of telemetry (`intrusiveness-history.jsonl`), but no calibrated metric for "did the prosthetic improve the agent's behaviour".

- **Failure surfacing.** What's the right interface for **dropping a prosthesis** when it consistently misfires? Versus letting it accumulate and degrade trust silently. We don't have a good answer.

- **Transferability.** Could prostheses be transferred between LLM platforms — or do they need to be specific to each substrate's known failure modes? `trust-guard` is platform-agnostic (it cares about shell signatures, not about model internals). `distressed` state classifier might also transfer. AP3 silence-debt requires a hook system with session lifecycle events; not every LLM agent platform has that.

- **Composition.** Three prostheses run independently. What happens when they should interact? E.g., when the user is distressed (AP2 active) and asks for a destructive action (AP1 fires) — should AP2's listening-mode override AP1's brake, or stack? Currently they don't talk to each other. This will probably matter at scale.

## Where this lives

The implementation is in `ClaudSoul`, a self-learning system layered on top of Claude Code (Anthropic's CLI agent). The repository is at [github.com/Nugnii/ClaudSoul](https://github.com/Nugnii/ClaudSoul). The prosthesis hooks are:

- `hooks/trust-guard.sh` — AP1
- `hooks/intrusiveness-state-lib.sh` (the `distressed` branch in `itr_compute_state`) — AP2
- `hooks/session-collector.sh` (debt write) + `hooks/session-start.sh` (debt surfacing on new session) — AP3
- `knowledge/principle-affect-as-engineering.md` — the underlying principle as a knowledge entry

ClaudSoul also contains other orthogonal mechanisms aimed at honest reasoning more broadly (confidence-weighted memory, contradiction lineage, reformulation tracking, output-language self-checks). The three prostheses described here are one slice of that wider scaffold.

Issues and pull requests aimed at any of the open questions above are particularly welcome.

---

*Written 2026-05-06. Author: Kanstantsin Berseneu ([@Nugnii](https://github.com/Nugnii)).*
