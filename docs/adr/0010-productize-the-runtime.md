# ADR-0010: Productize the runtime around capabilities

- Status: accepted
- Date: 2026-08-14

## Context

Flyology was developed as a sequence of independently gated milestones. That
made early uncertainty visible and kept each checkpoint reviewable, but the
milestone names have become accidental architecture. Current production builds
assemble sources from `runtime/m3`, `runtime/m4`, `runtime/m5`, and `runtime/m6`;
the principal GNARL semantic facade is named `Flyology.M3_Runtime`; the platform
contract is named `Flyology.M2_Architecture`; target entry assembly still uses
an `m1_entry.S` filename; and demonstrations, structured evidence markers, and
runtime implementation coexist in the same packages.

Those names describe discovery order, not responsibility. Keeping them as the
permanent structure obscures dependencies, makes subtraction unsafe, and makes
it difficult to consume the runtime as a small coherent project.

## Decision

Flyology will migrate, without a big-bang rewrite, to this responsibility graph:

1. the ordinary Ada application depends on the compiler-compatibility facade;
2. the compatibility facade delegates language tasking semantics to the RTS;
3. the RTS delegates state changes to one kernel task-state authority;
4. scheduler policies own ordering and selection but never context transfer;
5. the kernel delegates machine operations through one typed platform contract;
6. architecture implementations own only the target-specific privileged and ABI
   mechanisms; and
7. Limine boot code owns loading, validated machine discovery, and MP handoff.

The intended source and project boundaries are:

```text
src/kernel/       task state, waits, timers, domains, ready queues, dispatcher
src/rts/          activation, masters, abort, rendezvous, protected objects
src/gnarl/        Ada and System compiler-compatibility units
src/abi/          unavoidable C/unwind/allocator ABI boundaries
src/platform/     common contract plus x86_64 and aarch64 implementations
src/boot/limine/  validated Limine protocol and bootstrap handoff
config/           product policy/domain configurations
tests/            host models, compiler probes, target scenarios and support
formal/           SPARK proof projects and TLA+ design models
gpr/              component and image projects
```

The names describe the steady state. Migration may retain existing paths behind
project source directories and narrow forwarding packages, but no new product
API may acquire a milestone name.

### Invariants during migration

- `Flyology.Task_Core` remains the sole production authority for task state,
  current-task ownership, exact waits, ready membership, and context handoff
  until its responsibilities are mechanically split. No parallel replacement
  state machine is permitted.
- Ordinary Ada task declarations remain the only application task-creation
  surface. No public spawn, fiber, or alternate task dialect is introduced.
- Scheduler policy selects; kernel code transfers contexts.
- Voluntary switching and interrupt-time preemption remain distinct machine
  mechanisms feeding the same checked task-state transitions.
- Dense `Core_Id`, Limine processor identity, LAPIC identity, and MPIDR identity
  remain distinct types and mappings.
- Every intermediate commit keeps `main` buildable and preserves applicable
  x86-64/AArch64 SMP1/SMP4 gates.
- A move or rename is behavior-preserving unless its commit explicitly states,
  proves, and tests a semantic change.
- Compiler-facing external names are inventoried before relocation. Compatibility
  aliases are temporary and receive a removal gate.

### Build and product shape

A root Alire crate and GPR project graph will become the supported developer
entry point. Alire selects and records tools; GPR projects express component
source ownership and image composition. Freestanding target images may continue
to require explicit binder, linker-script, firmware, and FAT-image steps, but
those steps must consume project-produced objects rather than reconstructing a
second source graph in shell.

The intended reusable products are a kernel archive, a GNARL/RTS archive, and
target platform objects, composed into a freestanding image. Whether a compiler
predefined unit can reside in a particular archive is decided by an executable
link gate, not assumed from the desired diagram.

### Evidence and history

Milestone reviews, serial-marker meanings, and clean-room discovery records are
historical evidence and are not rewritten to pretend the final structure always
existed. They move, if needed, under a history/evidence namespace with redirects
or links. Current product documentation uses capability names.

Obsolete milestone scaffolding follows a proof-grade subtraction protocol:

1. census callers, external symbols, proof roots, probe references, and gates;
2. quarantine it from supported project source paths;
3. run the full capability gate without it; and
4. delete it only when the evidence demonstrates zero remaining responsibility.

## Migration slices

1. Record this decision and the clean-room evidence schema.
2. Add the Alire/GPR build graph while retaining differential legacy builds.
3. Extract target demonstrations and markers from product packages.
4. Split kernel and RTS monoliths behind their existing typed boundaries.
5. Rename and split platform contracts and target assembly.
6. Consolidate compiler-facing units, probes, and evidence manifests.
7. Replace milestone build/test entry points with capability gates.
8. Quarantine and remove obsolete scaffolding after the full proof, model,
   reproducibility, inspection, and target matrix passes.

Each slice is a reviewed commit. A failed differential gate stops the migration;
it is not papered over by weakening an older test.

## Consequences

For a transition period, the repository contains both historical milestone paths
and the emerging responsibility-based projects. That temporary duplication is
controlled by the migration plan and must decrease after each compatibility
window. The result is a smaller conceptual API, independently buildable layers,
clearer clean-room provenance, and a product whose source layout describes its
actual ownership rather than its chronological development.
