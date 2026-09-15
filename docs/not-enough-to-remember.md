<!-- derived-from: docs/not-enough-to-remember.ru.md@a6667b2973d0 -->
# When "I'll remember" is not enough

## How an AI agent's mistakes turned from promises into verifiable mechanisms

In April 2026 my working process with the agent looked like this: the
agent makes a mistake, I point at it, the agent answers "got it, I'll keep that in mind" — and
a week later makes it again. Sometimes in the same file.

I started counting. It turned out that I had reminded the agent of one and the same rule three
times in three weeks, word for word: "you must if you see repeating symptoms understand that
there is a cause behind all of this". Three reminders about one thing is not my interlocutor's
forgetfulness. It is a missing mechanism.

What follows is 5 months of work on making the rule hold by itself. Below: the main idea, five
findings I did not expect, a couple of honest failures, and a minimal version that can be
assembled in a single working session.

---

## One idea

**A noticed error must either disappear in a verifiable way, or turn into a permanent object of
the system.**

There must be no third outcome. "I'll keep it in mind", "more carefully next time", "got it" are
not outcomes, they are a way to close the conversation. An error that stays only in the
conversation lives exactly as long as the conversation does.

Everything else follows from that: if an error must get an outcome, then something has to notice
it mechanically, demand the analysis before the fix, and then verify that the outcome actually
happened.

The whole loop fits on one line, and everything after that is only its details:

```
error → signal → analysis → outcome → check → return on regression
        (machine) (before the fix) (one of four) (command) (on schedule)
```

---

## Five findings I did not expect

**1. A repeated success is also an error signal.**
Every detector I knew of reacts to failures. But the most frequent sign of "the agent is
wandering" looks different: the file gets edited, the test is green, the file gets edited again,
the test is green again. Each iteration taken separately is a success. No counter connected
them. The moment that has to be caught is not chronic rewriting, it is the **first reversal**:
tried it, checked it, it did not add up, trying otherwise. It arrives on the second edit.

**2. Messages only the human sees do not change the agent's behaviour.**
The event handlers in my harness have two channels: write into the agent's context, or show a
message to the owner. I used the second one for a long time. Measured across the entire history:
**15 firings went into the owner channel only, and the agent reacted to none of them**. Not
"reacted rarely" — not once. Text that is not in the context does not exist for the agent.

**3. A safeguard's success must land in the denominator.**
I was counting the share of signals left without consequences — and the decision "strengthen the
safeguard or relax it" rested on that number. It turned out the guard recorded only unsuccessful
outcomes: when the analysis did happen, it returned from the code **before** the write to the
journal. Turns where everything worked correctly did not enter the statistics at all, and the
share of "no outcome" was inflated by construction. The metric that decisions rest on was lying
in the convenient direction.

**4. Absence produces no signal.**
This turned out to be a property of the design, not an oversight. All my sensors wait for an
event: an edit, a failure, a message, a release rollback. But a missing thing — an unwritten
section, a field nobody created, a mechanism that does not exist — **does not happen**. It is
there from the very beginning and it stays. A system whose only input is an event is blind to
absence by construction.

My documentation check, for instance, worked off changes: "you touched code, did that affect the
descriptions?" A new entity affects nothing — its description does not exist yet. Result: the
central idea of the system lived for a full day without being mentioned in a single document,
and it was a human who found that by reading, not a mechanism.

The only cure for this is instruments that run **on a schedule**, not on an event.

**5. Task closure is verified by the machine, not by the executor's report.**
Every open task has a command you can run. While the task is open, that command must **fail**. If
it is green on an open task, that is a defect, and always one of two: either the problem has
already been solved and closing it was forgotten, or the command checks the wrong thing. When I
introduced this rule and ran it across my own list, it turned out that **six checks out of seven
were not measuring what their own description declared**.

---

## Two failures worth knowing about in advance

**The test was green for three and a half months while the safeguard could not fire even once.**
The counter of failed commands read a field that does not exist in the data; moreover, on a
failed command the required event did not arrive at all. The test passed nonetheless — because it
fed the counter the shape of data the counter assumed, not the shape the real system produces.
This pattern is confirmed 13 times in my knowledge base and stands 12th by frequency; ahead of it
is, for example, "the subject of measurement is not the one the claim is about" — 55. Next to it
lives its other half: "the detector is wired to an indicator that does not yield what it claims",
with 22 confirmations.

**Quoting the rule lifted the requirement to analyse.**
The check for "an analysis happened" looked for markers of reasoning in the text. If the agent
quoted, word for word, the very instruction about how to reason, all the markers were found — and
the requirement was lifted, although nothing had been analysed. The cause turned out to be not in
the check but in its input: the quotation has to be cut out of the text before the counting.

There is a third one, my favourite: a tool that searches the code for a particular defect found
that defect **in itself** on its very first run.

---

## The minimal version

The full loop is months of accretion. Far less than that starts working:

1. **A task file with a contract.** Every entry has two mandatory fields: what counts as done,
   and **a runnable check command**. On an open entry it is red, on a closed one green.
2. **One check at the turn boundary** that runs those commands and names the discrepancies. We do
   not trust the executor's report.
3. **One repetition detector**: a second consecutive edit of the same file, or a second failure
   within a window of the last six calls. By window, not by consecutive streak — parallel calls
   break the streak with a success that has nothing to do with being stuck.
4. **An outcome journal**: one line per signal, and success goes into it too, not only failure.

Everything else — defect classification, the map of causes, refusals instead of reminders — is
worth introducing once you have measured what is lost without it. Building all of it at once is a
reliable way to end up with safeguards that never fire.

---

## The full write-up, and what to do with it

The detailed version is [the mechanics of the whole loop](mechanism-errors-and-backlog.md): the
data model, the roles of all the handlers, 25 transferable invariants, honestly stated limits,
and the numbers as of today.

Next to it lies [the task for the reading AI](ai-reader-task.md). Give both files to your own
agent — Claude, ChatGPT, Codex, an in-house one — and ask it to carry out the task: the agent
has to map the described architecture onto its own environment, name what is technically not
reproducible, and propose a minimal adoption plan with runnable acceptance criteria. Comparing
the answers of different agents to one and the same file is more interesting than reading the
file itself.
