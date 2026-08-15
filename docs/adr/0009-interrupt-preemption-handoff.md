# ADR 0009: Task-owned interrupt continuations and atomic dispatcher handoff

- Status: accepted
- Date: 2026-08-14

## Context

interrupt-substrate checkpoint captured complete interrupt frames but returned to the interrupted task.
preemption capability must sometimes abandon the reusable per-core exception stack, make the
interrupted task Ready, run the dispatcher, and later resume the exact
instruction. Publishing `Current` before the incoming task stack is installed
would let an interrupt mistake the dispatcher stack for task state. Retaining
a pointer into IST/SP_EL1 storage would let a later interrupt overwrite a
suspended task's continuation.

## Decision

Each execution slot owns one complete-context record. Interrupt ingress first
normalizes and validates the architecture frame and publishes the request
epoch. It then makes one nonblocking attempt to enter the RTS critical section.
On success, `Task_Core` accounts the current budget, asks the proved policy
kernel for a cause, copies the complete frame into the current task's slot,
commits the checked Running-to-Ready transition, and returns the already-saved
dispatcher context address. The architecture then abandons the exception frame
and restores that voluntary dispatcher context. No exception-stack address
becomes task state.

On lock contention, interrupt context never spins. The request epoch remains
pending and architecture code installs a short local one-shot retry before
returning to the interrupted task. The same deferred path is used while the
interrupted core owns the serialized diagnostic output lock, preventing a
replacement task on that core from waiting for a diagnostic owner that cannot
resume. The epoch is the correctness state; the retry timer is only a prompt.

The dispatcher masks interrupts before removing a selected task from the ready
policy and publishing it as `Current`. It consumes the task's complete-context
flag while still masked. Voluntary resumption unmasks only after the incoming
stack and preserved registers are installed; complete resumption restores the
saved interrupt status with `iretq` or `eret`. A complete continuation is
single-use; a future interrupt must publish another frame.

x86-64 interrupt entry executes `cld` before calling Ada while retaining the
interrupted RFLAGS in the hardware frame. An IST handoff that does not execute
`iretq` restores the private data selector before dispatcher code resumes.
AArch64 keeps task/dispatcher contexts on SP_EL0 and exception frames on
SP_EL1, completes GIC EOI before abandoning the frame, and restores SPSR_EL1
only when resuming the task.

Timer expiry and reschedule IPI/SGI are both prompts into the same checked
callback. A nested runtime critical section records the request but cannot
switch. Scheduler policy returns ordering/selection and a preemption cause;
only `Task_Core` changes ownership and only architecture code transfers state.
Changing a Ready task's base priority removes the exact ready entry and
reinserts it at the tail of its new active-priority queue with a fresh sequence;
round-robin execution receives a new budget only on the next dispatch.

## Consequences

Arbitrary-instruction preemption is resumable without aliasing a per-core
exception stack, and the dispatcher cannot be captured as the published task.
The enabled state contract remains x87/SSE on x86-64 and base FP/SIMD on
AArch64. Expanding that contract requires new frame layouts, restore
validation, and behavioral canaries. Current execution evidence is limited to
the pinned QEMU 10.2 q35/virt contracts at SMP1 and SMP4.
