# bootstrap-minimum checkpoint review — reproducible toolchain and images

- Review date: 2026-08-12
- Repository state: pre-initial-commit review; the closing commit records this exact tree
- Host: Apple Silicon macOS 26.5.2 / Darwin 25.5.0
- Gate: `scripts/verify-bootstrap-minimum.sh`
- Proof: `scripts/prove.sh`

## Evidence

The authoritative image gate built each target twice into independent output directories and compared the files byte for byte. It then checked ELF class, target, type, entry, RX/RW program headers, absence of RWX and hosted/dynamic/TLS sections, required entry/Ada symbols, and an empty undefined-symbol set.

| Target | Compiler | ELF entry | SHA-256 |
| --- | --- | --- | --- |
| x86-64 | `x86_64-elf-gcc (GNAT-FSF-builds) 15.3.0` | `0x100000` | `9d0f927bbf430d19a0904752175fb294d66b721fb15415ce494ae65bb0568644` |
| AArch64 | `aarch64-elf-gcc (GNAT-FSF-builds) 15.3.0` | `0x40000000` | `6e4ef3c742b05b3cd16a80748727a7cd91205fbb3272cf8846fd8263b12eea1d` |

`GNATprove FSF 16.1.0` completed `Success: all checks proved (16 checks)` for the initial deterministic validation kernel. The proof covers checked extent arithmetic, Ada CPU/Core conversion, task-state transition legality, and wake-generation increment. The generated invocation header is in the ignored build output at `build/proof/gnatprove/gnatprove.out`.

External inputs and checksums are pinned in `docs/external-inputs.md`. The target compilers intentionally have no default runtime. `src/bootstrap/system.ads` is the independently discovered clean-room minimum: an empty package declaration, which is the complete compiler-required surface for the owned bootstrap-minimum checkpoint no-op probe on both targets. Evidence is recorded under `docs/clean-room/`.

## Findings and dispositions

### Superseded blocker — derived GNAT source created a licensing boundary

Evidence: the first bootstrap `System` adaptation was derived from a GNAT runtime unit, which would place runtime source under GPLv3 with the GCC Runtime Library Exception and require a separate licensing subtree.

Disposition: superseded at user direction. The adaptation and entire GNAT-derived subtree were deleted. ADR-0004 requires a clean-room runtime under MIT/Apache-2.0. An independently isolated agent proved that the owned bootstrap-minimum checkpoint no-op requires only an empty `System` declaration on both targets; that strictly smaller result replaced all previously assumed target parameters.

### High — proof found invalid 256-core count conversion

Evidence: the first successful phase-3 proof reported range checks in both CPU/Core contracts. `CPU_Count` permits 256 while `Core_Id` ends at 255, so converting the count itself to `Core_Id` was invalid even though CPU-to-core conversion subtracts one.

Disposition: fixed by expressing eligibility as `Ada_CPU (Core + 1) <= Ada_CPU (Count)`. The full proof rerun proves all 16 checks.

### High — first links attempted unsafe program geometry

Evidence: `--fatal-warnings` rejected an implied executable stack on x86-64 and an RWX load segment on AArch64.

Disposition: fixed with explicit RX/RW `PHDRS`, `-z noexecstack`, and gate checks that reject RWX segments.

### Medium — Alire command working directory was initially wrong

Evidence: `alr -C toolchains/... exec` changed the process directory, so the compiler could not locate repository-relative runtime sources.

Disposition: fixed in `scripts/toolchain.sh`, which resolves the repository root from its own absolute path and restores it before executing the target command.

### Medium — bootstrap-minimum checkpoint entry addresses are diagnostic link addresses, not a memory contract

The images are freestanding executable-link probes, not Limine boot images. The entry addresses must not become an HHDM, load-address, or KASLR assumption. bootstrap checkpoint replaces the bootstrap entry/link contract with Limine-compatible loading and validated response consumption.

### Medium — bootstrap-minimum checkpoint does not exercise binder elaboration

The exported Ada subprogram demonstrates target Ada compilation and linkage but not binder startup. This is allowed by the bootstrap-minimum checkpoint exit gate; binder elaboration is an explicit bootstrap checkpoint requirement and remains unclaimed.

