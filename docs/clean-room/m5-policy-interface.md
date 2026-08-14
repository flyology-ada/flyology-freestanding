# M5 dispatching-policy interface record

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

`scripts/probe-m5-policy.sh` compiles the owned no-op policy probe and the
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
The deterministic policy kernel and all existing SPARK units produce 425
proved checks with no justified or unproved checks; the M5 host campaign pins
597 policy/configuration/accounting decisions and its exact output hash.
Product support remains unclaimed until the checked budget model is connected
to task-owned complete interrupt frames, real timer/IPI preemption, and
ordinary-Ada no-yield gates on x86-64 and AArch64 at SMP1 and SMP4.

Reference: Ada RM D.2.3 (Preemptive Dispatching) and D.2.5 (Round Robin
Dispatching), as published by the Ada Resource Association.
