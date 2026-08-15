# Product-structure review — responsibility-owned runtime

## Status

Complete for the product-structure capability. The reviewed implementation is
commit `3e34545eefee1abfd682e05c407291cef0732763`, Git tree
`e19830fafe52c24915e115060b5be8bc50ab7ad1`. The closing review/roadmap commit
changes documentation only.

Maintained product code is indexed by responsibility: deterministic primitives,
one concurrent kernel, GNARL semantic glue, compiler facades, narrow foreign ABI
code, and per-architecture platform implementations. Tests, probes,
configuration, clean-room evidence, and verification entry points use capability
names. Numbered development-stage identifiers are absent from maintained paths,
content, product symbols, structured markers, artifacts, and profiles.

Git history intentionally retains the chronological filenames used by the
earlier spikes so review hashes and clean-room provenance remain auditable. The
maintained Git tree, working tree, generated product paths, content, symbols,
markers, and profiles contain no numbered development-stage names. Rewriting
history is not part of the product surface and would invalidate those records.

## Reviewed structure

- `src/primitives/` is the reusable deterministic Ada/SPARK library.
- `src/kernel/` is the sole mutable task-state, ready, wait, timer, dispatcher,
  and context-handoff authority.
- `src/rts/` owns GNARL lifecycle and synchronization semantics without a
  parallel task-state machine.
- `src/gnarl/` contains only compiler-facing Ada and System facades.
- `src/abi/` contains the documented allocator and unwind C boundaries.
- `src/platform/{x86_64,aarch64}/` contains target-specific entry, context,
  interrupt, timer, memory, Limine-request, and linker mechanisms.
- `config/` selects restrictions, scheduler policy, domains, and stable product
  profiles; it owns no mutable runtime state.
- `tests/target/scenarios/` contains ordinary-Ada conformance clients rather than
  runtime implementation.
- `tests/platform/` contains isolated minimal compiler-link, binder/boot, and
  interrupt-frame boundary applications and is rejected from every supported
  product source path.

The stable image entry point is `scripts/build-product.sh ARCH PROFILE`; the
artifact is `flyology-freestanding.elf`. Profiles are `tasking`, `preemptive-fifo`,
`preemptive-round-robin`, and `domains`. The Alire/GPR host product is
`libflyology_freestanding_primitives.a`. No public spawn, fiber, scheduler-control, wait-token,
or alternate task-creation API is present.

## Clean-room audit

The clean-room manifest is schema version 2. Each interface set records its
compiler/targets, observation record, owned probe, authoritative gate, semantic
status, proof boundary, implementation root, and an exact tracked
implementation-unit inventory under `docs/clean-room/inventory/`.

`scripts/check-clean-room.sh` rejects missing/untracked inventory entries,
duplicate identifiers, unknown statuses, incomplete interface records, and
missing evidence/gate paths. Probe scripts still enforce generated expansion,
symbol, relocation, representation, and call-order observations. The manifest
does not turn shape evidence into a semantics claim or deterministic-model proof
into proof of concurrent Ada, C, assembly, MMIO, or hardware.

No GNAT runtime source was introduced. The accepted evidence remains the Ada
Reference Manual, public documentation, Flyology Freestanding-owned compiler expansion and
binder output, diagnostics, symbol/ALI/representation/disassembly observations,
and black-box tests. This is an engineering provenance statement, not legal
advice or an intellectual-property warranty.

## Exact-tree gates

All commands below completed successfully on the reviewed implementation commit
and tree identified above.

- `alr build --release` built `libflyology_freestanding_primitives.a` with SHA-256
  `36ba618da57f0b22b9b659f7bce26a8824603a01d7c3e2d16e32b230e4801914`.
- `scripts/verify-formal-models.sh` ended in
  `FLYOLOGY:FORMAL_MODELS:PASS`: GNATprove FSF 16.1.0 proved 476/476 checks at
  level 2; the tasking, synchronization, preemption, and domain host models
  retained their pinned edge/hash results; TLC retained the pinned scheduler,
  domain, and wait-arbitration state counts.
- `scripts/verify-product-build.sh` ended in `FLYOLOGY:PRODUCT:GATE:PASS` after
  two independent output-root builds of every architecture/profile ELF and FAT
  pair produced identical SHA-256 hashes.
- `scripts/verify-product-runtime.sh` ended in
  `FLYOLOGY:PRODUCT:RUNTIME_GATE:PASS` after profile-aware ELF inspection and 16
  bounded QEMU cells: x86-64 `q35` and AArch64 `virt`, each profile at SMP1 and
  SMP4. Every runner rejected failure/panic markers and required its causal
  capability markers.
- The newly project-owned exception-boundary probe built on both targets and
  passed x86-64/AArch64 SMP1/SMP4 before its integration into the authoritative
  synchronization gate. The full tasking products then passed inspection,
  unwind validation, and both CPU counts on each architecture.

Pinned target compilers reported GNAT-FSF 15.3.0. Both QEMU binaries reported
10.2.0. Coverage remains the fixed emulated-machine contracts, not physical
hardware or hosted CI.

