# Extract the machine

Build this inventory before you write TLA+. The spec can be only as good as the inventory.

## State variables

Collect everything that says where an entity is in its life:

- Status enums and `state` columns.
- Boolean flags, such as `is_published` or `archived`.
- Nullable timestamps, such as `completed_at`, where null means "has not happened".
- External state: a third-party API's view, another service's copy, a cache, a queue.
- **Time.** Records valid for a period (leases, tokens, invites, trials, reservations) change state when the clock passes, with no code writing anything. Find what acts on expiry: a cron job, a check at read time, or nothing.
- **Deletion.** A hard delete is a move to a "gone" state. It can strand references, queued jobs, and webhooks.

The real state is the product of all of these. Note the combinations that the code assumes cannot happen, such as `completed_at` set while `status = 'queued'`.

## Transitions

Make one row for each code path that writes a state variable:

| Transition | Guard (from)    | Writes                         | Trigger    | Atomic?                 | Location            |
| ---------- | --------------- | ------------------------------ | ---------- | ----------------------- | ------------------- |
| Claim      | status = queued | status := running, worker := w | queue poll | no: SELECT, then UPDATE | `jobs/worker.py:88` |

- **Guard**: what the code checks, not what it should check. A missing check is a candidate.
- **Trigger**: user action, webhook, cron, queue message, timeout, admin tool, migration.
- **Atomic?**: answer from the storage code. A read-check-write outside one transaction or lock is several steps that can interleave, and most race bugs come from here. A conditional `UPDATE ... WHERE version = $expected` is a compare-and-set. A row or advisory lock serializes writers. The isolation level decides what a second statement sees. Note where ids and sequence numbers are drawn: a value drawn at insert but visible only at commit lets a reader's cursor skip it.
- **Reachable?**: before you model a path, check that production takes it. Feature flags, fallbacks, and undeployed migrations can make a path dead.

## Environment

Messages delivered twice, out of order, or never. A crash between two writes. Two workers at once. A retry after a timeout that actually succeeded.

## Candidates

Draw the machine as a Mermaid `stateDiagram-v2`, then list candidates:

- States with no way out, or that nothing can reach.
- Guards into one state that are missing, or weaker than the others.
- Reachable flag combinations that no code handles.
- Two writers to one field with no coordination.
- Expiry that nothing enforces. A deleted entity that something can still reach.
- Internal states exposed through an API, or clients able to request an illegal transition.

## Evidence from production and history

- **Logs.** An audit log, a transitions table, an event stream, or per-state timestamps show what already happened. Look for transitions missing from your table, states reached with no legal path, and entities stuck in non-terminal states. A hit here beats any model. Ask the user before you query anything outside a dev environment.
- **Git.** Search commits and migrations for races that were already fixed: a lock, a version check, an idempotency key. Each one becomes a boolean constant in the model, so that the report can say "safe because of X, and the model breaks without X".
