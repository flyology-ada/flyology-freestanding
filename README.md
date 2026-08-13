# Flyology Barebones

Flyology Barebones is a freestanding GNAT Ada tasking runtime for the fixed QEMU x86-64 `q35` and AArch64 `virt` virtual-hardware contracts. It aims to supply the runtime core, full-GNARL tasking integration, SMP dispatcher, synchronization primitives, scheduler policies, and architecture support from which a system can be built. It is not an operating-system distribution.

The first release is not complete. Work proceeds through the independently gated milestones in [ROADMAP.md](ROADMAP.md); no milestone is complete until its build, proof, review, and QEMU evidence is recorded.

## Product constraints

- Ordinary Ada task declarations and GNARL own language-level tasking semantics.
- x86-64 and AArch64 remain supported together from the first boot milestone onward.
- Every applicable QEMU gate covers one and four virtual CPUs.
- SMP, remote rescheduling, and scheduling domains are part of the first-release architecture.
- Networking, storage, filesystems, TLS, framebuffer UI, general ACPI/DTB discovery, and broad physical-server claims are out of scope through M6.

## Repository map

- `ARCHITECTURE.md` — normative layering and invariants.
- `ROADMAP.md` — milestone gates and current status.
- `docs/adr/` — durable design decisions.
- `docs/reviews/` — evidence-based milestone reviews.
- `scripts/` — authoritative build, test, proof, and reproducibility entry points (introduced during M0).
- `runtime/` — original runtime/platform implementation (introduced incrementally).
- `runtime/bootstrap/` — original minimal compiler-compatibility runtime used by early milestones.

## Authoritative gates

- `scripts/verify-m0.sh` builds and inspects the M0 ELF probes.
- `scripts/verify-m1.sh` builds both Limine images, boots each at one and four CPUs, and boots both injected last-chance variants.
- `scripts/verify-m1-reproducible.sh` rebuilds both M1 ELF and FAT images twice and compares their SHA-256 output.
- `scripts/verify-m2.sh` proves and inspects the M2 core, reproduces both images, and boots both architectures at one and four CPUs.
- `scripts/verify-m2-reproducible.sh` rebuilds both M2 ELF and FAT images twice and compares their SHA-256 output.
- `scripts/verify-m3.sh` proves and probes the clean-room tasking interface,
  checks independent-output-root reproducibility, context layouts, both ELFs,
  ordinary Ada tasks at one and four CPUs, and repeated SMP4 wake stress.
- `scripts/stress-m3.sh` repeats the M3 SMP4 activation, placement, master, and
  idle/wake gates on both architectures.
- `scripts/test-m3-models.sh` exhausts the bounded placement and transition
  spaces and checks full-capacity FIFO and activation/master sequences.
- `scripts/verify-m3-reproducible.sh` rebuilds both M3 ELF and FAT images in
  two separate output roots and compares their SHA-256 output.
- `scripts/verify-m4.sh` proves and exhausts the deterministic synchronization
  kernels, probes the clean-room M4 compiler surface, rebuilds and inspects
  both images, boots both CPU counts, and repeats the SMP4 race scenarios.
- `scripts/stress-m4.sh` repeatedly executes the ordinary-Ada delay,
  protected-entry, rendezvous, priority, abort, termination, and reclamation
  paths at SMP4 on both architectures.
- `scripts/test-m4-models.sh` enumerates wait/wake/timeout/abort orders and
  checks exact queues, timer cancellation, priorities, ceilings, and clock
  arithmetic with a pinned edge count and state hash.
- `scripts/prove.sh` proves the deterministic SPARK validation kernel.
- `scripts/check.sh` performs shell/static and repository hygiene checks.

## Licensing

Original work is available under either Apache-2.0 or MIT; see [LICENSE-APACHE](LICENSE-APACHE), [LICENSE-MIT](LICENSE-MIT), and [NOTICE](NOTICE). The tracked runtime is a clean-room implementation; external tools and boot artifacts retain their own licenses outside the source tree.
