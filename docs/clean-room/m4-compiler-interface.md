# M4 synchronization and exception interface evidence

This record is limited to Flyology-owned probes, compiler-generated expansion,
ALI metadata, object relocations/disassembly, the public two-phase unwind ABI,
and black-box execution. No GNAT runtime source was inspected or copied.

## Exception boundary

The owned `probes/m4/exception_probe.adb` produces the same compiler-facing
surface on both pinned GNAT 15.3 targets: `_Unwind_Resume`,
`__gnat_personality_v0`, `__gnat_begin_handler_v1`,
`__gnat_end_handler_v1`, the Program_Error check entry, and the
`program_error` identity. The landing pad receives the generic unwind object
and selector in the target's standard exception data registers. Its normal
handler lifecycle is `begin_handler_v1(object)` followed by
`end_handler_v1(object, cookie, null)`.

Flyology implements the Ada-specific exception object, LSDA matching,
personality, handler lifecycle, bounded allocation, and fail-closed behavior in
original code. It links the generic `libgcc` DWARF unwinder shipped inside each
pinned cross-toolchain; no copy is placed in the repository. This is a GCC
Runtime Library component governed by its upstream license and GCC Runtime
Library Exception, not original dual-licensed Flyology material.
The derived installed archive hashes are
`b6d172e843239c3fa3906c0d972936a48ebf3d4249a0d0e723f83ecb18ff2304`
for x86-64 and
`0effb03f768225ce901b94e6ab108a3709b83bd2c879a629136b89b9bb0cd992`
for AArch64; the build script checks them before linking.

Both linkers retain and separately register the original C exception-runtime
and Ada-probe frame sequences. This is required because individual freestanding
objects carry terminating frame sequences. The C runtime is compiled with
`-funwind-tables`; omitting it is a negative condition that prevents AArch64
from reaching the Ada personality.

`scripts/build-m4-exception.sh` builds a zero-unresolved freestanding image.
`scripts/run-m4-exception.sh` requires a caught Program_Error pass and unique
online-core markers under the pinned QEMU/UEFI contract for SMP1 and SMP4.

This checkpoint proves one named caught exception and the generic stack-unwind
path. The later abort increment below adds task-root containment for a private
abort occurrence. It does not yet establish exception occurrences/messages,
nested handler replacement, re-raise, general application-exception
propagation, or abnormal master semantics. Those require additional ordinary
Ada probes and QEMU gates before M4 closure.

## Synchronization surface discovered so far

Owned cross-target probes identify base protected-object lock/read-only-lock,
unlock, ceiling initialization and finalization; protected-entry initialization,
entry-call and service hooks; simple/timed/conditional task entry calls;
accept/select completion hooks; dynamic task abort/activation cleanup; delay;
and dynamic-priority operations. Private controlled record layouts that the
compiler does not expose remain deliberately unspecified. Implementations must
bind these facades to the single Task_Core state authority and exact-token wait
arbitration rather than introduce a second scheduler or public task API.

The native GNAT 15.3 expansion of the owned delay probe lowers relative
`delay 0.001` to `Ada.Calendar.Delays.Delay_For (Duration)`. Flyology's owned
facade routes that call through checked nanosecond-to-tick conversion, the
per-core exact-token timer table, and the common wait arbitration kernel. The
ordinary-task QEMU gate requires four simultaneous delayed tasks in the SMP4
image, rejects early resume by comparing the architecture clock with the
registered absolute deadline, and emits one `FLYOLOGY:M4:DELAYS:PASS` marker
only after their lexical master observes all completions. Absolute delays and
broader cancellation races remain separate M4 gates.

The owned `absolute_delay_probe.adb` confirms on both targets that an Ada
`delay until` statement lowers to `Ada.Real_Time.Delays.Delay_Until (Time)`.
Flyology represents `Ada.Real_Time.Time` as the validated architecture tick,
implements `Clock`, `Milliseconds`, time addition and comparison, and routes
the absolute deadline into the same per-core timer and exact-wait path used by
relative delay. The implementation checks conversion and deadline addition
before publishing a wait.

The ordinary-Ada image waits for a future absolute deadline, rejects any early
resume, then repeats `delay until` on the expired deadline to prove the
nonblocking path. All four QEMU cells require one
`FLYOLOGY:M4:ABSOLUTE_DELAY:PASS` marker. This checkpoint does not yet provide
the full `Ada.Real_Time` arithmetic/conversion surface. Until exception
registration is implemented, the language-defined `Time_Error` name aliases
the existing `Program_Error` identity and only fail-closed error paths are
claimed; no test exercises an overflow condition as conforming `Time_Error`
propagation.

The owned `base_protected_probe.adb` forces aggregate protected state so GNAT
cannot lower the object to scalar lock-free atomics. Both cross compilers then
emit the same base lifecycle: `Protection` default initialization,
`Initialize_Protection`, abort deferral, `Lock` or `Lock_Read_Only`, `Unlock`,
and `Finalize_Protection`, plus attachment through the compiler-required
finalization node. AArch64 additionally references `__clear_cache` for its
local trampoline; the probe gate records this target-specific difference
rather than hiding it. The product demonstration uses a library-level callback
and has no cache-trampoline dependency.

