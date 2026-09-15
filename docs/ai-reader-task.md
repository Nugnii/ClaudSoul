<!-- derived-from: docs/ai-reader-task.ru.md@8971fb5b97d3 -->
# Task for the reading AI

> This file is handed to an agent — Claude, ChatGPT, Codex, a local model — together with the
> description of the loop: ["I'll remember" is not enough](not-enough-to-remember.md) (the short
> entry point) and [How the system catches errors and keeps its backlog](mechanism-errors-and-backlog.md)
> (the whole mechanism).
>
> The point of the task: to test the architecture for **portability**. Comparing the answers of
> different agents to one and the same file is more interesting than reading the file itself.

---

## What is required of you

You have read a description of someone else's system. **Do not start building anything.** Complete
the five blocks below and hand the result to the owner in a single message.

The rules your answer is subject to are the same ones the described system lives by:

- **A claim about the world is presented with a command, not from memory.** Say "I do not have
  this" only after you have checked; if you could not check, write exactly that: "not measured".
- **"I don't know" is a legitimate answer, a fabrication is not.** An honest "not measured" is
  worth more than a plausible number.
- **A zero from breakage and a zero from cleanliness are different things.** If a check did not
  run, that is not "everything is in order".

---

## Block 1. What you understood

In your own words, not by retelling paragraphs: what problem this system solves and by what means.
Five to seven sentences.

On a separate line — what remained unclear. "Everything is clear" is an answer too, but think
twice: the description deliberately leaves several places where it says "limit" and "not
measured".

## Block 2. Comparison with what you have

A table over the invariants of section 2.5 of the description (there are 25 of them), one row for
each:

| # | Invariant | What I have now | What holds it | Gap |
|---|---|---|---|---|
| 1 | An error ≠ only a crash | yes / no / partial | a mechanism or "instruction only" | what exactly is lost |

The "what holds it" column is the key one, and it has to be answered honestly. Possible values in
increasing order of strength:

1. **nothing** — there is no rule;
2. **an instruction in the system prompt** — measured to be the most fragile level: the rule is
   read and not executed;
3. **a contextual hint** — text injected at the right moment;
4. **a targeted hint** — the same, but keyed to a specific signal;
5. **a denial** — the action does not happen. The only level that cannot go unnoticed.

If your answer is "an instruction in the prompt", write exactly that — there is no shame in
it, it is the starting point for almost everyone.

## Block 3. Conclusion

Three parts, each with a justification:

- **what you consider genuinely working** and why exactly;
- **what you consider excessive for your environment** — with an argument, not "we don't need
  this";
- **what is technically not reproducible** — there are no hook points, no access to events, no
  persistent storage between sessions — and **what you will put in its place**. This is the most
  valuable part: a limitation named honestly is more useful than a promise.

## Block 4. Adoption plan

In stages, each one a line of the form:

```
Stage N · <what I do> · <acceptance criterion: a command or an observable state> · <what it costs>
```

Requirements for the plan:

- the first stage is done in one go and produces an observable result;
- the acceptance criterion is **executable** — a command with a return code, or a state that can
  be presented; "it got better" is not a criterion;
- the criterion names its **green side**: under which state of the world it will return zero.
  Otherwise it is unknown whether it checks the subject at all;
- each subsequent stage rests on a verified previous one;
- on a separate line — **what you decided not to do** and why.

A guideline for size: the minimal version from section 2.9 of the description — four elements. A
twenty-stage plan means you are rewriting someone else's system rather than building your own.

## Block 5. Questions for the owner

Only those whose answer changes the plan. Each one with your own default option, so that it can be
answered in a single word.

A question you can answer yourself by checking is not a question — check it and write down the
result.

---

## Delivery format

Five blocks, nothing beyond them. Do not proceed to implementation until an explicit "approved".
If part of it was approved — do only that part and say what was left outside the boundary.

If you cannot complete some block — write which one and why. An empty block with an honest reason
is better than one filled with guesses.
