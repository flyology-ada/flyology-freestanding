# bootstrap checkpoint review — sequential Ada and SMP boot substrate

- Review date: 2026-08-12
- Closing gate: `scripts/verify-bootstrap.sh`
- Reproducibility gate: `scripts/verify-bootstrap-reproducible.sh`
- Proof gate: `scripts/prove.sh`

## Evidence

The closing gate runs static repository checks, proves the deterministic kernel, twice builds and compares both ELF/FAT images, inspects final ELF and every Limine request qword, then performs six bounded QEMU boots. Normal boots require exactly one Ada-main marker, exactly one marker for each dense core, exactly one final pass, and no failure or panic marker. Negative boots start from an ordinary Ada `raise Program_Error`, require the compiler-generated rcheck symbol in the probe object, and halt through the last-chance diagnostic without a success marker.

| Target | Normal CPU counts | Negative boot | Reproducible ELF SHA-256 | Reproducible FAT SHA-256 |
| --- | --- | --- | --- | --- |
| x86-64 `pc-q35-10.2` | 1, 4 | SMP1 last chance | `eaa4d94dccb7d5ca0dbb0670ce879a66ef6985fb94a61689375dc89bf2bf98c4` | `294958454b438d062b0e260847f59e8d67d73a0f831892b941fa39293549f3e7` |
| AArch64 `virt-10.2` / GICv3 | 1, 4 | SMP1 last chance | `9eafa9bcc2464db1a576c2ee0555b1f01efd2eea1c11925b24435f0e9c09b6bd` | `16ccc3b69043265857818029f5f9972554a0ccb38e1bc3e2d0a38ad728f267f0` |

GNATprove proves 42 checks, including postconditions connecting each C-exported, boot-executed validator to its arithmetic model. The boot path invokes these Ada validators for every memory entry, every entry pair, every topology identity pair, and each AArch64 page-table address translation before AP release.

## Findings and dispositions

### Blocker — UART was first accessed through an absent identity mapping

QEMU exception tracing showed an AArch64 data abort at physical PL011 address `0x09000030`. Limine's four-level mappings did not retain that identity map.

Disposition: fixed with a private TTBR0 three-level table for only the pinned QEMU PL011 2 MiB window. Page-table physical addresses are validated by the proved executable-translation function before TTBR installation.

### Blocker — PL011 memory attributes were inconsistent

The first private descriptor accidentally selected Normal memory, and a later correction briefly reused Limine's MAIR slot 0, which would have retyped existing mappings.

Disposition: fixed. The descriptor selects `AttrIndx=7`; startup assigns Device-nGnRnE to MAIR slot 7 and leaves slot 0 untouched. The final dual-CPU-count AArch64 rerun passed after this exact change.

### Blocker — topology validation accepted duplicate identities

The initial scan located the BSP and allocated dense IDs but did not reject duplicate MP pointers, processor IDs, LAPIC IDs, or MPIDRs.

Disposition: fixed before AP release. Pairwise validation rejects pointer reuse and calls the proved identity predicate. Each CPU also independently compares its hardware register identity with its record before publishing online. MPIDR comparison uses the architectural affinity fields rather than non-affinity status bits.

### Blocker — memory and HHDM validation was incomplete

Initial assembly checked only partial sums and did not reject overlapping entries. The original SPARK predicates were disconnected from boot.

Disposition: fixed by C-convention Ada/SPARK functions called directly from both entries. They validate nonzero complete physical and translated extents, memory types 0 through 8, pairwise disjointness, and bounded counts. All exported result/model equivalences prove. Alignment is not required because the pinned Limine protocol permits unaligned extents.

### High — base revision and external inputs were partially checked

Startup originally checked only the base tag's unsupported word; disk construction checked only Limine file existence.

Disposition: fixed. Both architectures require loaded revision 6 and response revision 0. Image construction rechecks architecture-specific Limine hashes. QEMU, four firmware files, mtools, and GNU timeout are version/digest checked at use.

### High — last-chance evidence bypassed compiler-generated checks

The first negative variant called the ABI directly from assembly.

Disposition: replaced by the tracked Ada `raise Program_Error` probe. The gate requires its sole undefined reference to be `__gnat_rcheck_PE_Explicit_Raise`, then observes the terminal diagnostic in QEMU. bootstrap checkpoint explicitly uses `No_Exception_Propagation`; it does not claim unwinding or Ada exception propagation.

### High — compiler checks and warnings were broadly suppressed

Disposition: target Ada now uses overflow checking, warnings-as-errors, and section-level dead-code elimination. Only the warning category that restates the explicit bootstrap checkpoint no-propagation restriction is disabled. The generated binder unit retains its generated-code warning mode.

### High — request ABI inspection checked only table size

