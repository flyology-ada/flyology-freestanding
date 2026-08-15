# interrupt-substrate checkpoint review — policy-neutral SMP execution substrate

- Review date: 2026-08-13
- Implementation commit: `1a316a7ebaf1ebba809d4f8b196c1f2bc55b81e8`
- Closing gate: `scripts/verify-interrupts.sh`
- Proof gate: `scripts/prove.sh`

## Evidence

The closing gate checked repository hygiene, proved the deterministic kernels, validated Ada/assembly interrupt layouts, rebuilt and compared both ELF/FAT pairs twice, inspected the freestanding ELFs, and ran four bounded QEMU cells. Every cell required one marker per dense core for the substrate, complete interrupt-frame round trip, request epoch, parallel task overlap, nested deferred request, remote reschedule delivery, and timer delivery. x86 additionally injected an interrupt after private `LGDT` but before final `LIDT`, proving that the bootstrap selector remained valid throughout the transition. No failure or panic marker was accepted.

| Target | CPU counts | ELF SHA-256 | FAT SHA-256 |
| --- | --- | --- | --- |
| x86-64 `pc-q35-10.2` | 1, 4 | `63a59986dc71e17703418dc4bff8054804eeed72467b409169f0e49581cd1d90` | `7aabf9f1f19020c484c9e248d419bfc8018c61d1b6b6138842ad9b46f5706749` |
| AArch64 `virt-10.2` / GICv3 | 1, 4 | `97e86bf22d9dab614a43805c58c266573b708fceacdca037f47105766c6416e7` | `be839fb07f2dbbf673846b2843979a15d83f826f55f18de815d0379bd9beef04` |

GNATprove FSF 16.1.0 proved all 97 checks in the six implemented deterministic model units. The imported declarations in `Flyology_Freestanding.Task_Primitives_Contract` are deliberately outside SPARK and are neither claimed proved nor linked as the final GNARL implementation. The gate checks the proof executable digest as well as its version.

The exact implementation commit ended in `FLYOLOGY:INTERRUPTS:GATE:PASS`. Independent architecture, concurrency, and verification reviews returned GO after the final transition and stale-generation fixes.

## Findings and dispositions

### Blocker — declared interrupt frames were disconnected from entry assembly

Initial vectors saved only general registers while the layout gate compiled unused Ada records.

Disposition: fixed. x86 creates a normalized 256-byte frame on per-core IST1 stacks and stores complete x87/SSE state in per-core aligned XSAVE areas. AArch64 creates an 832-byte frame on per-core SP_EL1 stacks containing all GPRs, return/control state, thread pointer, and `q0 .. q31` plus FPCR/FPSR. Both paths validate canaries and resume the interrupted instruction. Voluntary context records remain separate.

### Blocker — request acknowledgement could erase a concurrent reason

Both architecture paths originally acknowledged an epoch and then cleared reason bits, permitting a publisher between those operations to retain a pending epoch without its cause.

Disposition: fixed with conservative sticky reasons. Acknowledgement advances only the observed epoch; reason bits are never cleared in interrupt-substrate checkpoint, matching the SPARK model. This cannot lose a cause, though generation-qualified clearing remains preemption capability work.

### Blocker — critical depth and block handoff were not production-safe

Nested entries reacquired a nonrecursive spinlock, and the first block primitive briefly returned to executing code after publishing `Blocked` and clearing current ownership.

Disposition: fixed. Only depth transition 0-to-1 acquires the global lock and only 1-to-0 releases it. Block publication, current-task removal, interrupt masking, outer lock release, and context transfer form one handoff; application execution cannot continue in the published blocked state. A nested timer test requires deferral until the outer leave.

### Blocker — exact-wake and dispatch models were only smoke tests

Initial execution bypassed queue selection and did not demonstrate reusable waits, stale identity/generation rejection, or concurrent application work.

Disposition: fixed. Production interrupt-substrate checkpoint execution owns persistent per-core current/state/wait records and ready queues. Two complete block/wake/redispatch cycles run through the checked path; wrong incarnation and prior-generation tokens return before state or queue mutation. SMP4 uses an unlocked barrier that cannot complete unless the four separate task contexts overlap.

### Blocker — x86 table activation exposed invalid IDT/GDT combinations

An early form used IST-backed gates before private TSS installation. A later form changed to the private GDT while the active bootstrap IDT still referred to Limine's code selector.

Disposition: fixed fail-closed. Each expanded private GDT validates and preserves the live bootstrap code selector without colliding with Flyology Freestanding descriptors. A dedicated interrupt is injected through the bootstrap IDT after `LGDT`; its per-core marker is required. `LTR` then precedes final `LIDT`, whose 256 gates all use selector `0x08` and IST1.

### High — interrupt-controller initialization inherited unsafe state

The AArch64 redistributor initially wrote the wrong disable register, did not normalize PPI27 trigger state, and omitted the store barrier before SGI. The x86 timer design initially assumed an unavailable TSC deadline feature.

