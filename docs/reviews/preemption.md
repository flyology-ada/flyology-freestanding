# preemption capability review — interrupt-time preemption and standard policies

- Review date: 2026-08-14
- Implementation base commit: `524f3670653f4bb3c7be43d95f9aa47e06125476`
- Reviewed source tree: `1043bb6a74dccdb90f744d82f8ffd0be3e236b3b`
- Closing gate: `scripts/verify-preemption.sh`
- Proof gate: `scripts/prove.sh` (FSF GNATprove 16.1.0, level 2)

## Evidence

The frozen reviewed-tree gate ended in `FLYOLOGY:PREEMPTION:GATE:PASS`. It checked
repository hygiene; proved the deterministic policy and ready-position
kernels; reran the cumulative tasking capability/synchronization capability host models and native synchronization capability black boxes;
rebuilt the clean-room compiler-policy probes with both target compilers;
checked voluntary and interrupt layouts; reproduced, inspected, and checked
unwind metadata for FIFO and round-robin images; booted both policies on both
architectures at one and four CPUs; and repeated every architecture/policy
SMP4 preemption campaign five times. Every QEMU run had a 20-second timeout and
rejected `FLYOLOGY:FAIL:` and `PANIC:`.

| Policy | Target | CPU cells | ELF SHA-256 | FAT SHA-256 |
| --- | --- | --- | --- | --- |
| FIFO | x86-64 `pc-q35-10.2` | 1, 4, plus 5 × SMP4 | `6d17be1fdab6ee9116e041208e21a3afdb3d47945eb91dc382e23cf6831638e1` | `008eee319ff5e97f7b932894760beae694eede1080ffcf082682d807ced71a4c` |
| FIFO | AArch64 `virt-10.2` / GICv3 | 1, 4, plus 5 × SMP4 | `28fffd44e6c7c13d89ec35b8b2a06400de2e01d9deaf47da3d57db1ecb15bb00` | `af4c198a412192621f0acd078a073c8670741ff494c64e2b8ccbc175c3bd76a5` |
| Round robin | x86-64 `pc-q35-10.2` | 1, 4, plus 5 × SMP4 | `e598254e4ca5c7c7c7dc1c0b8dc9895045fd1b99ce954de90392e7af1efadfa9` | `72702368f7bf06a01905de1fad0e82c5a3654c418322b2ccab1d501aa0be0f99` |
| Round robin | AArch64 `virt-10.2` / GICv3 | 1, 4, plus 5 × SMP4 | `cb82cc51b56d24520d5e3302ee22d1cc54b4330507dfbe7497f2b195e25073e5` | `c82ea0eba5abf22ca19633732a0b284e774f4ca5580ee63570bdf0e5a16656e9` |

GNATprove proved all 434 generated checks with zero justified or unproved
checks and no `Assume`. The proof covers the deterministic dispatcher,
priority-ready, preemption accounting, wait, timer, lifecycle, ceiling,
termination, abort-closure, and allocator-arithmetic kernels. Concurrent
`Flyology_Freestanding.Kernel`, imported task-primitives declarations, compiler-facing
GNARL facades, architecture assembly, hardware, the C unwinder, and the C
allocator synchronization remain outside SPARK behind typed boundaries. The
proof does not establish the interrupt handoff or the global RTS-lock protocol.

The host gates emitted exactly:

- `FLYOLOGY:TASKING:MODEL:PASS:EDGES 313:HASH 6790843470299599875`
- `FLYOLOGY:RTS:MODEL:PASS:EDGES 224969:HASH 12736863837444350006`
- `FLYOLOGY:PREEMPTION:POLICY_MODEL:PASS:EDGES 611:HASH 4221926451382466817`

The preemption capability model enumerates policy validation, FIFO/round-robin budget decisions,
preemption causes, ready positions, and priority requeue operations. It is
exhaustive over its bounded deterministic inputs, not over concurrent Ada,
assembly, or hardware interleavings.

The closing QEMU logs were recorded on 2026-08-14 between 13:09 and 13:19
America/Vancouver. The eight baseline cells and twenty SMP4 stress cells each
contain their policy-specific preemption capability marker exactly once. SMP4 additionally requires
remote IPI/SGI preemption, a complete-context canary and delayed higher-priority
coordinator on every core, Ready-task priority requeue, FIFO non-rotation, and
a causally observed interrupt retry while another core holds the RTS lock. The
reproducibility claim is same-host, same-worktree rebuilding in two independent
output roots; it is not independently provisioned clean-room reproduction.

## Findings and dispositions

### Blocker — interrupt ingress could spin behind the global RTS lock

The first interrupt callback entered the same blocking RTS lock used by long
protected actions. A timer or reschedule interrupt on one core could therefore
spin while another core held the lock, contradicting the nonblocking ingress
contract and admitting a cross-core deadlock.

Disposition: fixed. Interrupt entry publishes the request epoch and makes one
nonblocking lock attempt. Contention leaves the epoch pending, programs a short
local retry prompt, and returns to the interrupted task. The retry prompt is not
correctness state. A dedicated per-core counter at byte offset 120 of each
128-byte architecture core record causally proves the contention path without
an interrupt-side retry loop or aliasing the online-publication word.

### Blocker — Ready-task priority changes retained stale queue age

The first production path changed a Ready entry's priority in place. That could
preserve an old FIFO sequence or head position after a base-priority change and
give round-robin work a stale budget.

Disposition: fixed. The proved ready policy removes the exact entry and appends
it at the tail of the new active-priority queue with a fresh sequence. Production
resets its round-robin budget for replenishment on the next dispatch. An
ordinary-Ada SMP4 test requires the resulting order.

### Blocker — tests did not initially prove all-core arbitrary preemption

