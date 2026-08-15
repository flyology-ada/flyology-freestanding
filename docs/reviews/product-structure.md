# Product-structure review — responsibility-owned runtime

## Status

In progress. Commit `87a4d9d050520dedb1e1a244193e386ded8464bf`
closed the responsibility naming, clean-room inventory, deterministic-library,
formal, reproducibility, and runtime-matrix slices. A subsequent completion
audit found that the freestanding target still reconstructed its source/object
graph procedurally in `scripts/build-image.sh`; only the deterministic primitive
library was expressed as a GPR project. The current target-project slice fixes
that structural defect, but this review remains open until the exact committed
tree has completed the full reproducibility/runtime matrix and the remaining
monolith/subtraction audit is dispositioned.

Maintained product code is indexed by responsibility: deterministic primitives,
one concurrent kernel, GNARL semantic glue, compiler facades, narrow foreign ABI
code, and per-architecture platform implementations. Tests, probes,
configuration, clean-room evidence, and verification entry points use capability
names. Numbered development-stage identifiers are absent from maintained paths,
content, product symbols, structured markers, artifacts, and profiles.

The earlier evidence below remains valid for its reviewed commit, but it is not
final product-structure closure. The current work adds the target GPR graph and
removes the duplicated shell Ada graph. Closure still requires a fresh exact-tree
review/gate matrix and a final census of the large kernel/RTS and quarantined
checkpoint responsibilities.

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
artifact is `flyology.elf`. Profiles are `tasking`, `preemptive-fifo`,
`preemptive-round-robin`, and `domains`. The Alire/GPR host product is
`libflyology_primitives.a`. No public spawn, fiber, scheduler-control, wait-token,
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
Reference Manual, public documentation, Flyology-owned compiler expansion and
binder output, diagnostics, symbol/ALI/representation/disassembly observations,
and black-box tests. This is an engineering provenance statement, not legal
advice or an intellectual-property warranty.

## Exact-tree gates

All commands below completed successfully after commit
`87a4d9d050520dedb1e1a244193e386ded8464bf` and before this review file was
created.

- `alr build --release` built `libflyology_primitives.a` with SHA-256
  `0af8eaa0259e3b2ffb3d9d865b061802110ac87b3bb28f5662e78b2888b22be1`.
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

Pinned target compilers reported GNAT-FSF 15.3.0. Both QEMU binaries reported
10.2.0. Coverage remains the fixed emulated-machine contracts, not physical
hardware or hosted CI.

| Architecture | Profile | ELF SHA-256 | FAT SHA-256 |
| --- | --- | --- | --- |
| x86-64 | tasking | `5b118eaa58cdddf6955bea7bf28eaf56d0c5ca21873332e6a00ee559e8e234a4` | `587e974b519b32cbc6086f4b072acf44b5811983fec448c0ae33690d1c2cbfa7` |
| x86-64 | preemptive-fifo | `a8fd0c95cb71b788df32f4d99269c84794cfa8dcccac8ebfc6520e6e73aa93f5` | `57bd2622928ee20d668477bcff7000b3085daf2d68494df632e83645543adc99` |
| x86-64 | preemptive-round-robin | `d5caa90ca4852848882bf9d0ec7af380fcb41c8bc00fb16f5dc1b194d20bbe26` | `18e91f55cfd0585154330616de7f9dd7ca1524f2cdc56cd87c1c26d55bc21652` |
| x86-64 | domains | `46a283fb74cfffd047b9cafa8bc59524a2f54cb9c0a85809336bf8c8cce12229` | `4ecffa58b33e7baf888b41c1aaaf85206e844a67dab99e5bb1e161dc749dcb88` |
| AArch64 | tasking | `84a305cde94460734456f234e0ed92c95e2d25564c21e0f8dfeb5e145a0145bb` | `12fee95740bf2c5b8013e4340e7c46304d3ab09ff82e9aaa21b75898081f4dbe` |
| AArch64 | preemptive-fifo | `f08b4dd6432d1f4735e51e055d4a002fbafaa9ec2fd608a4c721ab1f919bf8f5` | `7c46e0e43da77f293295beb15ba47e90de4e137bcd31c6d72edad35451aaef71` |
| AArch64 | preemptive-round-robin | `022b32766842910310d5d48dc66f6d3c03ebdcad51d189c6cc353d35b4ed50e2` | `2f8b6f8c2936a0936a481d7a6c4701fda7199d9b2efea528ed0ebb99d09ba1f5` |
| AArch64 | domains | `dc0520a2967ccba01b7677c04dd2384ab5eb06bb821190783dde95de557c3275` | `bff798979dcadda80640b35000ce334d665b5ec7fc24f54b598810b56cc52711` |

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

Disposition: fixed in the current target-project slice. `gpr/flyology_image.gpr`
owns the selected source roots, ordinary-Ada main, and assembly-exported
validation roots; GPRbuild discovers the remaining Ada dependency closure.
`gpr/flyology_cross.cgpr` describes the compiler protocol without inventing an
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

## Residual limits

- The primitive archive is an internal `0.1.0-dev` engineering library; package
  API stability is not promised before the first release.
- The concurrent kernel, GNARL facade, C allocator/unwinder, assembly, MMIO, and
  QEMU virtual hardware remain outside the SPARK proof boundary.
- TLA+ models explore design-level bounded state spaces and are not a refinement
  proof of the Ada/C/assembly implementation.
- Same-host, two-output-root reproducibility is demonstrated; independently
  provisioned builders and hosted CI are not claimed.
- Hardware support remains the pinned QEMU `q35` and `virt` contracts. Physical
  hardware, other firmware, other compiler releases, and broader Ada semantics
  remain separate work.

The target-project blocker is resolved. Product-structure completion remains
open pending exact-tree aggregate evidence and the final responsibility/subtraction
audit described above.