Disposition: fixed for the pinned machines. GICv3 disable/pending/configure/enable and RWP waits are explicit, `dsb ishst` orders shared publication before SGI, and virtual timer PPI27 is normalized. x86 uses the x2APIC initial-count timer supported by QEMU 10.2 `-cpu max`.

## Perspective review

- Architecture and boundary integrity: the policy package selects from ready structures but never transfers context. The core validates transitions/current ownership and architecture code alone saves/restores machine state. Limine remains confined to boot description and MP handoff.
- Systems/hardware correctness: per-core pointers, private exception stacks, GDT/TSS/IST, x2APIC timer/IPI, GICv3 SGI/PPI, SP_EL0/SP_EL1, and FP enabling are exercised on the exact pinned QEMU machines. Unsupported feature or selector geometry fails closed.
- Ada/GNARL compatibility: interrupt-substrate checkpoint exposes only an internal task-primitives contract shaped for later GNARL binding. It does not expose Spawn/fiber APIs and does not claim ordinary Ada tasks, activation, masters, rendezvous, or protected objects; those remain tasking capability/synchronization capability.
- SMP concurrency and atomics: task bodies overlap outside the global RTS lock. Wake publication and queue mutation are serialized; request epochs are release-published before notification and acquire-observed. Sticky reasons close the acknowledged-clear race.
- Interrupt/ABI/context: target Ada is built without the x86 red zone. Voluntary ABI state and arbitrary-instruction interrupt state have separate layouts. x86 scope is x87/SSE only; AArch64 scope is base FP/SIMD only.
- Scheduler-policy separation: one bounded FIFO ready implementation establishes the selection contract. It owns no current-task or context state. Multiple standard policy configurations remain preemption capability and domains remain dispatching-domain capability.
- Memory safety and lifecycle: all interrupt-substrate checkpoint task, core, frame, queue, and stack storage is bounded/static with checked indices and canaries. There is no allocator, dynamic task destruction, or reclamation claim yet.
- SPARK soundness and coverage: 97 checks cover the six deterministic implementations without assumptions, false-positive annotations, or ghost hardware state. Concurrent assembly/atomics and the imported future GNARL contract are explicitly excluded.
- Security/fail-closed behavior: illegal state transitions, queue overflow/duplicates, stale/future wakes, depth/counter errors, invalid frames, selector conflicts, unsupported identities, and controller timeouts terminate through diagnostics.
- Verification and observability: QEMU runs use 20-second hard timeouts and require exact unique property markers. A timeout is accepted only after all markers. The table-transition and stale-wake gates are causal, not labels emitted before their checks.
- Portability and claims: evidence covers only QEMU 10.2.0 `pc-q35-10.2` and `virt-10.2`, TCG, SMP1/4, and the pinned firmware/Limine inputs. No physical-server, AVX, SVE, ACPI, or general DT discovery support is claimed.
- Licensing: all tracked runtime code is original MIT/Apache-2.0 clean-room work. Compiler-facing observations remain documented compatibility evidence; no GNAT runtime source is tracked or used as implementation input.

## Subtraction review

There is no public creation, scheduler, interrupt-registration, device, or allocation API. Idle is a private per-core context, not an Ada task. The implementation retains one task-state authority and uses the wait record only for matching token/phase data; the earlier disconnected request smoke authority was removed from production correctness.

The two architecture entries remain separate because their exception frames, controllers, privilege stacks, and instructions are materially different. One concrete FIFO implementation remains because interrupt-substrate checkpoint must execute through a ready-queue selection boundary; speculative policy families and domains were not added. The global RTS lock remains the smallest correctness mechanism and is not sharded without evidence.

## Residual risks and unsupported claims

- interrupt-substrate checkpoint captures and restores complete enabled interrupt state and posts dispatch requests, but it does not switch Ada task contexts from interrupt return. Real interrupt-driven preemption is preemption capability.
- Sticky reason bits over-approximate historical causes. They are safe against lost requests but must be refined before reason-specific quantum accounting in preemption capability.
- The assembler layout tables duplicate the numeric save/restore offsets. The current gate catches Ada/table drift and frame canaries catch exercised corruption, but shared assembler constants or disassembly validation should remove this residual drift risk before preemption capability.
- `verify-interrupts-reproducible.sh` performs two same-host rebuilds in separate output roots. It proves deterministic output under the pinned environment, not an independently provisioned clean-room builder.
- No ordinary Ada task declarations, GNARL lifecycle semantics, dynamic allocation, exception propagation, synchronization, delay, or reclamation are claimed.
- Shellcheck was unavailable. `sh -n`, warnings-as-errors, proof, layout, ELF, reproducibility, and all QEMU gates did run.

## Decision

interrupt-substrate checkpoint is complete. The final implementation gate ended in `FLYOLOGY:INTERRUPTS:GATE:PASS` for both architectures at SMP1 and SMP4 with the hashes recorded above. This decision establishes only the policy-neutral execution substrate and does not authorize an tasking capability ordinary-task or full-GNARL claim.