Early SMP4 canaries could terminate after a coordinator on one core released a
shared flag, without proving that timer-to-dispatch handoff occurred on every
core. The original lock-contention test also lacked a happens-before edge and
could pass without a failed interrupt-side lock attempt.

Disposition: fixed. Each core now runs one CPU-bound complete-context canary and
one delayed higher-priority coordinator with a private release byte. Every
coordinator must make progress before its local canary can finish. The ingress
test arms its delayed high-priority task before the producer enters a checked
50-ms no-safe-point window while the remote protected holder owns the RTS lock;
the marker requires the dedicated retry count to increase.

### High — diagnostic output could self-deadlock under preemption

The serial diagnostic lock was not scheduler-aware. Preempting its owner and
running a reporting task on the same core could leave the replacement spinning
for a lock whose owner could not resume.

Disposition: fixed. Interrupt dispatch recognizes the local serialized-output
owner and uses the same retained-epoch/retry path instead of transferring to a
replacement task. The diagnostic lock remains outside scheduler policy.

### High — temporary instrumentation enlarged the product ABI

An exported collision-debug step variable was written but never read by source,
tests, scripts, or documentation.

Disposition: removed. Only the internal, behaviorally asserted retry counter
remains; no debug-step symbol or alternate task/scheduler interface is exported.

## Perspective review

- Architecture and boundary integrity: GNARL owns language semantics;
  `Flyology_Freestanding.Kernel` owns checked task state and context handoff; scheduler policy owns
  ordering and cause selection; architecture code owns frame capture, restore,
  interrupt acknowledgement, and transfer only.
- Systems/hardware correctness: x86 uses calibrated x2APIC one-shot timers and
  IST frames under the pinned QEMU contract. AArch64 uses `CNTV_CVAL_EL0`, PPI
  27, GICv3 EOI, SP_EL1 exception stacks, and SP_EL0 task/dispatcher contexts.
- Ada/GNARL compatibility: applications use ordinary Ada tasks, priorities,
  delays, protected objects, and rendezvous. Policy configuration comes from
  the compiler/binder surface established by owned GNAT 15.3 probes; there is
  no public spawn, fiber, yield, or scheduler API.
- SMP and atomics: request publication precedes notification. Interrupt ingress
  never blocks on a remote RTS-lock owner. The one RTS lock remains the state
  publication authority; the scheduler does not transfer contexts.
- Interrupt/ABI/context: complete asynchronous continuations are copied into
  task-owned storage before abandoning IST/SP_EL1. They preserve every enabled
  GPR, status, stack, FP control, and FP/SIMD register tested by the canaries.
  Voluntary and asynchronous context records remain distinct.
- Policy semantics: FIFO gives higher-priority preemption and head reinsertion
  of the interrupted task without rotating equal-priority CPU-bound peers.
  Round robin gives equal-priority progress, replenishes at tail dispatch, and
  retains budget across higher-priority interruption as required by the retained
  model.
- Memory and lifecycle: synchronization capability's off-stack retirement, exact wait generations,
  stack-slot reuse, stable identity tombstones, and allocator contracts remain
  unchanged and are rerun by the cumulative gate.
- SPARK soundness: 434 checks cover deterministic kernels without assumptions.
  Concurrent orchestration, assembly, C, QEMU, and hardware are explicitly
  excluded from the proof claim.
- Security and diagnostics: invalid frames, selectors/status, stale task or wait
  generations, impossible state/queue ownership, lock-depth errors, and retry-
  counter overflow fail closed. Structured pass markers follow causal checks.
- Portability and claims: execution evidence is limited to QEMU 10.2.0 TCG,
  q35/virt, EDK2, Limine, SMP1/4, GNAT 15.3 targets, and GNATprove 16.1. No
  physical hardware or hosted CI result is claimed.
- Licensing: the implementation is original MIT/Apache-2.0 clean-room work.
  Compiler compatibility was derived from the Ada RM, owned source probes,
  generated expansion/binder output, and black-box behavior—not GNAT runtime
  source. Existing external libgcc/Limine inputs remain isolated and recorded.

## Subtraction review

There is still one task-state/current/ready/context authority, one RTS lock, and
one selected scheduler policy per image. No public creation, fiber, wait-token,
preemption, or policy-control dialect was added. Interrupt retry is one bounded
architecture prompt over the existing epoch, not a second work queue or state
machine. The unused debug export and in-place priority mutation were removed
rather than wrapped. Test-only canaries and markers do not select, block, wake,
or transfer application tasks.

## Residual risks and unsupported claims

- Execution is limited to the pinned QEMU 10.2.0 TCG q35/virt contracts. No
  physical hardware, hosted CI, independently provisioned reproduction, or
  general ACPI/DT discovery is claimed.
- x86 enables x87/SSE with `XCR0=3`; AVX, AVX-512, AMX, and other extended state
  are disabled. AArch64 enables base FP/SIMD only; SVE/SME are disabled.
- Only whole-partition FIFO and round-robin policy images are closed. Immutable
  scheduling domains and heterogeneous per-domain policies remain dispatching-domain capability.
- Deterministic proof/model exploration does not cover all concurrent
  interleavings. Repeated QEMU stress is causal and bounded, not exhaustive race
  exploration.
- The fixed synchronization capability execution, identity, stack, handler, and heap capacities remain.
  Shellcheck is unavailable; the repository's shell syntax/hygiene checks pass.

## Decision

preemption capability is complete for standard-Ada-aligned FIFO and round-robin policy selection,
timer/IPI/SGI-driven arbitrary-instruction preemption, task-owned complete
contexts, all-core no-yield progress, and bounded nonblocking interrupt ingress
on the two fixed QEMU machine contracts. dispatching-domain capability scheduling domains and heterogeneous
policies are not claimed.