| Architecture | Profile | ELF SHA-256 | FAT SHA-256 |
| --- | --- | --- | --- |
| x86-64 | tasking | `0cd01b8e2a9b77b194c44a7c78fb87d15a3b533e7cfea9dcf3d9a208d9f3a101` | `425e3ee665acbb7f10f764eb0eacdcf62cef3a76f35732f0b10e9bb56c4fc0ab` |
| x86-64 | preemptive-fifo | `44e006629f7a528b82dc2cb22c84899a6727459a2f917366e62c0141ab0b42c3` | `be59d8463680f2521464cdb44baeff89693871b0ee2e4ede37a0aa51f68462f0` |
| x86-64 | preemptive-round-robin | `c200ada177bb1605cb22c25ff780988ddc4271dd64034f52ad83e5e45865de45` | `c45042dbaf2909c2b739d1d7f46b4483be0cdd62ff271ebc0452a1c2194c039a` |
| x86-64 | domains | `05adc78a9e0f8c2b6dce2f8c8d4957fac71dc870281b6121ca1d92fac3306d4e` | `983af068c6e442a8cb28689e72503031b66fa4d4c35e1c8b3b5af5cdd9ce6dba` |
| AArch64 | tasking | `379ca8b1bb8e820a99e63c8a8d050e4d08698d96002bb65c1afebb98b4f7ad77` | `871eb089cd32212baa5c5f85395c9a1d7d1fb71d3a3e27f4a5141ae42d1587e8` |
| AArch64 | preemptive-fifo | `ae97e2691c16331241ae0f9110dbf815fba7e1d9d088e316557ffa6711889a32` | `336afe05ee17e7bdc150c06b2000870a49f1e1fb720aa81e65930cae842560a3` |
| AArch64 | preemptive-round-robin | `cde497f4488d0c82975ec7f25cbe883fdd6b735a38c95b573fcff755292ecb4e` | `ea2ebbdd7ab80f8c27d243841793e543f79b60c027ed3ba5b3232aa9c63f0ced` |
| AArch64 | domains | `5b9dca32a73d9c32043ba594e0f825650c1b0db1609def0483b43b1b722e44e2` | `60e25f99a329a26ad979dc01ba61d72683075fd58b6d750ae2bbd27ec12a6b13` |

## Findings and dispositions

### Blocker — chronology leaked into maintained filenames, ABI names, and gates

Disposition: fixed across responsibility-owned source moves, stable private ABI
names, capability markers/profiles, and the final filesystem normalization.
Repository hygiene now rejects both numbered path components and embedded
numbered-stage tokens in tracked content.

### High — clean-room claims referenced broad directories

Disposition: fixed by schema-versioned implementation inventories. Adding a new
compiler facade no longer silently enlarges an existing evidence claim.

### High — compatibility wrappers duplicated the stable image interface

Disposition: removed. Product and capability gates now call the stable
build/inspect/run entry points with named profiles. Narrow bootstrap/interrupt
builders remain isolated because they verify distinct early-boundary behavior,
not because they are alternate product builds.

### Blocker — the freestanding source graph remains explicit shell

Disposition: fixed in the current target-project slice. `gpr/flyology_freestanding_image.gpr`
owns the selected source roots, ordinary-Ada main, and assembly-exported
validation roots; GPRbuild discovers the remaining Ada dependency closure.
`gpr/flyology_freestanding_cross.cgpr` describes the compiler protocol without inventing an
installed runtime or embedding local tool paths. The shell produces a sorted
response file from project objects and retains only binder, assembly/C, raw
linker, `libgcc`, firmware, and FAT-image orchestration. Repository hygiene
rejects reintroduction of a shell `compile_ada` source graph.

### Medium — compatibility checkpoint applications remain tracked

Disposition: reclassified as platform boundary verification, not legacy product
scaffolding. The census found unique minimal compiler linkage, binder
elaboration/last-chance, and complete interrupt-frame responsibilities that the
full product image cannot isolate. The applications now live under
`tests/platform/`; product project hygiene proves they are absent from supported
source paths and rejects reintroduction of `tests/legacy/`.

### Medium — rendezvous semantics remain embedded in the RTS lifecycle body

Disposition: fixed by the responsibility-owned
`flyology_freestanding-rts-rendezvous_operations.adb` subunit. Entry-call admission,
conditional/timed waits, FIFO acceptance, exceptional completion, and selective
wait remain inside the single RTS state and lock authority, but no longer make
task lifecycle and master cleanup share one implementation file.

## Residual limits

- The primitive archive is an internal `0.1.0-dev` engineering library; package
  API stability is not promised before the first release.
- The concurrent kernel, GNARL facade, synchronized allocator address facade,
  C unwinder, assembly, MMIO, and QEMU virtual hardware remain outside the
  SPARK proof boundary. The allocator state engine was subsequently migrated
  into the proved primitive library without changing these ownership boundaries.
- TLA+ models explore design-level bounded state spaces and are not a refinement
  proof of the Ada/C/assembly implementation.
- Same-host, two-output-root reproducibility is demonstrated; independently
  provisioned builders and hosted CI are not claimed.
- Hardware support remains the pinned QEMU `q35` and `virt` contracts. Physical
  hardware, other firmware, other compiler releases, and broader Ada semantics
  remain separate work.

The target-project blocker and final responsibility/subtraction audit are
resolved. Product structure is complete for the bounded first-release runtime;
the residual limits above remain explicit product limits rather than hidden
closure work.