Disposition: `scripts/inspect-bootstrap.sh` validates ELF target/type/entry, program headers, absence of hosted/TLS/dynamic/RWX state and relocations, required and undefined symbols, all record offsets, and all 50 final request-table qwords including identifiers, revisions, response slots, stack size, paging values, and per-architecture MP flags.

## Perspective review

- Architecture and boundaries: GNARL is not present or claimed. Limine supplies load/mapping/MP descriptions only. Common deterministic validation now executes in Ada/SPARK; architecture assembly retains response traversal, privileged state, MMIO, and handoff.
- Systems/hardware: x86 requests and validates x2APIC, installs a terminal IDT, establishes `GS_BASE`, verifies APIC ID, and switches stacks. AArch64 validates EL1, enables FP/SIMD, installs VBAR, establishes `TPIDR_EL1`, verifies MPIDR affinity, installs Device MMIO, and switches stacks.
- Ada/compiler semantics: binder-generated `adainit` runs an owned elaboration body observed by the Ada main; `adafinal` runs afterward. The clean-room evidence lists the exact supported binder and terminal diagnostic surface.
- SMP concurrency and atomics: AP `goto_address` publication is a release store on AArch64 and relies on x86 TSO aligned store ordering. Online publication is release/acquire, and the final marker cannot precede any online marker. The diagnostic lock is atomic and serialized.
- Interrupt/ABI/context: bootstrap checkpoint vectors are deliberately terminal diagnostics, not resumable interrupt frames. x86 switches to an emergency diagnostic stack after entry; AArch64 clears the lock and reports on the current owned stack. Complete asynchronous frames and independent interrupt stacks are interrupt-substrate checkpoint work and are not claimed here.
- Scheduler separation: no scheduler exists in bootstrap checkpoint. APs halt after the startup barrier, so no policy or context-transfer API has leaked into boot.
- Memory safety/lifecycle: no allocator or task lifecycle exists yet. Boot extents, translations, count capacities, table geometry, and core stack indices are checked; allocation remains interrupt-substrate checkpoint work.
- SPARK soundness: 42 checks prove without axioms, ghost hardware state, disabled bodies, or false-positive annotations. Privileged instructions and concurrent hardware mutation remain outside SPARK.
- Security/fail-closed: unsupported revisions, paging, x2APIC, CPU counts, null records, duplicate topology, invalid extents/types/overlap, translation overflow, and input hash drift halt or fail the build/test.
- Verification/observability: all QEMU runs are bounded and assert unique behavioral markers, not process exit. The last-chance negative path and ordinary happy paths are both observed on both architectures.
- Portability/claims: coverage is only QEMU 10.2.0 `pc-q35-10.2` and `virt-10.2` under TCG with the pinned UEFI inputs. AArch64 rejects non-EL1 entry; it does not claim general EL2 normalization or physical server support.
- Licensing: tracked runtime code is original MIT/Apache-2.0 work. Limine request constants are isolated 0BSD compatibility data. No GNAT runtime source is tracked or used as implementation input.

## Subtraction review

No public task, spawn, fiber, scheduler, interrupt-registration, allocator, or device API was introduced. The duplicate architecture request records are retained because the MP flag and assembler syntaxes differ; their final bytes are checked from one script. A shared generated record source could reduce duplication later, but adding a generator now would increase the trusted build surface.

The early general SPARK validation package remains because its types and predicates are the basis for interrupt-substrate checkpoint state and topology work. Only the four C-exported boot validators are linked by garbage collection. The AArch64 TTBR0 table is the smallest mapping that makes diagnostics valid under Limine's mapping contract; a general VM subsystem was explicitly not added.

## Residual risks and unsupported claims

- Terminal bootstrap checkpoint exception vectors are not complete resumable frames and have no nested-fault recovery. This is an explicit interrupt-substrate checkpoint gate, not an bootstrap checkpoint context-preservation claim.
- bootstrap checkpoint supports terminal compiler checks only under `No_Exception_Propagation`; ordinary Ada handlers, unwinding, secondary stacks, and exception occurrences remain absent.
- The in-tree negative gate reproduces `Program_Error`; other discovered rcheck forwarding names remain compatibility observations rather than independently gated conformance cases.
- APs enter Flyology-owned records/stacks and halt. There is no dispatcher, idle wakeup, IPI/SGI, or parallel application execution yet.
- The fixed AArch64 UART address is part of `virt-10.2`; no DTB discovery is claimed.
- Shellcheck was unavailable on this host; `sh -n`, repository hygiene, target warnings-as-errors, ELF inspection, proof, reproducibility, and QEMU gates did run.

## Decision

bootstrap checkpoint is complete. The final exact-tree `scripts/verify-bootstrap.sh` rerun succeeded after this review was added, ending in `FLYOLOGY:BOOTSTRAP:GATE:PASS`; its hashes are recorded above. This decision does not authorize or imply any interrupt-substrate checkpoint tasking, interrupt-frame, or scheduling claim.
