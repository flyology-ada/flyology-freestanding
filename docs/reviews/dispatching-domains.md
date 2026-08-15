# dispatching-domain capability review — immutable scheduling domains and heterogeneous policies

- Review date: 2026-08-14
- Implementation base commit: `d2d2b8fe0b3ea985533a291793ec866423153619`
- Reviewed source manifest: `c2e116bf07afafea1f76df3a8112bca392ae874cf5cbbe3e0d6bd6d678e5b15b`
- Closing gate: `scripts/verify-domains.sh`
- Proof gate: `scripts/prove.sh` (FSF GNATprove 16.1.0, level 2)

## Evidence

The serialized closing run ended in `FLYOLOGY:DOMAINS:GATE:PASS`. It checked
repository hygiene; ran GNATprove and every bounded Ada/TLA+ model; exercised
the native allocator and abort/exception black boxes; rebuilt the clean-room
tasking capability through dispatching-domain capability compiler-interface probes with both target compilers; checked
interrupt layouts, ELF structure, and unwind metadata; reproduced both images;
booted x86-64 and AArch64 at one and four CPUs; and repeated each architecture's
SMP4 dispatching-domain capability campaign five times. Every QEMU run had a 20-second timeout and rejected
`FLYOLOGY:FAIL:` and `PANIC:`.

The manifest is the SHA-256 of the sorted SHA-256 list for every regular file
under `src`, `formal`, `probes`, `config`, `scripts`, and `tests`. It identifies
the exact implementation, formal models, probes, and gates independently of
this review and the roadmap status edit; the unchanged Git base is the commit
listed above.

| Target | CPU cells | ELF SHA-256 | FAT SHA-256 |
| --- | --- | --- | --- |
| x86-64 `pc-q35-10.2` | 1, 4, plus 5 × SMP4 | `86792322d91a3282d7f089dfd32d902bf0295461453374328c08e7ea05919bb7` | `b500ba5640b0c8ca908b762307f332c7e8c128f894bdeeff7724be620c6a33a8` |
| AArch64 `virt-10.2` / GICv3 | 1, 4, plus 5 × SMP4 | `1a180e141ae11e5fa4b731df6bbe8c57ec12da6fdfb1565bf76b9b032d70c274` | `553e0929767aa3731cbc09b6245c18bbfce638cf1665315ae6be993f9cc2fd9c` |

GNATprove proved all 476 generated checks with zero justified or unproved
checks and no `Assume`. The scheduling-domain proof covers validity, canonical
initialization, all-or-none creation with exact frame conditions, placement for
both compiler automatic-CPU sentinels and specific CPUs, and explicit/inherited
admission. It also reruns the deterministic dispatcher, policy, ready-position,
wait, timer, lifecycle, ceiling, termination, abort-closure, and allocator
arithmetic kernels. Concurrent `Flyology_Freestanding.Kernel`, imported task-primitives
declarations, compiler-facing GNARL facades, secondary-stack machinery,
architecture assembly, hardware, the C unwinder, and C allocator synchronization
remain outside SPARK behind checked boundaries.

The bounded host gates emitted exactly:

- `FLYOLOGY:TASKING:MODEL:PASS:EDGES 313:HASH 6790843470299599875`
- `FLYOLOGY:RTS:MODEL:PASS:EDGES 224969:HASH 12736863837444350006`
- `FLYOLOGY:PREEMPTION:POLICY_MODEL:PASS:EDGES 611:HASH 4221926451382466817`
- `FLYOLOGY:DOMAINS:DOMAIN_MODEL:PASS:EDGES 39:HASH 18160326575195984137`

TLC explored 338,697 distinct states: 165,888 each for FIFO and round-robin
scheduler/preemption, 5,408 for scheduling domains, and 1,513 for exact wait
arbitration. The scheduler models keep deadlock checking enabled. The domain and
wait models admit valid bounded terminal states and make only their listed
safety claims. These are executable design models, not source refinement or a
proof of Ada, atomics, assembly, compiler ABI, or hardware.

The closing QEMU logs were recorded on 2026-08-14 between 17:12 and 17:16
America/Vancouver. All four baseline cells and ten SMP4 stress cells contain
their dispatching-domain capability markers exactly once. SMP4 requires CPUs 1–2 to remain in the FIFO
system domain and CPUs 3–4 in a round-robin secondary domain; standard domain
queries, implicit child inheritance, explicit system-domain override, FIFO
non-rotation, round-robin equal-priority progress, and delayed higher-priority
complete-context preemption on every core must all succeed. Reproducibility is
same-host, same-worktree rebuilding in two independent output roots, not
independently provisioned clean-room reproduction.

## Findings and dispositions

### Blocker — per-core diagnostic ownership did not survive preemption

The preemption capability pre-Ada FP/SIMD canary flag was per-core. After interrupt-time context
transfer, another task could run on that core while the interrupted task's flag
remained active, causing a valid replacement context to be compared with the
wrong task's constants and fail intermittently.

