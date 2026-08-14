# ADR 0005: Separate context forms and generation-qualified rescheduling

- Status: accepted
- Date: 2026-08-13

## Context

M2 needs voluntary switching, complete resumable interrupt state, nested runtime critical sections, and cross-core notification without letting architecture code select scheduling policy. Treating all contexts alike would make an ABI-boundary save insufficient for arbitrary interrupt return. Treating an interrupt delivery bit as a reschedule request would permit coalescing or acknowledgement races to lose work.

## Decision

Voluntary and asynchronous contexts are distinct represented types. The voluntary form saves the target ABI-preserved state; the interrupt form saves complete enabled machine state. x86-64 enables only x87 and SSE (`XCR0=3`) and stores XSAVE data outside the reusable IST frame. AArch64 saves base FP/SIMD `q0 .. q31`; SVE and SME remain disabled.

Each core owns nonwrapping requested and acknowledged epochs plus reason bits. Notification IPIs/SGIs are prompts after release publication, not the request itself. M2 keeps reason bits sticky so acknowledgement cannot erase a concurrently published cause. Runtime critical sections are nestable per core; only the outermost level owns the global lock, and a pending request becomes dispatchable at the outermost leave boundary.

The deterministic task-state, wait-generation, ready-queue, and epoch transformations are SPARK kernels. Assembly, atomics, interrupt controllers, and concurrently changing per-core words remain outside SPARK behind typed contracts. Scheduler selection never performs context transfer.

## Consequences

Context completeness is explicit and testable, and wake/reschedule publication cannot depend on reliable one-for-one interrupt delivery. M2 may conservatively over-report old reason categories. A generation-qualified clear or equivalent atomic protocol is required before M5 uses reasons for quantum-specific accounting. Enabling AVX, SVE, or other extended state requires a new context contract and tests.

## M5 transfer extension

M5 gives each execution slot task-owned complete-context storage. On x86-64
this is the normalized 256-byte frame plus its own 4,096-byte XSAVE area; on
AArch64 it is the complete 832-byte frame. The interrupt path will copy into
that storage before abandoning the per-core exception stack, then restore the
already-saved voluntary dispatcher context. The dispatcher remains the only
component that commits selection and resumes either the task's voluntary
context or its complete interrupt context. No pointer into an IST or SP_EL1
exception stack becomes task state.

The complete-frame transfer primitives validate return selectors/status,
instruction and stack state, extended-state geometry, and alignment before
`iretq`/`eret`. Their assembly constants are emitted into a layout section and
checked against independently compiled Ada representation reports for both
targets. Merely compiling these primitives does not constitute preemption
support; M5 additionally requires their connection to the checked task-state
and policy kernels plus interrupt-driven ordinary-Ada QEMU gates.
