# ADR-0001: Preserve full GNARL layering

- Status: accepted
- Date: 2026-08-12

## Context

Flyology Freestanding must support ordinary Ada task declarations and the full GNARL architecture on SMP. A convenient public spawn/fiber API or a Ravenscar-only runtime would reduce initial implementation effort but change the language/runtime contract and foreclose required semantics.

## Decision

GNARL remains the owner of Ada tasking semantics. A private task-primitives/core-dispatcher layer supplies atomic state transitions, block-and-unlock, wakeups, current-task ownership, context transfer, preemption control, interrupt return, remote rescheduling, and idle. Scheduler policies only manage eligibility and select the next task. Architecture code owns machine mechanisms. Limine is limited to boot loading, initial machine data, and MP handoff.

No public spawn/fiber dialect is introduced. Ravenscar and Jorvik may later be valid profiles, but neither constrains the product architecture.

## Consequences

The first ordinary-Ada task demonstration arrives later than it would with a custom fiber API. In exchange, test programs exercise the intended language surface and policy variation does not leak into GNARL or context-switch code.
