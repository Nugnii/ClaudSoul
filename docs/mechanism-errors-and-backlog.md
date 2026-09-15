<!-- derived-from: docs/mechanism-errors-and-backlog.ru.md@d1afed57b32e -->
# How the system catches errors and keeps its backlog

> An export document: a technical appendix to the short entry point
> [«I'll remember» is not enough](not-enough-to-remember.md).
> Written for an outside reader — a human or another AI — so there are no file names here:
> yours will be your own, and what has to carry over is how the thing is built.
> The numbers come from an instrument run as of 14 September 2026, system version 1.33.0.

---

# PART 1. In brief, in plain language

## Why this exists

An ordinary assistant fixes the spot where you noticed the breakage and moves on. A week
later the same breakage surfaces next door — and it fixes it again, as if it were new.
Knowledge of the cause lives only in the conversation, and the conversation ends.

The system is built so that **a noticed error cannot quietly end in nothing**. Every problem
has a trace, every trace has an outcome, every outcome has a check. Not "I'll try to
remember", but guards that do not let you walk past.

## Two ideas everything else stands on

**The first.** If a rule had to be repeated twice, the culprit is not forgetting but a
missing mechanism. The rule is moved out of text and into a guard, and from then on it holds
by itself.

**The second — about the forest.** A tree has a root, a trunk and a canopy. If you cut the
leaves, the tree lives, and the leaves grow back. So analysis ends **not with an explanation
but with a map**: from the root that was found you draw upward everything that grew on it,
and you fix from the root. There are usually several roots, and together they form a
**forest** — each with its own canopy and its own repair order.

## The stages

**Stage 1. Notice.** "Error" here is broader than usual. Ten kinds of trigger are born inside
the conversation:

- a command failed (two failures out of the last six is already a signal);
- **a success that repeats**: a second pass over the same file while the runs are green means
  we tried, we checked, it did not add up, we are trying differently;
- the person I work with made a correction;
- the person I work with asked a question — the question often is the finding;
- the agent itself said "found it", "it turned out", "broken" in its own reply;
- **the agent repeated itself** — said "this is the third time today". Such a phrase usually
  closes a topic; here it opens one;
- a piece of knowledge was confirmed twice in one session;
- a piece of knowledge arrived and was not applied;
- a complaint about something being broken;
- cumulative signals over a day.

And separately — **events in the world**, which are not visible in the conversation at all: a
red check run on one's own commit, a rollback, a repeat hotfix, a backlog-item closure that
came back to life, a finding from a scheduled measurement, delegated subagent work cut short.
Only the scripts see them. Mature engineering practice does the same: a release rollback
mandates an analysis in and of itself, regardless of whether anyone noticed something wrong.

This is caught not by memory but by guards on events: before a tool call, after an edit, at
the turn boundary, when a subagent finishes, on a schedule.

**Stage 2. Stop.** The guard sees the trigger and demands analysis **before** the edit. For
six of the ten kinds this is a real refusal — the next tool call does not go through. Four
kinds only remind, and each has a stated reason: an event in the world arrives from outside
the turn (holding a stop because of yesterday's rollback would mean standing still for a
day), a question and a breakage complaint are recognised by a signal whose accuracy has been
measured and is not enough for a refusal, and a repeat in the agent's own speech is a signal
with an accuracy of 15 out of 20.

**Stage 3. Analyse.** Not "list the possible causes": a list of hypotheses can be produced
without any data and therefore always beats a real descent. The order is the reverse:

1. **Breadth across manifestations.** Where else is this same signal visible? Every place has
   an address: file, line, run, log. One manifestation means there is nothing to build an
   analysis on.
2. **Depth.** A chain of "why" from two to five **different** manifestations, along two
   lines: "why it broke here" and "where what we computed from came from". A node that
   honestly computed what it was handed is not the cause — feed it a correct input and the
   symptom disappears without the node being touched.
3. **Stopping by signal, not by count.** "Five whys" is a number of steps, not a criterion.
   Four tests for a link: remove it and the symptom could not have arisen **by any path**;
   the **ratio** of places does not drop as you move up; the link predicts where the signal
   will surface a third time; at that link a signal can be stated with **one** consequence.
4. **Sideways.** Where else the same construction stands — it will fail the same way, even if
   it is green right now.
5. **Downward.** What rests on this root — that is the list of what to check after the fix.

**Stage 4. Draw the forest.** A root that has been found but not mapped leaves the repair to
discretion: things get fixed where they were noticed, not where they originated. For each
root the map records:

- **the probe** — not a phrase but an executable signal: a command that prints the places
  where the root is in effect. The signal lives in data, not in the instrument's code, so a
  new root can be registered without editing the tool;
- **the canopy** — those places themselves, by address, marked "fixed / open / not ours";
- **the ratio** — how many places carry the link and in how many of them the symptom is
  already visible. This is the only stopping test that gets **harder** as you move up: the
  step up that drops the ratio is precisely the step past the root;
- **the counterexample** — a place that matches by form but is not a carrier. Without one the
  signal is not up for discussion;
- **the links** — which root holds which. The repair order is taken from the links: first the
  one the others stand on.

**Why the map is a file and not a story.** The ratio used to be presented in words, and the
substitution went through unnoticed: the analysis declared "five out of five", the real one
was "one out of sixty-five", and the guard let the turn pass — all the required words had
been spoken. Now the instrument runs each root's probe itself, counts the canopy and compares
it with what was declared; a discrepancy goes red. Along the way it also checks that the
forest stays a forest: no cycles, no links into nowhere, no orphan roots.

The map is **local to the project** — every project has its own roots. What is common across
projects travels not as a map but as knowledge: a pattern noticed twice in different places
becomes an entry in the base and arrives in the next project on its own.

**Stage 5. Give an outcome.** Silence is forbidden. There are four legitimate outcomes: fixed
it now; wrote it into the backlog; wrote down a piece of knowledge; issued a one-line verdict
of "false alarm". A guard's refusal is lifted by a named outcome, not by the fact that it was
forgotten. The "false alarm" verdict is not a concession but a measurement of the signal's
accuracy: if more than a quarter come out that way, you narrow the signal rather than
discipline the executor.

**Stage 6. Write the backlog item.** Six lines are mandatory for an item:

- **Result** — what state of the world counts as achieved. "The problem cannot arise, because
  here is the mechanism" also qualifies;
- **Check** — a command that can be run. While the item is open, it must be **red**. Green on
  an open item means one of two things, and both are defects: either the problem is already
  solved and it is time to close the item, or the command is not about it. An open item with
  a green or missing check **is not written at all** — that is a refusal at the moment of
  writing;
- **Green side** — a fixture in which the same command yields zero. A red command proves only
  that the world is not currently as declared; it does not prove that it will go green
  because of the fix rather than because it stopped seeing the subject;
- **Genus** — which class of defects the finding belongs to. The unit of work is the class, not
  the place;
- **Root** — which root of the forest it belongs to, or "none" with an explanation;
- **Reading** — if the result is measured by a number, that number has a source command, and the
  number is **rewritten by a mechanism** rather than remembered.

**Stage 7. Fix.** You edit a file named in an open item — and a guard reminds you: it is already
in the backlog. Otherwise a third outcome appears that should not exist: the problem is listed as
open, the fix proceeds as a new task, and the closing is never recorded.

**Stage 8. Close.** The "done" mark is put there by the executor, but what is trusted is the check
command, not the executor. At the turn boundary a guard runs it and names the discrepancy. The
second line of defence is the archiver: an item with a red check is not moved into the archive.
Cut off separately is the **blind check** — a command that goes green from a file name or from a
word in the text rather than from the result of the work: such an item is flagged and is not
closed at all.

**Stage 9. Clear out.** Once a week what has been closed moves off into the archive. The working
backlog file describes only what has not been done — otherwise it swells and stops being read.
The measurement that led to this: 21 open items against 32 closed, and 65% of the file's
characters went to work already done.

**Stage 10. Bring back.** Closings come in two kinds. Those backed by a test check themselves.
Those closed by a one-off action (a log cleaned out, a link restored) check themselves with
nothing and can quietly roll back; measurement: of 28 closed items, 11 were held by a test, 17 by
a one-off action. So those go through a re-check when their term comes due, and a resurrected
closing comes back as an open item. Triggers left without an outcome come back the same way, and
so do measurements whose term has run out.

**Stage 11. Turn it into knowledge.** Case → pattern (two or more similar cases) → principle
(works outside its own domain). Knowledge lives in files: each one has confirmation and
contradiction counters, a shelf life and, if it is worth it, its own guard. The point is not the
archive but that knowledge with high confidence pushes itself into the work at the right moment.

## What makes this scheme work rather than sit on paper

- **A success counts as an error too.** Three green runs of the same file are the same signal
  as three failures.
- **A signal has an owner and a deadline.** An obligation without an owner does not get done —
  that has been measured.
- **Closing is verified by a machine.** The executor's report proves nothing.
- **Treat the forest, not the leaves.** The order of fixes is taken from the links between roots,
  not from where the symptom was noticed first.
- **The level of enforcement matches the cost of the error.** A refusal is placed only where the
  signal is precise and the consequence is single; where it is not — only a reminder, and that is
  written down honestly.
- **Numbers are computed, not remembered.** Every "thirteen accumulated" has a source command, and
  every declared number has someone who rewrites it.
- **What is counted is not only "the guard fired" but also "the guard helped".** These are
  different numbers, and the second one requires separate accounting.
- **A property is proved by behaviour, not by reading.** For an instrument you look for a witness
  that goes red on a gutted instrument: a green test next to dead code means nothing.

---

# PART 2. Functional description for an AI reader

What follows is a description for a system that will read this, assess it and possibly reproduce
it for itself. The task for such a reader is kept in a separate file:
[the AI reader's task](ai-reader-task.md).

## 2.1. Environment and mode of existence

The system is not an application. It is a set of **event handlers** ("guards" from here on),
**text files** and **verifiable commands** living inside an agent harness. The harness invokes
guards on lifecycle events and passes them JSON on standard input; a guard answers with JSON on
standard output.

Eight hook points: before a tool call, after a tool call, the arrival of a message from the person
I work with, the turn boundary, context compaction, session start and session end, the completion
of a nested sub-agent.

Three response channels, and they are not equivalent:

1. **An injection into the turn's context** — works as a hint to the agent.
2. **A message to the owner** — visible to the human. Measurement: 15 firings that went into this
   channel only did not change the agent's behaviour a single time. What matters more: "invisible"
   is a property of the PAIR "channel and client", not of the channel. The same channel, taken for
   mute, turned out to be visible on the mobile client and unfolded one reminder into a dozen
   lines. A claim of invisibility ages together with the client, and it has no verifier.
3. **A refusal** — the tool call does not happen. The only level that cannot go unnoticed.

Of the 82 guards, 10 deny, 4 ask back, the rest inject text. This is not a weakness but a rule:
**a refusal is placed not on a piece of knowledge but on a signal, and only where the consequence
of continuing is exactly one.** A signal into which forms with different consequences have been
dumped is doomed to remain a hint — any strengthening would make some of the refusals false. One
refusal was introduced after an accuracy measurement of "34 out of 34 across 21,658 calls"; another
had to be narrowed to the literal case when it rejected correct work twice within one turn.

**A separate rule about the turn boundary.** A non-empty injection on the "the turn is ending"
event restarts the turn. So persistent state (a missing file, a broken setting) must not be
printed there: a measurement of three consecutive turns with a broken instrument gave three
restarts out of three. For persistent state there is a queue of deferred messages **paired with a
throttle keyed on the composition of the state**: the queue removes the restart but not the
repetition of the content. When there was no throttle, the summary went out in 69–94% of user
turns across four sessions.

## 2.2. Data model

**A backlog item** is a paragraph in a single text file. Marks: open, in progress, done,
deliberately not doing. The six mandatory lines are described in stage 6. Three properties of the
form matter more than its appearance:

- **The check is runnable** — not "look at it with your eyes" but a command with an exit code.
- **The sign of the check is the opposite of the mark**: red for an open item, green for a closed
  one. Trigger:
  six of the seven "checks" on open items did not measure what their own "result" declared.
- **Genus and root are mandatory, but "none — here is why" is a legal answer.** What is required
  is a decision, not an assignment.

Item recognition lives **in one place**, not as a private copy in every reader. Trigger: the items
changed their formatting, three readers each held their own copy of the criterion, and all three
failed on the same day, silently and each in its own way. Two subtleties worth adopting whole:
labels are defined by enumerating the variants, not by a character class (the status glyphs share
their first byte, and a closed item passed for an open one — checks went red on one OS and green
on another); and code blocks are stripped **before** item recognition, because the backlog document
quotes its own contract with samples, and a sample is visually indistinguishable from a real
item — without this a reader carried a sample off into the archive and executed the command
quoted inside it.

**The root map** is a separate project file where the forest lives. What a root record contains is
stage 4. The key property: **a root's criterion lives in data, not in the instrument's code.** The
instrument reads the map, runs each root's probe, counts the canopy itself and compares it against
the declared figure; a new root is registered by editing the map. Separately, the instrument checks
that the graph stays a tree: a cycle, a reference into nowhere and an orphan root are named
separately.

The canopy is a **queue, not a verdict**: the probe prints the places where the construct's
criterion is visible, some of them may turn out to be false, and this is written as a number —
"so many of those found have been verified". "Zero carriers" is a legal outcome; "not measured"
is one too, and it does not count as green. Mixing "how many the probe found" with "how many were
read by eye" is not allowed.

Two observations from practice. First: the instrument ended up in its own map — one root's probe
looked for state names through a list of variables, which is to say it was built by exactly the
construct that another root describes. Second: **the ratio declared in the map regularly diverges
from the counted one** — the canopy grows with every commit, while the number in the map is a
snapshot. The practical consequence for the reader: **do not copy canopy numbers into prose** —
not into descriptions, not into this document. A copy without a writer diverges silently; you have
to look by running it.

**The defect-genus registry** is a tool, not prose. Twelve genera, each with a criterion rule, a
counterexample and a **measured precision**. A genus without measured precision is not registered,
and that is written as a number: "not registered: precision 3%, catches genre, not relation".
Given a genus letter, the tool prints its carriers. On a genus item the "check" counts carriers,
so a new finding of the same construct increments the counter rather than creating an item. A
genus count is a **queue, not a field of view**: carriers whose consequence differs (tests, for
instance, where the defect fails loudly rather than silently) are printed by name and do not enter
the queue — otherwise "zero carriers" is unreachable by construction.

The counterexample is fed to the criterion **mechanically** instead of living in prose: a separate
test takes the declared counterexample and checks that the criterion does not catch it. The very
first such run found three violations in one genus and one stale address in another.

**The outcome log** holds one line per fired trigger: the kind of trigger, the turn key, the
outcome, the analysis trace. There are eight outcomes and they split in two: four are observed by
the machine (the chain was stated — **the only one that means the guard succeeded**; the edit was
deferred by a refusal; the carrier changed; there was no outcome) and four are named by the agent
(fixed it, wrote a backlog item, wrote a knowledge record, refuted it). The outcome is determined
**by the actions of the turn**, not by speech: "said" and "saved" look identical in the text of a
reply, and the whole mechanism rests on that distinction.

Two mistakes in this log worth not repeating. The first: a guard's success was at first **not
recorded** — the guard exited before the write, so a turn in which the analysis did happen never
entered the denominator, and the share of "no outcome" was inflated by construction; and the rule
for raising the enforcement level stood on that share. The second: the reader's list of
observable carriers was shorter than the closed list it printed itself — 23% of outcomes were
invisible to it.

**A guard's denominator** is a separate log: a criterion match is marked **at the moment of the
match**, tagged "spoke" or "stayed silent" and carrying an **event signature**. Recording after the
decision would make the share uncountable; the signature is needed in order to count distinct
events rather than tool calls — the first run gave "spoke 14%" for a guard that was recounting a
single remark on every call. A third tag is "did not read the input": silence caused by an
unreadable input is not silence by decision. A separate instrument names the criteria that have
not fired once across a window of sessions: a sensor's silence is indistinguishable from its being
healthy, and the list of the silent ones is taken **from the knowledge base, not from the
logs** — by construction they are not in the logs.

**The measurement registry** is a table of "what we measure · period · command". A measurement
without a deadline rests on somebody's memory, so each one has a period, and overdue ones are
named at session start. On a non-zero exit code the measurement runner **registers an analysis
trigger** — otherwise the finding died in the output. The period is counted in units of **work**,
not of the calendar: in a day the tree gets rewritten, in a year of silence nothing changes. Where
the subject is moved by commits, the unit is commits since the last run; the trigger: 569 commits
over 12 days passed as "not overdue" under a period of 30 days.

**The concept registry** checks not numbers but **entities**: a concept of stage rank is obliged
to be named in the state documents, and for every "concept × document" pair it is recorded why
it is there. Three states of the instrument: no registry, a concept has disappeared (with its
name), everything in place. The registry's boundary is stated outright: what goes into it is not
every mechanism, but whatever it is that without it a retelling of the design becomes **wrong**,
not merely incomplete.

**The knowledge base** is files with metadata: confidence, impact, nine context anchors,
confirmation and contradiction counters, links. 593 records, of which the operational circuit is
411 cases, 55 patterns, 10 principles.

## 2.3. Guard roles

| Role | Event | What it does | Level |
|---|---|---|---|
| Failure counter | before a call | 2+ failures within the last 6 outcomes → "stop, don't repeat the same approach" | hint |
| Rework detector | after an edit | file edited → test run → **the same** file edited again: a turn-back while the runs are green | hint |
| Analysis gate | before a call | a trigger exists, no trace of analysis in the turn → demands a chain | **refusal** for 6 kinds out of 10 |
| Named-problem guard | turn boundary | a problem named in the reply, no carrier changed | hint |
| Helper outcome | the helper finished | cut off without a reply → a trigger for analysis | hint |
| Backlog cross-check | before an edit | you are editing a file named in an open item | hint |
| Open-item contract | before a write | an item with a green or missing check is not written | **refusal** |
| Closure gate | turn boundary | runs the checks of items of both signs, names the discrepancy | hint |
| Archiver | on schedule | carries away what is closed; does not move one with a red or blind check | **inevitability** |
| Closure re-check | on schedule | every item has its own invariant; what has resurrected comes back | external run |
| Findings return | turn boundary | triggers without an outcome pile up and get named | hint |
| Map checker | on schedule | runs the probes, counts the canopies, goes red on a discrepancy | external run |
| Concept checker | on schedule | a concept of stage rank has disappeared from a document | external run |
| Result witness | on schedule | for a tool, a check is sought that goes red on a gutted tool | external run |
| Absent tool | before a call | the command invokes something that does not exist on this machine | **refusal** |
| Explicit test exit | before a write | the test does not end with an explicit `exit` — the code will be taken from the last command | **refusal** |

Three implementation details that will save you weeks:

**Failures are counted over a window, not over a consecutive streak.** The harness invokes
independent tools in one parallel block; one command fails, its neighbour passes — the "streak"
is broken by a success that has no place in any meaningful "stuck". A threshold of "two in a
row" is practically unreachable under such batching.

**The indicator is read off actions, not off speech.** A helper cutting off is caught by the
fact that the last meaningful block of its transcript is not a text reply (measured: 3 out of 3
that were cut off were caught, 3 that finished speaking stay silent; across 56 transcripts 55
end with text). A dictionary of speech indicators catches an admission of error inside reasoning
and **does not catch a tool failure** — "my analysis did not work", "the workaround produced no
result" all went past it.

**An instrument has more than two states.** At least three: "there is nothing to check here" —
stay silent; "the instrument is broken" — speak, because silence here reads as "clean"; "it ran,
no findings" — stay silent. The transcript reader has four: no file, the file cannot be read,
cut off, finished speaking. The fourth was at first merged with the second, and an unreadable
transcript was silently passed off as a success.

## 2.4. How it is measured that a guard helped

This is a separate loop, and without it the system turns into theater: the guards fire, but
whether anything changes is unknown.

- **The share of triggers without an outcome** — for each kind separately. The number demands one
  of two things: raise the enforcement level or narrow the indicator.
- **The share of false ones** (the verdict "it just seemed so") — the precision of the indicator. Above a quarter, the indicator is too broad.
- **"Spoke versus stayed silent"** — by the event signature, not by calls.
- **Silent indicators** — the ones that did not fire even once within the window.
- **Drift of the declared against the computed** — by the root map.
- **The window is counted in sessions or commits, not in days.**

## 2.5. Invariants — what has to be carried over

Your mechanisms will be your own. What has to be carried over is not the layout of the files but
these statements:

1. An error is not only a crash. Repetition with a green result is an indicator of the same class.
2. The signal is registered by the machine. The agent's memory is not a signal.
3. Every signal must have an outcome, and the outcome is observed through actions, not through words.
4. The analysis comes **before** the edit. After the edit it never starts — the task is already "done".
5. The descent stops on the root indicator, not on the number of steps.
6. The analysis ends with a **map**, not with an explanation. A root has its canopy written down,
   and fixing goes from the root upward along the map, not from the leaf where it was noticed.
   There can be several roots, and together they are a forest.
7. The root indicator lives as **data**, not as the instrument's code: the probe lies in the map,
   the instrument runs it.
8. The specificity ratio is **computed by the machine** and checked against the declared one. A
   ratio presented as a phrase is substituted unnoticed — and it was substituted.
9. **A declared number has a writer.** A number that the machine checks but nobody rewrites
   diverges from the world silently; a copy of such a number in prose is a new carrier of the same
   defect.
10. The unit of work is the defect class, not the place where it was found.
11. A task has a runnable completion criterion, and the sign of the criterion depends on the mark:
    red for an open one, green for a closed one.
12. **A red criterion has its green side presented** — a fixture where it yields zero. Otherwise
    it is unknown whether it will turn green from the fix or because it stopped seeing its subject.
13. Closure is verified by the machine, not by the performer's report; and a check that turns green
    from a file name or a word in the text does not count as closure.
14. A closure with no test behind it is re-checked on schedule.
15. The working list describes only what is not done; the chronicle lives separately.
16. A rule that had to be recalled twice is moved out of text and into a mechanism.
17. The enforcement level is a property of the consequence. Refusal only where there is a single
    consequence and the precision of the indicator has been measured.
18. A problem named out loud must land in a permanent carrier, otherwise it lives only until the end of the conversation.
19. An instrument has three states, not two, and "broken" sounds different from "clean".
20. A signal is recognized **in one place**: a copy of the signal at each reader fails silently
    and differently.
21. A guard's success belongs in the denominator alongside its failure — otherwise the share of
    "no outcome" is inflated by construction, and decisions rest on it.
22. A signal's counterexample is fed to it **mechanically**. A counterexample in prose verifies
    nothing.
23. **A tool's property is established by behavior under mutation**, not by reading the code: for
    every tool a witness is sought that goes red on a gutted tool.
24. **Periodicity is counted in units of work** — sessions, commits, turns — not of the calendar.
25. **A channel's invisibility is a property of the pair "channel and client"**, not of the
    channel. Before referring to anything, name the surface on which the person I work with will see it.

## 2.6. The blind spot worth knowing about in advance

Every trigger waits for an **occurrence**: an edit, a failure, a remark, a rollback. **Absence
does not occur.** A missing thing — an unwritten section, a field never created, a mechanism that
does not exist — produces no signal for the machine or for the agent: it is there from the very
beginning and it stays. A system whose only input is an occurrence is blind to absence **by
construction**.

The measurement that made this visible: all four documentation guards are driven by changes
("what did you touch, did it affect any descriptions"), and a new entity affects nothing — its
description does not exist yet. The system's central idea lived for a day without being mentioned
in a single state document, and it was a human who found this by reading, not a mechanism.

What is done about it: you set up **completeness** instruments (a registry of concepts, a registry
of claims, a registry of measurements), hang them on a **due period** rather than on a change, and
require that an instrument's finding become a trigger for root-cause analysis on a par with a
failure. Part of that obligation is derived **from the data**: a root that stands in the map must
be named in at least one state document — then a new root is picked up on its own, without
topping up the registry by hand.

## 2.7. Limits, stated honestly

- **The analysis gate recognizes form, not thought.** Five "why"s with no content it will count as
  analysis, while real analysis in an unfamiliar form it will not.
- **Quoting the rule ≠ analysis.** The quoted doctrine had to be cut out of the turn's text before
  counting: a quote carries every signal of the criterion and used to lift the refusal without
  anything having been analyzed. The root was not in the criterion but in its input. The limit
  remains: a restatement in one's own words is not caught.
- **An address is checked for presence, not for relevance to the matter.** The requirement "at
  least one address in every branch of the criterion" cut off 17% of false passes out of 976
  traces — but an address attached to the wrong place will pass.
- **The map's declared numbers live without a writer.** A divergence from the computed value
  arises with every growth of the canopy and is cleared by hand; the instrument finds it on
  schedule and calls it "findings, not a breakage". This works, but it means that any copy of
  those numbers in prose will drift apart silently. That is why they are not here.
- **A guard that is always red carries no information.** A permanent red is indistinguishable from
  a real divergence — that is a separate class of defect.
- **A test that feeds a guard an invented shape of input is green and useless.** For three and a
  half months the failure counter could not fire even once while its test was green: the test fed
  it the shape of data the guard assumed, not the shape the world produces. This pattern is
  confirmed 13 times in the knowledge base and stands 13th by frequency; the base maximum is 55.
- **A new instrument carries a defect from the very registry it was built for.** Observed four
  times in a single session, and once the instrument caught itself.
- **A document without mechanism names is invisible to the checkers.** This document is written
  without file names by design — and so it fell out of the name check, out of the registry of
  numbers, and out of the description-age check all at once. It came to light like this: it
  claimed that its numbers are verified by an instrument, while the registry held not a single row
  for it; and it called a refusal a guard that prints a hint and exits with zero. Both claims
  lived for four days.

## 2.8. The numbers as of 14 September 2026

| What | How many |
|---|---|
| Guards / libraries | 82 / 31 |
| Of those, registered in the harness | 75 |
| Refuse / ask again | 10 / 4 |
| Hook test files / server tests | 525 / 130 |
| Kinds of triggers inside a turn | 10, of which 6 refuse |
| Genera of world events | 6 |
| Defect genera in the registry | 12 (a signal exists for 10; for two, "not created" with the precision stated) |
| Roots in the map | 6; look at canopies and ratios by running the instrument, not at a copy in prose |
| Open backlog items | 6 |
| Knowledge base entries | 593 (424 cases, 55 patterns, 10 principles) |

The guard, test, and knowledge numbers stand here because they have a generator. The canopy
numbers are deliberately absent — they have no writer, and a copy in prose would drift apart
silently.

## 2.9. If you are building from scratch — the minimal version

The full loop is months of accretion. Much less than that already starts working, and the four
elements of the minimal version are listed in the entry text:
["I'll Remember" Is Not Enough](not-enough-to-remember.md) — a task file with a contract, one
check at the turn boundary, a repeat detector, an outcome log. Here — only the order in which
everything else is added to them.

A root map makes sense from the moment you have two analyses that converge on the same mechanism.
Defect genera — when the same thing starts being filed as items by location. Refusals — last, and
only with measured precision. Building the whole thing at once is a sure way to end up with
guards that never fire.
