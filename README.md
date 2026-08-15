# Flyology Barebones

Flyology Barebones is a freestanding GNAT Ada tasking runtime for the fixed QEMU x86-64 `q35` and AArch64 `virt` virtual-hardware contracts. It aims to supply the runtime core, full-GNARL tasking integration, SMP dispatcher, synchronization primitives, scheduler policies, and architecture support from which a system can be built. It is not an operating-system distribution.

The first release is not complete. [ROADMAP.md](ROADMAP.md) records the
independently gated capabilities. The runtime is organized around
responsibility-owned components under
[ADR-0010](docs/adr/0010-productize-the-runtime.md); no capability is complete
until its build, proof, review, and QEMU evidence is recorded.

## Product constraints

- Ordinary Ada task declarations and GNARL own language-level tasking semantics.
- x86-64 and AArch64 remain supported together from the first boot capability onward.
- Every applicable QEMU gate covers one and four virtual CPUs.
- SMP, remote rescheduling, and scheduling domains are part of the first-release architecture.
- Networking, storage, filesystems, TLS, framebuffer UI, general ACPI/DTB discovery, and broad physical-server claims are out of scope through dispatching-domain capability.

## Repository map

- `ARCHITECTURE.md` — normative layering and invariants.
- `ROADMAP.md` — capability gates and current status.
- `docs/adr/` — durable design decisions.
- `docs/reviews/` — evidence-based capability reviews.
- `docs/clean-room/` — normative compiler-interface methodology and evidence.
- `docs/primitives.md` — responsibility catalog and boundary of the reusable
  deterministic primitive library.
- `docs/build.md` — Alire primitive-library and freestanding image builds.
- `src/kernel/` — the single concurrent task-state, ready-queue, dispatcher,
  timer, and context-transfer authority (`Flyology.Kernel`).
- `src/rts/` — GNARL lifecycle and language-semantic glue (`Flyology.RTS`).
- `src/gnarl/` — compiler-facing Ada and System predefined-unit facades whose
  exact surface is indexed by the clean-room evidence manifest.
- `src/primitives/` — reusable deterministic Ada/SPARK validation, lifecycle,
  queueing, timing, placement, and scheduling-policy algorithms.
- `src/bootstrap/` — minimal binder, Standard Library, and root `System`
  support required before the full GNARL facade is available.
- `src/abi/` — narrow documented C boundaries for exception unwinding and the
  compiler allocator ABI.
- `src/platform/{x86_64,aarch64}/` — target context, interrupt, timer, memory,
  Limine request, and linker implementations.
- `config/` — named restriction, scheduler-policy, scheduling-domain, and
  product capability selections; configuration is not runtime state.
- `gpr/` — the host primitive-library project, freestanding Ada image project,
  and relocatable no-installed-runtime cross-toolchain configuration.
- `scripts/` — authoritative build, test, proof, and reproducibility entry points.
- `tests/legacy/checkpoints/` — quarantined bootstrap and interrupt-substrate
  checkpoint applications,
  retained temporarily for compatibility gates and never linked by product
  profiles.
- `tests/target/scenarios/` — ordinary-Ada conformance image and behavioral workloads.

Product profiles select configuration views for `gpr/flyology_image.gpr`.
`build-image.sh` orchestrates its Ada objects with the explicit binder,
platform assembly/C, linker, and boot-media steps; capability gates use the same
build, run, and inspection entry points.

## Authoritative gates

- `alr build` builds the host-side `libflyology_primitives.a` from the
  deterministic Ada/SPARK kernel packages. Freestanding images are composed by
  `scripts/build-product.sh ARCH PROFILE` using the pinned per-target Alire
  workspaces, the target GPR project, and explicit binder/link/image steps.
- `scripts/verify-product-build.sh` rebuilds all four product profiles in two
  independent output roots for both targets and requires identical ELF and
  FAT-image hashes.
- `scripts/verify-product-runtime.sh` builds and runs all four product profiles
  on x86-64 and AArch64 at SMP1 and SMP4 through the capability entry points.

