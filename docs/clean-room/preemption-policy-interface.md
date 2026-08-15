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
The deterministic policy kernel and all existing SPARK units produce 434
proved checks with no justified or unproved checks. The preemption capability host campaign pins
611 policy/configuration/accounting/ready-position decisions and hash
`4221926451382466817`.

The product connection keeps policy, core, and architecture ownership
separate. `Flyology.Preemption_Model` validates the binder configuration,
converts the round-robin slice to checked clock ticks, accounts retained
budgets, and returns only a preemption cause. The priority-ready policy owns
head/tail ordering and next selection. A base-priority change of a Ready task
removes the exact entry and reinserts it at the tail of the new active-priority
queue with a fresh sequence; a round-robin budget is replenished only when the
task is next dispatched. `Flyology.Task_Core` commits the one checked
Running-to-Ready transition and owns task-local complete-context storage.
Architecture interrupt entry captures the enabled machine state and returns
either to the interrupted instruction or to the already-saved dispatcher
context; it never selects a task.

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
kernels, not concurrent `Task_Core`, interrupt assembly, timer hardware, or
the QEMU execution itself.

Reference: Ada RM D.2.3 (Preemptive Dispatching) and D.2.5 (Round Robin
Dispatching), as published by the Ada Resource Association.