Disposition: fixed. The pre-Ada canary remains only in the interrupt-substrate checkpoint profile where the
interrupt returns to the same task. preemption capability/dispatching-domain capability use task-local post-resume validation
of the complete saved context. The production preservation path and all-core
canaries remain checked on both targets.

### Blocker — the initial task stack boundary was rejected

An interrupt can arrive at the task trampoline before its first call pushes a
return address. At that point the architectural stack pointer is exactly the
exclusive top of the task's allocated extent. The first frame validator required
it to be strictly below that address and failed closed on a legal continuation.

Disposition: fixed. Interrupt-frame ownership accepts the exclusive top as the
one legal empty-stack boundary and still checks the exact task extent and bottom
canary. Ordinary live-stack observations remain strictly within the extent. A
focused natural-timing x86-64 SMP4 campaign passed 100 consecutive runs before
the complete two-target closing gate.

### Proof obligation — domain creation validity initially timed out

The monolithic validity postcondition obscured the exact ownership and frame
facts needed by GNATprove. This was a proof decomposition problem, not grounds
to weaken the contract.

Disposition: fixed. Validity is decomposed into domain-table, core-ownership,
task-table, and environment predicates. Creation uses a proved exact total-map
rewrite and strong unrelated-state frame conditions. The final whole-project
run proves 476/476 checks.

## Perspective review

- Architecture and boundary integrity: GNARL retains language semantics;
  `Flyology_Freestanding.Kernel` owns task/domain state and context handoff; each domain selects
  one scheduler policy; architecture code only captures/restores frames and
  performs interrupt notification/transfer.
- Ada/compiler compatibility: application code uses ordinary task declarations,
  `Dispatching_Domain` and `CPU` aspects, and the Ada 2022 D.16 query/create
  surface. The exact GNAT 15.3 handle, limited build-in-place return, task-field,
  and secondary-stack boundaries come from owned two-target probes.
- SMP and isolation: each active dense core has exactly one immutable domain
  owner. A Ready or Running task remains on an eligible core in its own domain;
  hardware IDs are never used as dense `Core_Id` values.
- Policy semantics: the system domain uses FIFO-within-priorities and the
  secondary domain round robin. Policy chooses work but never transfers a
  context. FIFO non-rotation and round-robin equal-priority progress execute
  concurrently in the same four-core image.
- Proof soundness: SPARK proves deterministic state transitions and exact frame
  conditions; TLC and host enumeration broaden bounded behavioral exploration.
  Concurrent integration and architecture paths remain explicitly excluded.
- Security and diagnostics: invalid handles, CPU/domain membership, capacity,
  state ownership, stack extents, and secondary-stack arithmetic fail closed.
  Structured pass markers follow their causal checks.
- Licensing: all added runtime and formal-model source is original dual
  MIT/Apache-2.0 work. Compiler compatibility evidence uses the Ada RM, owned
  probes, generated expansion/binder output, and black-box behavior—not GNAT
  runtime source. The external TLA+ tools JAR is MIT-licensed, ignored, pinned,
  and neither linked into nor shipped with the runtime.

## Subtraction review

dispatching-domain capability adds no public spawn, fiber, yield, task-creation, scheduler-control, or
wait-token dialect. There remains one task/current/ready/context authority and
one global RTS lock. Domain state extends that authority instead of wrapping it
with a second scheduler. The secondary stack is a bounded compiler ABI service,
not another task stack or general allocator. Fail-only diagnostic markers do
not select, wake, block, or transfer tasks.

## Residual risks and unsupported claims

- Domain membership is immutable in dispatching-domain capability. Cross-domain `Assign_Task` and dynamic
  ownership transfer are deliberately unsupported and fail closed.
- The product gate creates one secondary contiguous domain over CPUs 3–4. The
  model covers bounded subsets and rejection cases, but execution does not
  claim every topology, more than four cores/domains, or noncontiguous domains.
- Execution is limited to pinned QEMU 10.2.0 TCG q35/virt, EDK2, Limine,
  SMP1/4, GNAT 15.3 cross compilers, and GNATprove 16.1. No physical hardware,
  hosted CI, or independently provisioned reproduction is claimed.
- TLC exploration is exhaustive only within its stated finite constants. It
  does not establish liveness of the domain/wait models or source refinement.
- The fixed task, identity, stack, handler, heap, and 1 KiB per-task secondary-
  stack capacities remain. Dynamic domain destruction and resource reclamation
  are not implemented.

## Decision

dispatching-domain capability is complete for immutable scheduling-domain creation and task admission,
standard domain/CPU queries and inheritance, and simultaneous FIFO and
round-robin policy instances across all four cores on the two fixed QEMU machine
contracts. Dynamic domain reassignment, arbitrary topology, physical hardware,
and broader Ada tasking semantics are not claimed.