Flyology implements those profiles from owned declarations. Lock and unlock
hold the existing nestable global RTS critical section across the protected
body and update the current task's proved nested ceiling state. Thus protected
actions are globally serialized while unrelated application code continues in
parallel on other cores. The QEMU gate requires four automatically placed
ordinary tasks to update a two-word protected counter after their delays and
the master to observe the exact total before
`FLYOLOGY:M4:PROTECTED:PASS`. This checkpoint does not claim protected entries,
entry queues, priority-ordered entry service, ceiling-violation exception
propagation, or finalized-object race behavior.

The owned `simple_rendezvous_probe.adb` establishes the same compiler surface
on both cross targets for a simple task entry call: `Create_Task` receives an
entry count of one, the server calls `Accept_Call`, the client calls
`Call_Simple`, and normal accept completion calls `Complete_Rendezvous`. The
compiler also emits an implicit all-others landing pad that calls
`Exceptional_Complete_Rendezvous`; the probe records its handler lifecycle and
catch-all identity rather than treating it as optional.
The AArch64 local-object probe additionally emits `__clear_cache` for a nested
trampoline; the library-level product task type avoids that executable-stack
mechanism, and final ELF inspection rejects the symbol on both targets.

The product demonstration creates the server with ordinary Ada syntax, pins it
to the last configured Ada CPU, and calls it from the core-0 environment task.
The implementation queues a bounded call record, blocks each participant with
the common generation-tagged exact-wait mechanism, and performs both remote
wakes through Task_Core. All four architecture/CPU-count cells require the
returned `in out` value before emitting `FLYOLOGY:M4:RENDEZVOUS:PASS`.
Exceptional accept completion currently fails closed: exception-occurrence
copying and propagation to the caller have not yet been implemented or tested.
Conditional/timed calls, selective waits, entry families, requeue, abort, and
priority-ordered entry queues remain later M4 gates.

