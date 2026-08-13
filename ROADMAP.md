# Roadmap

Status vocabulary is deliberately strict: `not started`, `in progress`, `blocked`, or `complete (evidence link)`. Partial implementation is never described as milestone completion.

| Milestone | Status | Required outcome |
| --- | --- | --- |
| M0 | complete ([review](docs/reviews/m0.md)) | Pinned clean-room builder produces and inspects freestanding x86-64 and AArch64 ELF images reproducibly. |
| M1 | complete ([review](docs/reviews/m1.md)) | Limine boots Ada elaboration and brings all requested CPUs online on both architectures at `-smp 1/4`. |
| M2 | complete ([review](docs/reviews/m2.md)) | Policy-neutral per-core dispatch, checked task transitions, voluntary contexts, interrupt frames, and remote reschedule substrate. |
| M3 | not started | Ordinary Ada task activation, identity, stacks, masters, termination, pinned placement, and automatic placement across cores. |
| M4 | not started | Cross-core protected objects, rendezvous, delays, priority/ceiling behavior, exact wakeups, termination, abort races, and reclamation. |
| M5 | not started | Non-preemptive and preemptive standard-Ada-aligned policies, timer/IPI preemption, complete contexts, and no-yield progress test. |
| M6 | not started | Immutable scheduling-domain admission and heterogeneous policies demonstrated on four cores on both architectures. |

Each milestone closes only after:

1. authoritative build/test/proof/static scripts pass;
2. both architectures and all applicable CPU counts pass bounded machine-checked tests;
3. fresh reviews cover architecture, hardware, Ada/GNARL semantics, SMP/atomics, ABI/context preservation, scheduler separation, memory/lifecycle, proof soundness, security, diagnostics, portability claims, and subtraction;
4. blocking review findings are fixed and the review cites the exact rerun evidence.
