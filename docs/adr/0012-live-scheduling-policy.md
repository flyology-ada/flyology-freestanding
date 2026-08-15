# ADR-0012: Make live scheduling policy an atomic per-core configuration

- Status: accepted
- Date: 2026-08-15

## Context

ADR-0011 makes the Ada partition pragma and binder metadata authoritative for
the policy needed before library-level task objects can be elaborated. That
solves initial configuration, but it must not freeze scheduling for the life of
the image. A kernel may need to change the default globally, change one
dispatching domain, or temporarily override one CPU without rebuilding its
partition.

The ready scheduler already owns ordering while `Flyology_Freestanding.Kernel` owns task
state, budgets, timers, and context transfer. Adding a second runtime scheduler
object or rewriting binder globals would split those authorities. Programming
a remote core's local timer directly would also cross the existing per-core
hardware ownership boundary.

## Decision

Flyology Freestanding exposes an original, non-compiler-facing `Flyology_Freestanding.Scheduling` API for
live policy changes and observations. The initial binder-selected policy is
copied into effective per-core configuration before application elaboration.
Thereafter:

- a global change replaces every used domain default and every active core's
  effective policy;
- a domain change replaces that domain's default and every member core's
  effective policy;
- a CPU change replaces only that core's effective policy and leaves its domain
  default unchanged.

The complete target set is validated by a SPARK transition model before any
production mutation. The kernel commits policy, quantum, and task-budget
changes atomically under the one RTS lock. FIFO clears affected budgets.
Round robin gives an affected Running task one fresh complete quantum and
clears non-running retained budgets so the next dispatch starts a fresh
quantum. Ready ordering is unchanged because both supported algorithms use the
same fixed-priority/FIFO ready policy; only equal-priority preemption and budget
accounting differ.

After unlocking, the RTS publishes a kick to every affected core. The target
dispatcher consumes the changed configuration and locally reprograms its own
timer. A policy operation never selects a task or transfers a context.

Domain membership and task placement remain immutable. A later domain change
intentionally replaces earlier per-core overrides inside that domain; a later
global change replaces every override. This gives deterministic last-writer
scope semantics without maintaining an inheritance graph as a second state
authority.

## Consequences

Applications can change policy through typed Ada calls while continuing to use
ordinary tasks and standard dispatching domains. Invalid FIFO/nonzero-quantum
and round-robin/zero-quantum pairs are rejected at the public boundary. The
binder remains authoritative only for the pre-elaboration initial value.

The live API is a Flyology Freestanding extension, not evidence of a GNAT compiler-facing
interface or an implementation of every Ada dispatching policy. Adding another
algorithm requires extending the deterministic model, TLA+ transitions,
scheduler semantics, architecture prompts, and target evidence together.
