# Roadmap

Status vocabulary is deliberately strict: `not started`, `in progress`,
`blocked`, or `complete (evidence link)`. Partial implementation is never
described as capability completion.

| Capability | Status | Required outcome |
| --- | --- | --- |
| product structure | complete ([review](docs/reviews/product-structure.md)) | Responsibility-owned runtime/library layout, stable capability profiles, exact clean-room inventories, and zero numbered development-stage names in maintained artifacts. |
| bootstrap-minimum checkpoint | complete ([review](docs/reviews/bootstrap-minimum.md)) | Pinned clean-room builder produces and inspects freestanding x86-64 and AArch64 ELF images reproducibly. |
| bootstrap checkpoint | complete ([review](docs/reviews/bootstrap.md)) | Limine boots Ada elaboration and brings all requested CPUs online on both architectures at `-smp 1/4`. |
| interrupt-substrate checkpoint | complete ([review](docs/reviews/interrupts.md)) | Policy-neutral per-core dispatch, checked task transitions, voluntary contexts, interrupt frames, and remote reschedule substrate. |
| tasking capability | complete ([review](docs/reviews/tasking.md)) | Ordinary Ada task activation, identity, stacks, masters, termination, pinned placement, and automatic placement across cores. |
| synchronization capability | complete ([review](docs/reviews/synchronization.md)) | Cross-core protected objects, rendezvous, delays, priority/ceiling behavior, exact wakeups, termination, abort races, and reclamation. |
| preemption capability | complete ([review](docs/reviews/preemption.md)) | Non-preemptive and preemptive standard-Ada-aligned policies, timer/IPI preemption, complete contexts, and no-yield progress test. |
| dispatching-domain capability | complete ([review](docs/reviews/dispatching-domains.md)) | Immutable scheduling-domain admission and heterogeneous policies demonstrated on four cores on both architectures. |

Each capability closes only after:

1. authoritative build/test/proof/static scripts pass;
2. both architectures and all applicable CPU counts pass bounded machine-checked tests;
3. fresh reviews cover architecture, hardware, Ada/GNARL semantics, SMP/atomics, ABI/context preservation, scheduler separation, memory/lifecycle, proof soundness, security, diagnostics, portability claims, and subtraction;
4. blocking review findings are fixed and the review cites the exact rerun evidence.
