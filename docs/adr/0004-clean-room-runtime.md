# ADR-0004: Implement the runtime clean-room

- Status: accepted
- Date: 2026-08-12

## Context

Compiler-matched GNAT runtime sources carry `GPL-3.0-or-later WITH GCC-exception-3.1`. The exception is useful for generated target code, but copying runtime units creates a licensing boundary for the runtime library itself. Flyology Freestanding's original work is intended to remain uniformly MIT/Apache-2.0.

The Ada Reference Manual defines language semantics and much of package `System`, but GNARL/GNULL names and compiler-facing calling conventions are GNAT implementation interfaces. Full ordinary-Ada tasking therefore still requires compiler compatibility beyond the ARM.

## Decision

Flyology Freestanding implements the runtime clean-room and copies or adapts no GNAT runtime source, body, comment, or test. Allowed implementation inputs are:

- the Ada Reference Manual and Ada Issues;
- public GNAT user/reference documentation describing externally observable behavior;
- compiler-generated expanded Ada, binder output, ALI metadata, symbol diagnostics, and representation information produced from Flyology Freestanding-owned test programs; and
- black-box differential and conformance tests written from the language specification.

Every compiler-facing unit records how its required surface was discovered under `docs/clean-room/`. Names and signatures required for interoperability are treated as compatibility interfaces; implementation structure and algorithms remain independently designed.

GCC source archives may remain pinned as toolchain provenance, but scripts and contributors must not use their runtime sources to implement Flyology_Freestanding. If clean-room compatibility proves infeasible for a required semantic, the project stops and records the blocker rather than silently importing GNAT code.

## Consequences

The runtime can remain under the repository's MIT/Apache-2.0 terms, subject to legal review of compatibility-interface questions. Development cost and conformance risk increase substantially. Ordinary-Ada compiler expansion, binder closure, ACATS-style tests, and explicit symbol/interface inventories become primary evidence.
