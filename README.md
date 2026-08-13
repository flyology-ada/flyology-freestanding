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

## Licensing

Original work is available under either Apache-2.0 or MIT; see [LICENSE-APACHE](LICENSE-APACHE), [LICENSE-MIT](LICENSE-MIT), and [NOTICE](NOTICE). The tracked runtime is a clean-room implementation; external tools and boot artifacts retain their own licenses outside the source tree.