## Perspective review

- Architecture/boundaries: bootstrap-minimum checkpoint contains only target entry, one no-op Ada unit, a bootstrap `System`, and deterministic validation. It introduces no task API and preserves the full-GNARL decision in ADR-0001.
- Systems/hardware: ELF targets, entries, program headers, non-executable stack intent, and undefined symbols are machine checked. No boot/hardware behavior is claimed yet.
- Ada/GNARL: the bootstrap is explicitly sequential, original, and not presented as GNARL. ADR-0004 makes compiler expansion/binder probes and black-box conformance the interface source for later full GNARL/GNULL compatibility.
- SMP/atomics: only identity/state arithmetic exists; no concurrent behavior is claimed. The CPU/Core mapping boundary is proved.
- Interrupt/ABI/context: architecture entries obey stack alignment and call a C-convention Ada symbol. Complete contexts are not present or claimed.
- Scheduler separation: the normative architecture forbids scheduler-driven context transfer; bootstrap-minimum checkpoint has no scheduler implementation to review.
- Memory/lifecycle: no allocator exists. Extent overflow logic is proved, but allocation remains future work.
- SPARK soundness: 16 checks prove with no assumptions, false-positive annotations, imported axioms, or disabled bodies. Privileged code is outside the proof boundary.
- Security/fail-closed: linker warnings are fatal; the gate rejects hosted/dynamic/TLS sections, RWX segments, undefined symbols, target/entry drift, and non-reproducible output.
- Verification/diagnostics: gate output includes structured `FLYOLOGY:BOOTSTRAP_MINIMUM:PASS`, target metadata, and hashes. The earlier failures demonstrate the checks are active.
- Portability/claims: support is limited to the pinned ELF cross targets. QEMU/UEFI/Limine execution is not yet claimed.
- Licensing: all tracked source is original MIT/Apache-2.0 work. Downloaded tools and boot artifacts remain external inputs under their own licenses. No GNAT runtime source is tracked.

## Subtraction review

Risk tolerance is proof-oriented because this runtime will own privileged and concurrent state. The whole bootstrap-minimum checkpoint tree was searched for alternate task dialects, hosted dependencies, duplicated mechanisms, and premature platform services.

No other subtraction is accepted at bootstrap-minimum checkpoint. The bootstrap entry stubs are target-specific because their ABIs and instruction sets differ; merging them would obscure rather than remove a concept. The two toolchain manifests encode genuinely different mutually exclusive compiler selections. The only public-looking runtime surface is `Flyology_Freestanding.Validation`, which is the intended proof kernel. There are no zero-caller compatibility shims, configuration knobs, services, or scheduler abstractions to remove. This conclusion is backed by the complete initial-tree census and empty history; future milestone reviews must repeat the census against accumulated code.

One evidence-backed `NARROW` occurred during the licensing review: the provisional `System` package exposed address, priority, floating-point, and private target parameters, but the isolated compile probe showed zero bootstrap-minimum checkpoint need for every declaration. The package was narrowed to the empty declaration; dual-target builds and byte-reproducibility tests verify equivalence for the bootstrap-minimum checkpoint program. Reversal is trivial when a later owned probe demonstrates a required declaration. Concepts removed: speculative target model and exception/priority configuration; public surface reduced to one package name.

## Residual risk and unsupported claims

- Neither ELF has booted under Limine or QEMU.
- Binder elaboration, exceptions, last-chance diagnostics, HHDM/memory-map validation, AP startup, and SMP are absent.
- The proof compiler is native GNATprove 16.1.0 while target compilation is GNAT 15.3.0. The proved units use target-independent integer semantics; target representation proof must later consume compiler-matched target properties.
- The UEFI firmware binaries are pinned tested inputs, not reproducible EDK II builds.
- Clean-room implementation avoids copied runtime licensing but increases compiler-compatibility and semantic-conformance risk; legal conclusions about compatibility interfaces remain outside this engineering review.

## Decision

bootstrap-minimum checkpoint is complete. Both freestanding target images build reproducibly and the blocking findings are fixed. This review does not authorize or imply any bootstrap checkpoint claim.
