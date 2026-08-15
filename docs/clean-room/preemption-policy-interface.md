# preemption capability dispatching-policy interface record

This record is clean-room evidence from Flyology-owned sources, the Ada
Reference Manual, and generated output from the pinned GNAT 15.3 cross
compilers. No GNAT run-time source was consulted.

The Ada RM defines `FIFO_Within_Priorities` as higher-priority preemptive and
FIFO within one priority. A higher-priority preemption puts the interrupted
task at the head of its ready queue. The RM's round-robin policy adds an
execution-time budget: tail insertion replenishes the quantum, higher-priority
preemption retains the remaining budget, and exhaustion moves the task to the
tail only when it has no inherited priority and is outside a protected action.
These rules are the authority for `Flyology.Preemption_Model`; scheduler policy
still selects tasks and never transfers a context.

`scripts/probe-preemption-policy.sh` compiles the owned no-op policy probe and the
owned minimum predefined units with `-nostdinc/-nostdlib` for both pinned
targets. The generated binders agree exactly:

- `FIFO_Within_Priorities` assigns `__gl_task_dispatching_policy = 'F'` and,
  with binder switch `-T0`, `__gl_time_slice_val = 0`.
- `Round_Robin_Within_Priorities` assigns the policy character `'R'`; binder
  switch `-T10` exports `__gl_time_slice_val = 10_000`. The generated unit's
  value is therefore microseconds.
- Neither whole-partition probe emits a priority-specific range; the generated
  count is zero on both targets.

The probe establishes configuration representation, not scheduler semantics.
The same owned probe suite also places each standard policy pragma directly in
an Ada compilation unit and binds without `-gnatec` or `-T`. Both target
compilers export the requested `F`/`R` policy, FIFO slice zero, and the
round-robin unspecified time-slice sentinel `-1`. Consumer applications
therefore select their initial policy in Ada source. Flyology interprets the
unspecified round-robin quantum as 10 ms;
repository conformance configurations continue to pin the binder quantum so
their historical policy evidence remains exact.

The serialized GNATprove FSF 16.1 level-2 gate reports 543/543 generated
checks proved across all 23 deterministic proof units, with no justified or
unproved checks and no assumptions. This includes all six entities in the
original `Flyology.Scheduling_Configuration_Model`. The preemption capability
host campaign pins 2,531 policy/configuration/accounting/ready-position
decisions and hash `11691030413894487372`; its added transitions enumerate
empty, inactive, invalid, and accepted multi-core configuration changes and
hash every resulting per-core policy and quantum.

The live `Flyology.Scheduling` package is an original application API, not a
compiler-facing package and not evidence for a GNAT interface. It maps one
validated global/domain/CPU request through `Flyology.RTS` into the single
`Flyology.Kernel` state authority. The complete target set is checked by the
SPARK transition before any mutation under the RTS lock. The corresponding
TLA+ model explores global replacement, domain replacement, per-core override,
domain creation, admission, dispatch, and policy-dependent rotation in
17,035,809 generated / 683,040 distinct states. These are bounded design and
transition checks, not a refinement proof of concurrent Ada or assembly.

The product connection keeps policy, core, and architecture ownership
separate. `Flyology.Preemption_Model` validates the binder configuration,
converts the round-robin slice to checked clock ticks, accounts retained
budgets, and returns only a preemption cause. The priority-ready policy owns
head/tail ordering and next selection. A base-priority change of a Ready task
removes the exact entry and reinserts it at the tail of the new active-priority
queue with a fresh sequence; a round-robin budget is replenished only when the
task is next dispatched. `Flyology.Kernel` commits the one checked
Running-to-Ready transition and owns task-local complete-context storage.
Architecture interrupt entry captures the enabled machine state and returns
either to the interrupted instruction or to the already-saved dispatcher
context; it never selects a task.

The binder supplies only the safe pre-elaboration default. A live change does
not rewrite compiler globals. Global changes replace every used domain default
and active core; domain changes replace that default and all member cores; CPU
changes affect only one effective core. FIFO clears affected budgets, while
round robin gives an affected Running task a fresh full quantum and makes every
other affected task start fresh on its next dispatch. After the lock is
released, a request epoch and IPI/SGI prompt each affected core to consume the
new configuration and program its own local timer. Domain membership, task
placement, ready ordering, selection, and context-transfer ownership do not
move into this API.

The ordinary-Ada scheduling-domain image first leaves two equal-priority tasks
behind FIFO on one CPU and verifies that the second cannot start. A higher-
priority controller then changes that live CPU to a 2 ms round-robin quantum;
both CPU-bound tasks must make progress before the scope master can return.
On SMP4 the controller runs on CPU 1 and changes CPU 2, so the marker also
depends on the remote request/IPI-or-SGI path. The same image queries exact
global, domain, and CPU replacement results and rejects an invalid FIFO quantum
through the public exception boundary on both architectures and CPU counts.

Interrupt ingress never spins on the global RTS lock. The assembly entry first
handles the complete frame and publishes the request epoch, then the Ada
callback makes one nonblocking acquisition attempt. If another core owns the
RTS lock, or if the interrupted task owns the serialized diagnostic path, the
callback leaves the epoch pending, installs a short local one-shot retry, and
returns to the interrupted task. Correctness is carried by the retained epoch;
the retry timer is only a bounded prompt. This prevents interrupt context from
waiting behind a remote protected action and prevents same-core diagnostic
lock self-deadlock. The SMP4 gate observes this path through a dedicated
per-core retry counter at byte offset 120 of the 128-byte architecture core
record; the counter is diagnostic evidence, not scheduling state.

The interrupt-to-dispatch handoff is deliberately one-shot. The dispatcher
masks interrupts before publishing a selected task as Running, consumes any
saved-complete-context flag under the RTS lock, and unmasks only after the
incoming task context is installed. A later interrupt publishes a fresh full
frame. On x86-64, abandoning an IST frame also restores the private kernel SS
before voluntary dispatcher code resumes. On AArch64, the handoff abandons the
SP_EL1 exception frame and resumes the dispatcher on SP_EL0.

The ordinary-Ada preemption capability gates use no application safe point while waiting for
preemption. FIFO runs a delayed higher-priority task against a lower-priority
spin task and separately proves that timer interrupts do not rotate equal-
priority CPU-bound peers. Round robin requires two equal-priority spin tasks
to make progress. The SMP4 gate publishes a higher-priority CPU-2 rendezvous
from CPU 1 and requires the x2APIC IPI/GICv3 SGI path to preempt a CPU-2 spin
task. It also runs one CPU-bound complete-context canary on every core, changes
the priority of a Ready task and checks fresh tail order, and forces timer
ingress on CPU 2 while CPU 1 holds the global RTS lock in a protected action.
Architecture canaries seed and validate all enabled FP/SIMD state, FP control,
the task stack, the non-poll GPRs, and x86 RFLAGS/AArch64 NZCV across the real
handoff. The one scratch register used to poll the completion byte is restored
and reloaded by the loop rather than treated as a constant canary.

This is a fixed QEMU/GNAT product claim only. x86 enables x87/SSE with
`XCR0=3`; AVX/AVX-512/AMX are disabled. AArch64 enables base FP/SIMD only;
SVE/SME are disabled. Proof covers deterministic policy and arithmetic
kernels, not concurrent `Flyology.Kernel`, `Flyology.RTS`, application API
glue, interrupt assembly, timer hardware, or the QEMU execution itself.

Reference: Ada RM D.2.3 (Preemptive Dispatching) and D.2.5 (Round Robin
Dispatching), as published by the Ada Resource Association.
