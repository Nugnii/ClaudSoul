# ClaudSoul — a Vision

ClaudSoul is not a memory library or a RAG setup. It's a cognitive architecture for an LLM agent — seven layers and the bridges between them. What follows is the idea, before the spec.

## The problem

A language model has no memory. Every session starts from scratch. Two standard fixes — dump everything into a SESSION.md, or retrieve on demand from a vector DB — are both insufficient.

Dumping everything makes the context noisy. A week in, you can't tell which entries still matter and which are residue from an abandoned hypothesis. RAG solves retrieval but not the question of **what** to retrieve. The model doesn't issue its own queries. It reacts to whatever you hand it.

What's missing is a system that decides for itself what knowledge to activate, what to generalize, what to forget. The way human memory does it — not by query, by association.

## The central metaphor

Human memory isn't a database. It's a network. Links are multimodal (context, emotion, sensory), emotion sets the weight and encoding speed, recall is a reconstruction every time, and forgetting is noise filtering, not loss.

ClaudSoul is built on the same model, adapted for an LLM agent. Every piece of knowledge is a record with contextual anchors, a weight (confidence × impact × intensity), edges to other records, and a life cycle: case → pattern → principle → decay.

## Seven layers

Numbered bottom-up, from persistence to co-cognition. Each answers one question.

**1. Persistence — how to survive the end of a session?** Files in the repo: SESSION.md, CLAUDE.md, memory/, global-lessons/. Git as free versioning. Enough as a foundation, not enough as knowledge.

**2. Knowledge — what do we know, and how sure are we?** Cases aggregate into patterns, patterns into principles. Every record carries nine contextual anchors (domain, situation, trigger, stakes, actors, environment, circumstances, purpose, method) — it activates because the context matched, not because someone asked.

**3. Communication — what's happening between the agent and the interlocutor?** Gaps between request and intent, decision trails, satisfaction signals. The interlocutor rarely phrases what they actually want, and that gap is diagnosable.

**4. Thought Trajectory — where is the interlocutor's thinking headed?** After three or four messages a direction appears. The agent builds a hypothesis, tests it on the next message, rewrites cascadingly (H1 → H2 → H3), and keeps the history as data about its own calibration.

**5. Meta-Cognition — are we learning correctly?** 7-day and 30-day metrics, auto-audit, detection of stale knowledge. Reflection on the process, not just the output.

**6. Prediction — what comes next?** Three modes: silent prep (read the files that will be needed), gentle suggestion (framed as a question), proactive action (only if easily reversible).

**7. Co-Cognition — how to think together?** Not agent-plus-human, but an emergent understanding neither has alone. Confirmed in practice, poorly formalized.

## Bridges

The central insight: **skills are born between layers, not inside them.** A communication skill is not a property of layer 3 or layer 6 — it's a property of their interaction. Predicting the interlocutor's next reaction (L3↔L6) isn't L3 plus L6; it's a new thing.

Fifteen bridges are formalized; some work, some are designed. Examples: L2↔L6 — proactive surprise-factor estimation before acting ("how unexpected will this be?" instead of "what went wrong?"); L3↔L6 — predicting the next speech act; L2↔L4 — knowledge activation by trajectory, not just by the current message.

## The uncertainty principle

Any conclusion the system reaches may be wrong. Not a disclaimer — an operating principle.

Confidence=5 means "confirmed many times," not "this is true." The interlocutor model is a hypothesis, not a portrait. A correct prediction does not imply understanding. A correction is a data point, not a verdict: the interlocutor who objects may also be wrong.

Communication knowledge is additionally capped: confidence ≤ 2 until confirmed by different interlocutors. One opinion is not a universal rule.

## What this isn't

It's not an assistant with memory. Not a searchable knowledge base. Not an agent pipeline. It's one specific bet about how to make an LLM agent self-learning: give it associative memory, reflection over its own learning process, and room for emergent skills at layer boundaries.

Most of the implementation is markdown files with YAML frontmatter, shell hooks, and Claude Code skills. No fine-tuning, no separate model. Just structure on top of a general-purpose LLM that turns one-off dialogue into accumulating understanding.
