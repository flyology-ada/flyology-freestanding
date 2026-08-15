# Source-selected initial scheduling review

- Date: 2026-08-15
- Reviewed commit: `7959ed6b5b5aa0a43c5ece796876de59d9a0f572`
- Result: GO

## Scope

This review covers the consumer scheduling input, binder-derived architecture
composition, initial RTS policy validation, clean-room policy probes, removal
of the parallel scheduler-configuration packages, and the independent Alire
application workflow. It does not review live runtime policy transitions;
those are the next separately committed slice.

## Findings and dispositions

No blocker or high finding remains.

The implementation review found and fixed three issues before the reviewed
commit was created:

1. FIFO initially accepted an unnecessary `-1` time-slice sentinel. The RTS
   now accepts exactly zero for binder policy `F`; the sentinel remains valid
   only for source-selected round robin, where it maps to the documented 10 ms
   Flyology Freestanding default.
2. The root README still described a consumer profile option. It now describes
   source-selected policy and keeps repository profile names confined to the
   conformance matrix.
3. The project hygiene script passed while emitting errors for staged file
   removals. Its maintained-content scan now uses the Git worktree-aware grep
   boundary and remains fail-closed for numbered-stage names.

## Initial-policy boundary

ADR 0011 records why an application procedure cannot be the sole tasking
initializer. A task type declaration is inert, but a library-level task object
can be created and activated during binder-controlled library-unit elaboration,
before the application procedure runs. The system domain therefore needs an
initial policy before user initialization code can execute.

The standard `Task_Dispatching_Policy` pragma remains the consumer declaration.
The generated binder character is the single initial-policy representation
consumed by both image composition and the RTS. Repository ADC files and binder
time-slice flags remain conformance fixtures, not consumer configuration.

## Clean-room evidence

The policy interface remains derived from the Ada RM and Flyology Freestanding-owned source
probes; no GNAT runtime source was consulted. The exact reviewed commit passed
`scripts/probe-preemption-policy.sh` with both pinned GNAT 15.3 cross compilers.
It established:

- source FIFO -> binder policy `F`, time slice `0`;
- source round robin -> binder policy `R`, unspecified slice `-1`;
- repository FIFO/RR configurations retain their pinned historical binder
  values.

This is interface-shape evidence, not a proof of concurrent scheduler or
interrupt semantics.

## Subtraction review

`REMOVE` — the three `Flyology_Freestanding.Scheduler_Configuration` views and their build
directory selector are removed.

- Fact: an exact-tree `rg` census finds no remaining package reference or
  `FLYOLOGY_FREESTANDING_SCHEDULER_CONFIG_DIR` consumer; only the hygiene rejection pattern
  names the retired surface.
- Fact: commit `79f4ff5` introduced the package to replace milestone-numbered
  configuration with a responsibility name. ADR 0011 supersedes that rationale:
  the generated binder metadata already carries the responsibility-owned
  initial policy, so retaining a second package would recreate disagreement
  risk.
- Blast radius: the removed units were internal selected source views, not an
  Alire library API or compiler-facing GNARL unit. Repository profiles now
  select only their ADC/scenario/evidence composition.
- Verification: the project/clean-room hygiene gate, dual-target source probe,
  exact two-target consumer reproducibility/QEMU gate, and strict FIFO product
  build/QEMU cell passed.
- Reversibility: the removal is restored by reverting one focused commit; no
  serialized state or persistent format changed.
- Entropy delta: three duplicate Ada configuration units, one GPR external,
  two shell environment controls, and consumer `--profile` state are removed.

Under the proof-risk subtraction tolerance, no additional exported or
serialized surface is proposed for deletion in this slice.

## Exact gates

- `scripts/check.sh` -> `FLYOLOGY:CHECK:PASS`
- `scripts/probe-preemption-policy.sh` ->
  `FLYOLOGY:PREEMPTION:POLICY_PROBE:PASS`
- `scripts/verify-minimal-example.sh` -> reproducible x86-64/AArch64 ELF/FAT
  builds and `FLYOLOGY:EXAMPLE:MINIMAL:GATE:PASS`
- `scripts/build-product.sh x86_64 preemptive-fifo`
- `scripts/run-product.sh x86_64 1 preemptive-fifo` ->
  `FLYOLOGY:PRODUCT:RUN:PASS:x86_64:SMP1:preemptive-fifo`

The deterministic SPARK policy kernels were not changed by this slice, so the
GNATprove campaign was not rerun and this review makes no new proof claim.

## Residual boundary

The binder is authoritative only for the pre-elaboration initial policy. Live
global, domain, and per-core changes require a checked runtime transition API,
atomic scheduler/timer updates, target tests, and their own proof and review.
