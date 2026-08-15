# Live scheduling policy review

- Date: 2026-08-15
- Reviewed commit: `42102b66f43e83c5bcdbc1feb8ea19ff45bc7c07`
- Reviewed tree: `9993bbc70ca1b594aa1a769bf3de6a5bec3ecb78`
- Result: GO

## Scope

This review covers the original `Flyology_Freestanding.Scheduling` application API, atomic
global/domain/CPU replacement semantics, effective per-core configuration,
budget/timer integration, admission snapshots, the deterministic SPARK model,
the extended TLA+ scheduling-domain model, bounded host enumeration, and the
ordinary-Ada target workload. It does not claim additional Ada dispatching
policies, dynamic domain membership, hardware, or a compiler-facing GNAT
interface.

## Findings and dispositions

No blocker or high finding remains. Review found and fixed the following before
the reviewed commit was created:

1. `Policy_Of` originally read policy and quantum in two RTS-lock transactions.
   It now obtains one coherent pair under one lock, so a concurrent update
   cannot produce a torn public record.
2. The RTS domain snapshot initially reconstructed the old fixed FIFO/RR
   mapping. It now reads the kernel's current domain default, so task admission
   after a live change does not reintroduce stale policy metadata.
3. The first TLA+ global action changed the unused secondary-domain default,
   unlike production's used-domain rule. The transition now preserves an
   uncreated domain's initial default and matches the implementation/ADR.
4. The first target assertion compared only the returned policy for FIFO. It
   now compares the complete returned policy/quantum pair.
5. A metadata-only target check did not prove that switching changed execution.
   The final gate holds two equal-priority CPU-bound tasks behind FIFO, changes
   the live CPU to round robin, and requires both to progress. The SMP4
   controller changes a remote CPU, making the marker depend on the request and
   IPI/SGI path.
6. Kernel domain slice and tick-quantum arrays were write-only copies. They are
   removed. Domain policy remains the creation/admission default; effective
   per-core policy/slice/ticks are the sole dispatcher configuration. A
   compile-time check ties the model's four-core capacity to the kernel.

## Authority and concurrency

The standard pragma and binder value remain authoritative for the initial
policy required before library-level task objects elaborate. The live API is a
post-startup Flyology Freestanding extension and never rewrites binder globals.

`Flyology_Freestanding.Kernel` remains the sole mutable scheduling/task authority. One
SPARK-validated target set is committed under the global RTS lock. FIFO clears
affected budgets; round robin gives an affected Running task a fresh full
quantum and clears every other affected retained budget. The RTS releases the
lock before kicking each affected core, and only the target core programs its
local timer. Scheduler policy still selects; it never transfers a context.

Global replacement updates every used domain and active core. Domain
replacement updates that default and all member cores. CPU replacement changes
only one effective core. Domain membership, placement, priority, and existing
ready ordering remain unchanged.

## Clean-room and proof boundary

`Flyology_Freestanding.Scheduling` is original application API and is listed in the
preemption clean-room inventory only to keep implementation provenance
complete. It is not a predefined unit and supplies no evidence about GNAT
runtime source. Compiler-facing initial-policy facts remain derived from the
Ada RM and owned dual-target binder/source probes recorded in the policy
interface document.

GNATprove FSF 16.1 at level 2 proved 543/543 generated checks across 23
deterministic units, including all six scheduling-configuration-model entities,
with zero unproved, justified, assumed, warning, or error results. This proves
the pure transition's validity, exact selected-core frame, and rejection
preservation. It does not prove the concurrent kernel/RTS wrappers, public API
glue, atomics, assembly, timer hardware, or QEMU.

The host policy campaign pins 2,531 serialized decisions and hash
`11691030413894487372`. TLC explored the enlarged domain/policy state graph in
17,035,809 generated / 683,040 distinct states without a safety counterexample.
This remains bounded design exploration, not source-code refinement.

## Subtraction review

`REMOVE` — the write-only `Domain_Slices` and `Domain_Quanta` state and their
array types were removed before the reviewed commit.

- Fact: exact-tree `rg` finds no remaining symbol, and the compiler accepts no
  unused replacement state.
- Semantic owner: immutable domain membership means each dispatch and task
  budget consumes the effective core configuration; domain policy alone is
  sufficient as the retained default used by domain snapshots.
- Blast radius: the state was private to `Flyology_Freestanding.Kernel`; no public,
  compiler-facing, serialized, or persistent representation changed.
- Verification: the exact-tree aggregate proof/model/reproducibility/target
  gate passed after removal.
- Entropy delta: two mutable arrays and two private array types are gone; no
  adapter or compatibility layer replaced them.

The remaining surfaces are justified: four application operations (three
scope setters and one coherent CPU query), one deterministic transition model,
domain defaults, and effective per-core policy/slice/tick values. Exact-tree
reference census finds production callers for every internal transition/query.
No public spawn/fiber API, scheduler object, alternate ready queue, or second
task-state authority was added.

## Exact gates

`scripts/verify-domains.sh` passed on the reviewed tree and includes:

- repository/clean-room/project hygiene;
- 543/543 GNATprove checks and all pinned Ada host models;
- all four pinned TLA+ models;
- tasking, synchronization, policy, and domain dual-target probes;
- x86-64 and AArch64 interrupt-layout and unwind checks;
- independent-output-root reproducibility:
  - x86-64 ELF `1d9c80592907558a70a4ae6a486b4adb90b6f69c01d5dbc1f307c7ebfa34231d`;
  - x86-64 FAT `ed13cb5b0816c4e3e033c934a6b666a9f7febf386182be160da846160658afd5`;
  - AArch64 ELF `aaaed968c7f400f542a5e69e7504e19c73fd115cee21fbcfed301a3d18dd1e1f`;
  - AArch64 FAT `2e50441f312fcf7ef061df76b011e1b1fc8d1c11546121d59023c5023fdca16e`;
- x86-64 `q35` and AArch64 `virt`, each at SMP1 and SMP4;
- five additional SMP4 domain/live-policy runs per architecture; and
- final `FLYOLOGY:DOMAINS:GATE:PASS`.

Every target cell requires exactly one `FLYOLOGY:SCHEDULING:LIVE_POLICY:PASS`
and `FLYOLOGY:SCHEDULING:LIVE_EXECUTION:PASS` and rejects failure/panic output.

## Residual boundary

Only FIFO within priorities and round robin within priorities are implemented.
Per-priority policy mixtures, EDF, runtime domain membership changes, policy
inheritance graphs, hardware targets, and general-purpose hosted portability
remain outside this slice. Any new algorithm must extend the model, TLA+
transitions, scheduler/quantum semantics, documentation, and both architecture
gates together.
