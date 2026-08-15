# ADR-0010: Productize the runtime around capabilities

- Status: accepted
- Date: 2026-08-14

## Context

Flyology was developed as a sequence of independently gated experiments. That
made early uncertainty visible and kept each capability reviewable, but the
development sequence became accidental architecture: source ownership,
compiler facades, platform contracts, demonstrations, structured markers, and
build entry points were indexed by chronology instead of responsibility.

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
src/abi/          narrow Ada compiler ABI facades and unavoidable C unwinder
src/platform/     common contract plus x86_64 and aarch64 implementations
src/bootstrap/    binder and root predefined-unit substrate
boot/             Limine image configuration
config/           product policy/domain configurations
tests/            host models, compiler probes, target scenarios and support
formal/           SPARK proof projects and TLA+ design models
gpr/              component and image projects
```

These names describe the steady state. Maintained paths, symbols, markers,
configuration, probes, and reviews use capability or responsibility names;
numbered development-stage identifiers are rejected by repository hygiene.

### Invariants

- `Flyology.Kernel` remains the sole production authority for task state,
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

A root Alire crate and aggregate GPR project are the supported host-library
entry point. They build the deterministic `src/primitives/` packages as
`libflyology_primitives.a`. Freestanding Ada compilation is owned separately by
`gpr/flyology_image.gpr`, using the relocatable no-installed-runtime compiler
protocol in `gpr/flyology_cross.cgpr` and concrete compiler paths from the
pinned cross workspaces. The composition shell retains compiler binder
generation, architecture assembly/C, linker scripts, pinned `libgcc`, firmware,
and FAT-image construction because those operations are part of the checked
target ABI. It consumes project-produced Ada objects and is not a second source
or runtime implementation graph.

The reusable library is intentionally the deterministic primitive layer. The
concurrent kernel, GNARL/RTS facade, foreign ABI, and platform objects are
composed into a freestanding image and are not advertised as independently
linkable archives until an executable link gate proves such a boundary useful.

### Evidence and history

Capability reviews, serial-marker meanings, and clean-room discovery records
preserve the observed facts, commands, hashes, and limitations while using the
current responsibility names. Current product documentation and executable
interfaces use the same capability vocabulary.

Obsolete experimental scaffolding follows a proof-grade subtraction protocol:

1. census callers, external symbols, proof roots, probe references, and gates;
2. quarantine it from supported project source paths;
3. run the full capability gate without it; and
4. delete it only when the evidence demonstrates zero remaining responsibility.

## Implemented slices

1. Record this decision and the clean-room evidence schema.
2. Add the Alire/GPR deterministic-library build while retaining target gates.
3. Extract target conformance scenarios and markers from product packages.
4. Establish `Flyology.Kernel` as the sole concurrent state authority and
   `Flyology.RTS` as GNARL semantic glue.
5. Consolidate platform contracts and target assembly by architecture.
6. Consolidate compiler-facing units, probes, and evidence manifests.
7. Replace chronological build/test entry points and ABI names with capability
   gates and stable product profiles.
8. Preserve unique bootstrap/interrupt boundary applications under
   `tests/platform/` and reject them from supported product source paths.
9. Replace the procedural Ada source/object graph with a target GPR project and
   a relocatable freestanding compiler configuration.

Each slice was committed independently. A failed differential gate stopped the
reorganization; it was not papered over by weakening an existing test.

## Consequences

The repository now has one responsibility-based product graph and a quarantined
set of bootstrap/interrupt compatibility applications. The result is a smaller
conceptual API, an independently buildable deterministic library, clearer
clean-room provenance, and a product whose source layout describes actual
ownership rather than chronological development. Checkpoint applications remain
only while their isolated compatibility gates add evidence not covered by the
product matrix; they are never linked into a supported product profile.
