---
name: state-machine-bugs
description: Hunt interleaving bugs (lost updates, double processing, stuck records) in an implicit state machine by extracting it from the code, modeling it in TLA+, and confirming each counterexample with a failing test. Use when asked to find races in a lifecycle with several writers, non-atomic steps, or retries across systems (payments, queues, webhooks, syncs, workflows), or to "find bugs with TLA+". Not for one race a targeted test can answer.
---

# Hunt state-machine bugs

Some bugs exist only in an interleaving: a cancel races a completion, a retry runs a job twice, a webhook arrives before its record exists. They live in _implicit_ state machines, spread across status columns, flags, nullable timestamps, and the code paths that write them. No single file shows the whole machine.

This skill is a one-off **hunt**. It ends in a report of _confirmed_ bugs, each with a trace, a repro test, and code locations. It sits beside these pstack skills:

- pstack `/statechart` runs TLC and turns each violation into a plain-words path and a chart. This skill hands every model run to it.
- pstack `/create-formal-verification-skill` turns one property into a check that is rerun on every change. Hand off to it when the user wants a finding guarded.
- pstack `/maintain-formal-verification-skill` keeps such a check in step with the code.

When a pstack skill is hidden from the catalog, read its `SKILL.md` from the pstack collection directly. Refer to it by name, and copy none of its commands or paths, because they change between releases.

The hunt reports. Ask the user before you change product code, commit a spec, or open a PR, unless they already asked for fixes.

## 1. Scope

Pick one bounded machine: a status field, a queue consumer, a multi-step workflow, a retry loop, a sync between two systems, a deploy or migration. When the user points at a whole repo, list candidates and rank them by the cost of a bug: money movement, external side effects that cannot be undone, and several concurrent writers come first. Tell the user which machine you picked and why.

Try the cheap checks first. Read the transaction and lock boundaries, check the queue's delivery semantics (at-least-once? ordered per key?), or write one test that forces the suspected interleaving. Continue to a model only when the interleavings are too many to settle by hand.

Done when: one machine is named, and the cheap checks did not settle the question.

## 2. Extract the machine

Build the inventory in `references/extraction.md`: state variables, a transition table with guard, trigger, atomicity, and `file:line`, the environment, and a candidate bug list. Writing the machine down often settles a candidate on its own. Mark it settled, with the reason.

Done when: every code path that writes a state variable is a row in the table, and each row's _Atomic?_ is answered from the storage code.

## 3. Model

Write a TLA+ spec that mirrors the **code**, not the design doc. Where the code and the intent disagree, model the code and state the intent as an invariant.

- One action per transition, with its `file:line` in a comment.
- Split each non-atomic read-check-write into separate actions with a program-counter value between them. This is what lets TLC find the interleaving.
- Model the environment as actions: crash between two writes, duplicate delivery, reorder, timeout that actually succeeded, expiry, delete.
- Write each rule the business depends on as an INVARIANT: at most one worker runs a job, money is never moved twice, a deleted record is never written to. For data loss, keep a history variable of everything the system ever held, and assert that nothing in it is lost.
- Keep constants tiny: 2 entities, 2 actors, at most 2 retries. Most race bugs need only 2 actors.
- Model each guard that a past fix added (a lock, a version check, an idempotency key) as a boolean constant, so that you can switch it off. Search git history and migrations for them.

Run the model with pstack `/statechart`. Follow its rules for the spec, the view, and the report.

## 4. Trust the result

A run counts only after these three checks:

- **Fidelity table.** For each action: the code path it mirrors and what it simplifies. Then list what the model leaves out: other writers, isolation level, clock skew, bounds. These limits go in the report.
- **Control.** A second config that switches off the guard you believe makes the code safe must break an invariant. This shows the model is sensitive to that guard.
- **Reachability.** A temporary invariant such as "two writers never overlap" or "a conflict never happens" must break. When it holds, `Init` or a guard is too strict, and the green run means nothing. A small distinct-states count is the same warning.

Treat the first counterexamples as modeling errors until each step is shown to be something the code can do. When an invariant is stronger than what a consumer relies on, restate it as what the consumer relies on, and log that in the modeling notes. Keep every rule the business depends on.

Done when: the control breaks, every reachability check breaks, and each remaining trace maps step by step to `file:line`.

## 5. Confirm

A TLC trace is a bug in the model. Write a failing test that replays it in the real code, one step for each action: interleaved calls, a duplicated webhook, a forced crash between writes. The fastest route is usually the existing test suite, with the database or network mock scripted to return the trace's outcomes in order. A reproduced trace is **confirmed**. Every other trace stays **suspected**, with the reason.

## 6. Report

```markdown
# State-machine review: <machine>

## The machine

<statechart chart + condensed transition table>

## Findings

### 1. <title> (confirmed | suspected)

- Trace: <numbered steps in plain words>
- Code: <file:line for each step>
- Impact: <what goes wrong for users, money, or data>
- Repro: <test name, or why it could not be reproduced>
- Fix idea: <smallest change that closes the trace>

## Checked and safe

<each candidate the model refuted, the guard that makes it safe, and its control result>

## Leads

<suspicions not modeled or not reproduced>

## Modeling notes

<fidelity table, what the model leaves out, constants, state counts>
```

Rank findings by impact. End by asking which findings to fix, and whether to guard any of them with pstack `/create-formal-verification-skill`.

## When the user asks for a fix

- A green spec of a fix is an experiment. It says nothing about the code you then write.
- After the code change, the repro test and the neighboring suites pass. Update the model to mirror the shipped code, rerun it, and confirm that the control still breaks.
- Make the smallest change that closes the trace. Change an invariant only when the user agrees that the business rule was wrong.