- `scripts/verify-bootstrap-minimum.sh` builds and inspects the bootstrap-minimum checkpoint ELF probes.
- `scripts/verify-bootstrap.sh` builds both Limine images, boots each at one and four CPUs, and boots both injected last-chance variants.
- `scripts/verify-bootstrap-reproducible.sh` rebuilds both bootstrap checkpoint ELF and FAT images twice and compares their SHA-256 output.
- `scripts/verify-interrupts.sh` proves and inspects the interrupt-substrate checkpoint core, reproduces both images, and boots both architectures at one and four CPUs.
- `scripts/verify-interrupts-reproducible.sh` rebuilds both interrupt-substrate checkpoint ELF and FAT images twice and compares their SHA-256 output.
- `scripts/verify-tasking.sh` proves and probes the clean-room tasking interface,
  checks independent-output-root reproducibility, context layouts, both ELFs,
  ordinary Ada tasks at one and four CPUs, and repeated SMP4 wake stress.
- `scripts/stress-tasking.sh` repeats the tasking capability SMP4 activation, placement, master, and
  idle/wake gates on both architectures.
- `scripts/test-tasking-models.sh` exhausts the bounded placement and transition
  spaces and checks full-capacity FIFO and activation/master sequences.
- `scripts/verify-tasking-reproducible.sh` rebuilds both tasking capability ELF and FAT images in
  two separate output roots and compares their SHA-256 output.
- `scripts/verify-synchronization.sh` proves and exhausts the deterministic synchronization
  and allocator kernels, runs the native allocator contention and
  abort-versus-exception black-box gates, probes the clean-room synchronization capability compiler
  surface, rebuilds and inspects both images, boots both CPU counts, and
  repeats the SMP4 integration paths.
- `scripts/stress-synchronization.sh` repeatedly executes the ordinary-Ada delay,
  protected-entry, rendezvous, priority, abort, termination, and reclamation
  paths at SMP4 on both architectures.
- `scripts/test-synchronization-models.sh` enumerates wait/wake/timeout/abort orders and
  dependent-task abort closure, and checks exact queues, timer cancellation,
  priorities, ceilings, and clock arithmetic with a pinned edge count and
  state hash.
- `scripts/verify-preemption.sh` proves and probes the standard dispatching-policy
  surface, reproduces and inspects FIFO and round-robin images, verifies full
  context/unwind layouts, boots both architectures and CPU counts under both
  policies, and runs bounded SMP4 timer/IPI preemption stress.
- `scripts/stress-preemption.sh` repeatedly executes higher-priority timer preemption,
  remote IPI/SGI preemption, complete register/status/FP-SIMD preservation on
  every core, nonblocking interrupt ingress under remote RTS-lock contention,
  Ready-task priority tail requeue, FIFO non-rotation, and equal-priority
  round-robin progress at SMP4.
- `scripts/test-preemption-policy.sh` checks the deterministic policy, budget, and
  ready-position kernel against its pinned edge count and hash.
- `scripts/verify-domains.sh` proves and model-checks scheduling-domain creation,
  placement, and isolation; probes the clean-room Ada domain interface;
  reproduces and inspects both target images; boots both CPU counts; and runs
  bounded SMP4 heterogeneous-policy and all-core preemption stress.
- `scripts/stress-domains.sh` repeats the SMP4 domain inheritance, FIFO isolation,
  round-robin progress, and per-core complete-context preemption gates on both
  architectures.
- `scripts/test-domain-model.sh` checks the bounded deterministic domain
  creation/admission model against its pinned edge count and hash.
- `scripts/test-tla-models.sh` runs bounded TLC exploration of scheduler/
  preemption ingress, scheduling-domain isolation, and exact wake/timeout/abort
  arbitration, with pinned state counts; see
  [docs/formal-models.md](docs/formal-models.md).
- `scripts/verify-formal-models.sh` runs repository hygiene, GNATprove, every
  bounded Ada host model, and the TLA+ models as one fail-closed formal gate.
- `scripts/verify-preemption-reproducible.sh` rebuilds all four preemption capability ELF/FAT pairs in
  two independent output roots and compares their SHA-256 output.
- `scripts/prove.sh` proves the deterministic SPARK validation kernel.
- `scripts/check.sh` performs shell/static and repository hygiene checks.

## Licensing

Original work is available under either Apache-2.0 or MIT; see [LICENSE-APACHE](LICENSE-APACHE), [LICENSE-MIT](LICENSE-MIT), and [NOTICE](NOTICE). The tracked runtime is a clean-room implementation; external tools and boot artifacts retain their own licenses outside the source tree.
