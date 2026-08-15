# ADR-0011: Derive the initial scheduling policy from consumer Ada source

- Status: accepted
- Date: 2026-08-15

## Context

The first productized application workflow reused repository conformance
profile names such as `tasking` and `preemptive-fifo`. That made scheduling
semantics appear to be a shell-build property even though Ada defines the
partition-wide policy through `Task_Dispatching_Policy`. It also created a
second scheduler-configuration package that had to agree with GNAT binder
globals.

It is tempting to remove both the pragma and the binder policy and require the
application to call something like `Initialize_Tasking (Policy, Domains)`.
That call is too late if it is made from the application procedure. A task
*type* declaration is inert, but a library-level task *object* is created and
activated as part of its package's elaboration. Binder-controlled library-unit
elaboration happens before the application procedure is entered, so such a
task may need placement and ready-queue policy before user initialization code
can run.

The runtime must consequently establish a valid initial policy for the system
dispatching domain before any task-owning library unit elaborates. Requiring
every such unit to call or depend on a Flyology-specific initialization API
would be order-sensitive and could be bypassed by an ordinary predefined or
third-party unit. It would also create a second, non-Ada convention for a
property already represented in compiler-generated partition metadata.

## Decision

Independent applications declare `Task_Dispatching_Policy` in Ada source. The
consumer builder requires that declaration, binds the application, and derives
the architecture interrupt-to-dispatch composition from the binder's `F` or
`R` value. The runtime consumes that same binder value directly; it has no
parallel Flyology scheduler-configuration package. An unspecified GNAT
round-robin quantum maps to the checked Flyology default of 10 ms.

Repository profiles remain explicit conformance-matrix fixtures. A blank
binder policy remains available only to the cooperative repository checkpoint,
not to independent application crates.

The binder is authoritative only for this initial pre-elaboration policy. It
does not permanently own scheduling configuration. Once elaboration and
dispatcher startup establish the live task set, checked Flyology runtime
operations may change global, domain, or per-core policy at synchronized
dispatcher boundaries. Those transitions neither rewrite binder globals nor
alter the meaning of `Task_Dispatching_Policy`; they are an explicit Flyology
extension over a standard initial partition configuration.

## Consequences

Policy choice is visible in reviewed consumer Ada and cannot silently disagree
with the compiler-generated partition metadata. Adding a new scheduling
algorithm requires compiler/clean-room evidence or an explicitly named
Flyology extension; it cannot be smuggled in as a build flag. Live domain
policy transitions are a separate runtime capability and do not change the
meaning of this initial partition declaration.
