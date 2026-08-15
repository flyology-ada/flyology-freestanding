# ADR 0006: Clean-room compiler tasking compatibility

- Status: accepted
- Date: 2026-08-13

## Context

Ordinary Ada task declarations compiled by GNAT use a compiler-specific
staging and identity interface that the Ada Reference Manual does not define.
Copying GNAT runtime sources would impose a separate licensing boundary and
would make Flyology Freestanding's core architecture harder to review independently.

## Decision

Flyology Freestanding implements the required GNAT 15.3 compiler-facing surface as original
clean-room work. Interface discovery is restricted to Flyology Freestanding-owned probes,
compiler-generated expansion and object metadata, public documentation, and
black-box behavior. GNAT runtime source is neither consulted nor copied.

The compiler-facing predefined units are a compatibility facade. They own no
scheduler or context-switch policy: GNARL semantics delegate task-state changes
to the core runtime, ready ordering to the scheduler instance, and context
transfer to architecture code. Application task creation remains ordinary Ada
syntax; Flyology Freestanding exposes no Spawn, fiber, or parallel task dialect.

The initial tasking capability checkpoint retains terminated bounded TCB and stack slots. It
supports the demonstrated normal activation/master/completion path and fails
closed if compiler-emitted unwind entries are reached. This is not exception
propagation or abnormal cleanup support.

## Consequences

- Every added compiler-facing entity requires an owned two-target probe and an
  exact profile/representation record.
- Compiler upgrades require re-running and reviewing the complete probe suite.
- Clean-room provenance is auditable, but this ADR is an engineering record,
  not legal advice or a warranty about third-party intellectual property.
- synchronization capability must replace fail-closed unwind entries before claiming exception-driven
  task cleanup, abort, or abnormal master semantics.