The language-defined `Ada.Dynamic_Priorities` facade follows
[Ada RM D.5.1](https://www.adaic.org/resources/add_content/standards/22rm/html/RM-D-5-1.html).
The owned `dynamic_priority_probe.adb` confirms that both targets retain
`Set_Priority`, `Get_Priority`, and `Current_Task` calls with the RM parameter
ordering. Flyology maps these calls to Task_Core's base-priority field; a Ready
task is removed and reinserted by the proved priority policy, and a remote
target receives a reschedule request. The proved ceiling model defers the
active effect of a base-priority change while a protected action is in
progress, then restores the new base at the outer leave.

The QEMU demonstration changes the blocked rendezvous server's base priority
from the environment task, verifies the target query, and has the server verify
the same value through the default-current-task call before completing the
cross-core rendezvous. `FLYOLOGY:M4:DYNAMIC_PRIORITY:PASS` is emitted only
after both observations. Interrupt-time priority preemption remains an M5
gate; this M4 checkpoint requests rescheduling at cooperative safe boundaries.

The owned `conditional_rendezvous_probe.adb` confirms that both target
compilers lower a conditional task entry call to `Task_Entry_Call` with
`Conditional_Call` and an out acceptance flag. Flyology performs the acceptor
test, call-record reservation, both wait publications, and exact server wake
under the one RTS lock. If no matching accept is already open, it returns
without allocating or queueing anything. The ordinary-Ada QEMU test requires
one cross-core conditional call to be accepted and a no-parameter call against
a delayed server to take the else branch without queueing; the delayed server
is then reached by a normal queued call through the observed `Accept_Trivial`
hook. This checkpoint does not yet include asynchronous entry calls.

The owned `timed_rendezvous_probe.adb` confirms the six-parameter
`Timed_Task_Entry_Call` profile on both targets: target, entry index,
parameter address, relative `Duration`, delay mode zero, and an out acceptance
flag. Flyology arms one `Timed_Object_Wait` token and registers that exact token
with the per-core timer table. Acceptance under the RTS lock cancels the exact
timer before exposing the call to the server; timeout resolves the same token,
and a later server scan discards the stale record rather than accepting it.

The QEMU image proves both outcomes with ordinary Ada: an open server completes
before a long timeout, while a delayed server loses to a short timeout and
subsequently accepts a fresh normal call. Only then is
`FLYOLOGY:M4:TIMED_ENTRY:PASS` emitted. The test is deterministic rather than a
full boundary-race stress campaign; repeated accept/timeout collision stress
remains required before M4 closes.

The owned `dynamic_task_probe.adb` uses an allocator for an ordinary task type.
Both target compilers emit the same allocation and lifecycle surface:
`__gnat_malloc`, a local `Activation_Chain`, `Create_Task`, `Activate_Tasks`,
`Expunge_Unactivated_Tasks`, ordinary task completion, and lexical master
completion. The AArch64 local probe alone adds `__clear_cache`; the product
uses a package-level task body and final inspection continues to prohibit that
symbol. Successful activation consumes the temporary chain before its cleanup
hook runs. An unconsumed chain still fails closed because partial activation
cleanup has not yet been implemented.

The allocator is a checked 64-KiB, 16-byte-aligned monotonic pool. Exhaustion
enters the compiler's `Storage_Error` check path instead of returning null.
The QEMU demonstration allocates a task with ordinary `new`, observes its
stable language identity and normal termination only after its lexical master
returns, and emits `FLYOLOGY:M4:DYNAMIC_TASK:PASS` in all four architecture and
CPU-count cells. Adding the allocator also exposed and fixed an earlier
lifecycle omission: the registered environment task now owns an open root
master before application package elaboration can query `Current_Master`.

This allocation checkpoint deliberately does not claim `Unchecked_Deallocation`,
`Free_Task`, allocation-pool reuse, unactivated-task expunging, or abort.

The owned `selective_wait_probe.adb` confirms that both compilers construct an
`Accept_List`, mark a null accept body in its `Accept_Alternative`, and call
`System.Tasking.Rendezvous.Selective_Wait` with `Terminate_Mode`, an out
parameter address, and an out selected alternative index. AArch64 again adds
only the local-probe cache trampoline; the package-level product task avoids
it and the ELF gate rejects it.

Flyology's first selective-wait increment accepts exactly one alternative. It
uses the established rendezvous call table and generation-tagged waits, and
completes a compiler-marked null body before returning its selected index. The
ordinary-Ada demonstration couples that server with a concurrent client and
requires master-observed task completion before
`FLYOLOGY:M4:SELECTIVE_WAIT:PASS` in every QEMU cell. Although the compiler
surface includes `Terminate_Mode`, this checkpoint does not yet implement the
openness/dependency rules that permit a terminate alternative to be selected;
the demonstrated client always calls the accept alternative. Multiple
alternatives, guarded alternatives, else/delay alternatives, timed selective
wait, and priority queueing remain M4 work.

Normal task destruction now separates the stable language identity from its
bounded execution slot. After the owning master has observed every dependent
termination, Task_Core verifies that the exact incarnation is terminated,
not current, absent from every ready queue and timer table, has no active wait,
and retains its stack canary. It then releases only the execution record,
context, and stack slot. The next occupant receives the SPARK-checked successor
incarnation; wrap or the reserved zero incarnation fails closed.

The QEMU image creates more cumulative ordinary tasks than the 15 non-
environment execution slots while retaining earlier standard `Task_Id` values.
Later tasks validate their reused stack bounds, and the old identities remain
pairwise distinct, terminated, and not callable before
`FLYOLOGY:M4:RECLAMATION:PASS`. The stable identity table is bounded at 32 and
is deliberately not reused yet. This does not claim `Unchecked_Deallocation`,
`Free_Task`, allocation-pool reuse, or freeing an identity retained by user
code; those require the explicit compiler deallocation hook and lifetime rules.

## Abort checkpoint

The owned `abort_probe.adb` confirms on both pinned cross targets that a plain
Ada `abort Worker` statement constructs a `System.Tasking.Task_List` and calls
`System.Tasking.Stages.Abort_Tasks`. The target wrapper's compiler-generated
cleanup defers abort, calls `Complete_Task`, calls `Abort_Undefer`, and
continues the
generic unwind. The separate owned `task_root_probe.adb` records the minimal
catch-all handler surface used to contain that unwind before a dead task stack
is retired. These probes establish compiler shape; the QEMU test establishes
the implemented behavior.

Flyology records an abort request in the stable task record under the single
RTS lock. For the supported blocked-delay path it retrieves the task's current
generation-tagged wait token, cancels that exact deadline, and resolves the
same wait with `Abort_Wake`. Timeout and abort therefore cannot both win or
enqueue the task twice. Delivery occurs only with abort depth zero: the runtime
clears the pending request, marks delivery in progress to make duplicate abort
requests idempotent, and raises a private bounded exception occurrence. The
compiler cleanup marks completion, and the task-root handler contains the
unwind before normal Task_Core termination, exact master notification, stack
canary validation, and execution-slot reclamation.

The ordinary-Ada demonstration lets a pinned task enter a one-second delay,
aborts it from the environment task, rejects execution after the delay, and
requires the retained language identity to be terminated and not callable
before `FLYOLOGY:M4:ABORT:PASS`. On SMP4 the target is pinned to the last core,
so deadline cancellation and wakeup cross cores; SMP1 covers the same state
machine locally. This checkpoint intentionally does not claim asynchronous
abort of a CPU-bound task, abort of rendezvous/protected-entry waits,
abort-before-activation, multi-task abort statements, ATC, or full abnormal
master/exception semantics.
The current minimal personality treats its catch-all identity as matching the
private abort occurrence so the task root can contain it; application-level
handlers around an abortible operation are therefore not yet a conforming
abort boundary and are outside this checkpoint.
Interrupt-time forced delivery and the decisive no-safe-point behavior remain
M5 work.
