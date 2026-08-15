# Architecture

This document is normative unless superseded by an accepted ADR.

## Layer ownership

1. **GNARL** owns Ada language tasking semantics: activation, masters, rendezvous, protected objects, abort, delay, task attributes, priorities, and termination.
2. **Task primitives and core dispatcher** (`Flyology.Kernel`) own atomic
   task-state transitions, block-and-unlock, exact wakeups, current-task
   ownership, context transfer, preemption control, interrupt return, remote
   reschedule requests, and idle entry.
3. **Scheduler policy** owns eligibility ordering, ready structures, priorities/quantum accounting, and next-task selection. It never switches contexts.
4. **Platform code** in `src/platform/<architecture>/` owns exception frames,
   local timers, interrupt controllers, IPIs/SGIs, privileged registers,
   machine-state normalization, linker layout, and the minimum assembly
   required by entry/context ABIs.
5. **Limine** owns loading, initial mappings/stacks, machine description, and MP bootstrap handoff only.

Dependencies point downward through typed contracts. Architecture code does not choose policy; policy code does not manipulate exception frames; GNARL does not directly program interrupt controllers.

The compiler-facing predefined units in `src/gnarl/` delegate Ada tasking
semantics to `Flyology.RTS`. `Flyology.RTS` is semantic glue, not a second
task-state or ready-queue authority: it validates GNARL lifecycle operations
and commits them through `Flyology.Kernel`.

Large runtime bodies are decomposed with Ada subunits by semantic responsibility.
Subunits inherit their parent's private state and do not create another package
API or mutable authority. In particular,
`flyology-rts-domain_operations.adb` owns dispatching-domain aliases, creation,
freezing, queries, and the domain snapshot used by activation planning; the
state it mutates remains declared once in the `Flyology.RTS` parent body.
`flyology-kernel-domain_operations.adb` owns the corresponding checked kernel
configuration, creation commit, core ownership, and task-domain queries while
the domain/core/task arrays remain declared once in the `Flyology.Kernel`
parent body.
`flyology-rts-rendezvous_operations.adb` owns FIFO entry-call admission,
conditional and timed calls, accept, normal/exceptional completion, and the
currently supported selective-wait surface. It inherits the RTS call table and
exact-wait authority; the subunit introduces no second queue or public API.

The minimal binder and root predefined-unit substrate lives in
`src/bootstrap/`. The only C production sources live in `src/abi/`, where they
implement the documented compiler allocator and exception-unwinding ABIs; C is
not used for scheduler or task-state policy.

Restriction sets and compile-time policy/domain selections live under
`config/`. They select implementations and compiler behavior; they never own
mutable scheduling or task state.

The responsibility-based product source and build structure is defined by
[ADR-0010](docs/adr/0010-productize-the-runtime.md). The state-owning kernel is
in `src/kernel/`, the reusable deterministic algorithms are in
`src/primitives/`, and the GNARL semantic runtime is in `src/rts/`. Numbered
development-stage names are forbidden in maintained paths, product symbols,
configuration, tests, and evidence records; capability names are the only
supported vocabulary.

## Identity and topology

`Core_Id` is a validated dense value in `0 .. CPU_Count - 1`. Limine `processor_id`, x86 LAPIC/x2APIC IDs, and AArch64 MPIDR values remain distinct hardware identities stored in topology records. Mapping validation rejects duplicates, capacity overflow, missing BSP identity, and unsupported CPU counts before AP release.

## Task state and wakeups

The task-primitives boundary provides one atomic contract for:

- entering/leaving the runtime critical section;
- publishing the current task's blocked state while releasing its protecting lock;
- making an exact task ready;
- changing effective/active priority;
- registering and cancelling delay/deadline events;
- requesting local or remote rescheduling; and
- deferring preemption while runtime critical depth is nonzero.

Blocking and waking use a checked generation/token scheme so an old wake cannot satisfy a later wait and publication cannot race past the wake. A global RTS spinlock is acceptable until measured contention justifies sharding; application tasks are still allowed to execute in parallel.

## Contexts and preemption

Voluntary ABI-boundary switching saves the architecture's ABI-preserved state. Asynchronous interrupt-time preemption captures a complete resumable instruction state, including status/control and FP/SIMD state once enabled. The mechanisms have distinct representations and entry paths, but both validate and commit through the same task-state transition kernel.

Preemption-disable depth is per core. A reschedule received while depth is nonzero is recorded and serviced at the outermost leave boundary.

## Scheduling domains

A scheduling domain owns one policy instance, ready structures, preemption configuration, admitted tasks, and eligible cores. Cores are policy-neutral. Initial domain membership is immutable. `CPU => n` retains standard Ada specific-CPU meaning and must also satisfy domain eligibility; `Not_A_Specific_CPU` permits placement only among the task's domain-eligible cores.

No cross-domain migration is supported through dispatching-domain capability because priority interpretation, pending timers, blocked entry queues, protected actions, and ownership transfer lack defined semantics.

## Boot order

The BSP validates Limine base/protocol responses, memory map, HHDM, topology, capacities, and platform contract; constructs global/per-core state and owned stacks; completes required Ada elaboration; then publishes AP `goto_address` values with release ordering. AP stubs normalize privilege and FP state, install vector state, establish the per-core pointer, switch to an owned stack, publish online with release ordering, join the startup barrier, and enter dispatcher/idle. APs never call unelaborated Ada.

Initial targets are x86-64 QEMU `q35` under UEFI with x2APIC requested and four-level paging, and AArch64 QEMU `virt` under UEFI with GICv3 and four-level paging. The fixed `virtualization=off` AArch64 contract is validated as EL1 entry, and FP/SIMD is explicitly enabled before Ada/context code uses it. Supporting an EL2 entry would require a separate, tested normalization path.

## Memory

Allocation begins with checked memory-map normalization and bounded page/bump allocators. Every extent validates type, full-range overflow, alignment, HHDM conversion, and capacity. Exhaustion at Ada allocation boundaries raises `Storage_Error`. Reclamation is introduced when dynamic task destruction requires it; a general VM subsystem is out of scope.

## Verification boundary

SPARK covers deterministic validation and policy kernels: extents/alignment, dense topology, task-state legality, wake generations, ready-queue invariants, deadline/quantum arithmetic, and domain admission. MMIO, privileged instructions, raw interrupt entry, foreign ABIs, and concurrently changing hardware remain outside SPARK behind small typed contracts.

## Clean-room runtime boundary

The tracked runtime is original Flyology work. It implements the compiler-facing GNARL/GNULL architecture without copying or adapting GNAT runtime source. Interface discovery is limited to the Ada Reference Manual, public compiler documentation, compiler-generated expanded Ada/binder output, symbol/ALI diagnostics, and black-box conformance tests. Evidence is recorded under `docs/clean-room/`. GCC/GNAT source archives may be pinned for toolchain provenance but are not runtime implementation inputs.

The normative discovery and upgrade procedure is
[`docs/clean-room/methodology.md`](docs/clean-room/methodology.md), and the
machine-readable evidence index is
[`docs/clean-room/interfaces.toml`](docs/clean-room/interfaces.toml). Compiler
interface shape, implementation, target semantics, and formal proof are separate
claims and require separate evidence.
