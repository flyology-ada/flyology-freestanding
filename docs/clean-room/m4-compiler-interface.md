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

Both linkers retain every C and Ada frame in one contiguous `.eh_frame` table
with one final terminator. Exception initialization registers that table
exactly once from `__eh_frame_start`; an interior FDE is not a valid second
registration root. The C runtime is compiled with `-funwind-tables`; omitting
it is a negative condition that prevents AArch64 from reaching the Ada
personality.

`scripts/build-m4-exception.sh` builds a zero-unresolved freestanding image.
`scripts/run-m4-exception.sh` requires a caught Program_Error pass and unique
online-core markers under the pinned QEMU/UEFI contract for SMP1 and SMP4.

Removing only `No_Exception_Propagation` from the product configuration adds
one exact compiler-required source boundary on both targets:
`System.Soft_Links.Save_Library_Occurrence
(Ada.Exceptions.Exception_Occurrence_Access)`. Generated finalizers pass null,
and the binder later calls `__gnat_reraise_library_exception_if_any` after all
library finalizers. Flyology snapshots only the first current exception
identity and reraises it once; messages and tracebacks remain unsupported.

Generated exceptional protected-entry and rendezvous handlers call
`Begin_Handler`, query `Get_Gnat_Exception`, call the exceptional completion
hook, and then call `End_Handler`. Flyology therefore keeps a bounded current
handler stack per exact task slot, not per core, so a blocking handler does not
expose another task's occurrence. A separate bounded propagation stack per task
carries unwind identities through phase-two finalizers before `Begin_Handler`
runs. A nested exception that is raised and handled during outer cleanup pops
only its own propagation context; the outer context becomes current again.
The compiler-visible occurrence record is deliberately opaque; product
semantics currently preserve only the raw current handle returned through
`Get_Gnat_Exception` and a stable exception identity snapshot.

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
`FLYOLOGY:M4:PROTECTED:PASS`.

The owned `protected_probe.adb` now records the protected-entry compiler
boundary independently on both cross targets. GNAT constructs an array of
barrier/action callbacks, initializes `Protection_Entries` with the enclosing
object address and body-index mapper, and lowers an ordinary call through a
`Communication_Block` and `Protected_Entry_Call`. A protected procedure ends
through `Service_Entries`; a function uses `Unlock_Entries`; normal entry-body
completion calls `Complete_Entry_Body`. AArch64 adds only its already observed
local-trampoline `__clear_cache` reference, which the package-level product
object avoids.

The product representation owns a bounded 16-call queue using the proved
exact-token FIFO wait-queue model. A closed barrier
publishes the caller's exact task reference and wait generation while the one
RTS lock is held, then uses Task_Core's atomic block-and-release handoff. The
opening protected procedure evaluates barriers under the same lock, executes
the selected action, removes exactly that call, enqueues the exact waiter once,
releases the protected action, and only then sends the local or remote
reschedule notification. The ordinary-Ada gate blocks two tasks on the entry,
proves neither passed while closed, opens it from the environment task, checks
that the protected entry bodies ran in call order, and requires master-observed
completion before
`FLYOLOGY:M4:PROTECTED_ENTRY:PASS` on x86-64 and AArch64 at SMP1 and SMP4.
The separately owned `protected_conditional_probe.adb` establishes the
conditional-call lowering on both cross targets: GNAT passes
`Conditional_Call` through the same `Protected_Entry_Call` boundary and then
queries `Cancelled`; protected entry `'Count` calls `Protected_Count`. The
product evaluates the barrier while holding the protected-object lock and, if
it is closed, reports cancellation without publishing a wait token or adding a
queue member. The ordinary-Ada gate requires that rejection and a subsequent
zero entry count before starting the blocking FIFO test above.

The owned `protected_timed_probe.adb` establishes the duration-bearing
`Timed_Protected_Entry_Call` profile with both pinned cross compilers; an
independent owned native GNAT 15.3 probe produced the same call shape. This
required the exact compiler-facing type name
`System.Tasking.Call_Modes`; the earlier singular clean-room name caused an
invalid lowering and was removed. The product registers the same exact wait
token in the protected queue and per-core deadline table. Entry service
cancels that deadline before resolving the waiter, while expiry wins the
single wait outcome and removes the stale protected call under the same RTS
lock. The ordinary-Ada gate requires a closed timed call to time out and leave
entry `'Count` at zero before the blocking FIFO test.

The product no longer uses `No_Finalization`. Owned two-target expansion
evidence establishes the compiler-created controlled hierarchy, finalization
node attachment, named protected-object finalizer callback, and call to the
`Protection_Entries` `Finalize` override. The clean-room root uses the
compiler-recognized `Finalizable` implementation aspect solely to request that
metadata; no GNAT runtime source was consulted or copied. The product finalizer
fails closed unless the entry queue and every pending-call slot are empty,
marks the object uninitialized, and emits
`FLYOLOGY:M4:FINALIZATION:PASS`. The QEMU gate requires that marker exactly
once, after the binder calls the library finalizer during `adafinal`.

This is a bounded protected-entry teardown contract, not a claim for the full
`Ada.Finalization` or `Ada.Tags` APIs. Exception registration and tagged-type
registration remain disabled, task execution slots still use their explicit
lifecycle, and general controlled-object adjustment, user-defined tag queries,
and finalization races are not yet demonstrated.

Exceptional entry-body completion uses the same checked completion-phase
kernel as rendezvous. An immediate/open entry unlocks the protected action and
reraises the original occurrence to the direct caller. A queued entry changes
its exact retained record from `Queued` to `Completed_Exceptional`, snapshots
the stable exception identity, resolves the exact caller token once, and lets
the servicing task continue to later calls. The caller consumes and clears the
record before raising a fresh occurrence with that identity. The ordinary-Ada
gate requires both immediate and cross-core queued Program_Error handlers, a
subsequent normally serviced call, and an empty entry queue before the shared
`FLYOLOGY:M4:EXCEPTIONAL_SYNC:PASS` marker. Only exception identity is
preserved; messages and tracebacks are not copied. This checkpoint does not
claim absolute-delay timed protected calls, entry families, requeue,
priority-ordered entry service, simultaneous exceptional-completion versus
timeout/abort collisions, or concurrent finalized-object access.

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

For exceptional accept completion, the accepted call record remains owned by
the caller and changes from `Accepted` to `Completed_Exceptional`. The server
stores a stable exception identity, exact-wakes the caller, clears its active
call ownership, and reraises the original occurrence. The caller consumes and
clears the retained record before raising a fresh occurrence with the same
identity. The ordinary-Ada gate requires Program_Error handlers in both server
and caller, normal master completion, and the shared exceptional-sync marker.
This identity-only transfer is not full Exception_Occurrence copying, and
exception-versus-abort/timeout collision ordering remains an M4 closure gate.
Conditional/timed calls, selective waits, entry families, requeue, abort, and
priority-ordered entry queues remain later M4 gates where not separately
demonstrated below.

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

A timed-out queued call remains owned by its exact caller and wait token until
that caller resumes and clears the record. A server scan may skip a call whose
wait is no longer pending, but it cannot free or reuse that global call slot.
Timeout cleanup validates the original caller, token, timed flag, phase, and
current-task ownership under the RTS lock before reclamation. This prevents a
server from reusing the slot between timer wake and caller resumption.

The owned `dynamic_task_probe.adb` uses an allocator for an ordinary task type.
Both target compilers emit the same allocation and lifecycle surface:
`__gnat_malloc`, a local `Activation_Chain`, `Create_Task`, `Activate_Tasks`,
`Expunge_Unactivated_Tasks`, ordinary task completion, and lexical master
completion. The AArch64 local probe alone adds `__clear_cache`; the product
uses a package-level task body and final inspection continues to prohibit that
symbol. Successful activation consumes the temporary chain before its cleanup
hook runs. Flyology now prevalidates a nonempty unconsumed chain under the one
RTS lock, requires one exact master and dormant, unqueued, unwaiting task
incarnations, and only then cancels every member. Static declarative failure
does not emit that dynamic-chain hook, so `Complete_Master` performs the same
whole-set preflight and dormant cancellation before it waits for activated
dependents.

Activation failure is a separate path. A compiler wrapper that reaches
`Complete_Task` before `Complete_Activation` does not decrement the activation
group while it is still executing on its task stack. Dispatcher-side retirement
records the failed acknowledgement after the context switch, and the activator
wakes exactly once only after every successful sibling has acknowledged or
every failed sibling has retired. The compiler chain is then cleared and the
activator receives `Tasking_Error`. The ordinary-Ada QEMU test covers both a
static task that is never activated because a later declarative initializer
raises and a two-member activation group in which one task fails during body
declarative elaboration while its sibling runs normally.

The owned `activation_failure_probe.adb` pins that lowering independently on
both target compilers: the failing declarative initializer precedes
`Complete_Activation`, the task wrapper retains its mandatory `Complete_Task`
cleanup, and the surrounding scope retains `Activate_Tasks` plus master
completion. `Create_Task` also supplies the compiler-owned task-body elaboration
predicate. `Task_Start` validates that pointer; a false value bypasses the body
procedure and enters the same dispatcher-side failed-activation path. The
ordinary-Ada QEMU scenario exercises a raised task-body declarative initializer;
the false body-elaboration predicate is compiler-interface and checked-runtime
evidence, not a separately forced product-cell claim.

The allocator is a bounded 64-KiB, 16-byte-aligned monotonic pool. Exhaustion
enters the compiler's `Storage_Error` check path instead of returning null.
Checked reservation without cursor corruption and reclaiming allocation remain
M4 closure work.
The QEMU demonstration allocates a task with ordinary `new`, then uses standard
`Is_Terminated` under a bounded real-time deadline to observe its stable
language identity and normal termination. It does not incorrectly treat return
from the allocating helper as a master-completion boundary: the access type's
collection has the wider library-level lifetime. Only after that explicit
observation does it emit `FLYOLOGY:M4:DYNAMIC_TASK:PASS` in all four
architecture and CPU-count cells. Adding the allocator also exposed and fixed
an earlier lifecycle omission: the registered environment task now owns an
open root master before application package elaboration can query
`Current_Master`.

This allocation checkpoint deliberately does not claim `Unchecked_Deallocation`,
`Free_Task`, allocation-pool reuse, or dynamic heap-object reclamation.

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
bounded execution slot. Completion is also explicitly two-phase: the task
changes from `Running` to `Retiring` and relinquishes current-core ownership,
then switches to the independent per-core dispatcher stack. Only a callback
whose live stack address is validated inside that dispatcher extent may change
`Retiring` to `Terminated`, publish the standard identity state, decrement the
master, or wake its owner. A different core therefore cannot reclaim a stack
that still contains the terminating task's frames. After the owning master has
observed every dependent termination, Task_Core verifies that the exact
incarnation is terminated,
not current, absent from every ready queue and timer table, has no active wait,
and retains its stack canary. It then releases only the execution record,
context, and stack slot. The next occupant receives the SPARK-checked successor
incarnation; wrap or the reserved zero incarnation fails closed.

The QEMU image creates more cumulative ordinary tasks than the 15 non-
environment execution slots while retaining earlier standard `Task_Id` values.
Later tasks validate their reused stack bounds, and the old identities remain
pairwise distinct, terminated, and not callable before
`FLYOLOGY:M4:RECLAMATION:PASS`. The stable identity table is bounded at 128 and
is deliberately not reused yet. The compiler activation chain remains bounded
at 32 tasks, separately from the lifetime identity pool, so terminated
identities do not consume the live execution-slot capacity. Identity exhaustion
follows the checked `Storage_Error` path. This does not claim
`Unchecked_Deallocation`, `Free_Task`, allocation-pool reuse, or freeing an
identity retained by user code; those require the explicit compiler
deallocation hook and lifetime rules.

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

The SMP stress gate exposed the complementary abort-before-publication race: a
target could announce that it had started, receive an abort while still
Running, and then arm a delay after the request had been recorded. Every
GNARL blocking boundary now checks and consumes a deliverable pending abort
while holding the same RTS lock, before it publishes a wait token, deadline,
rendezvous call, protected-entry queue record, activation wait, or master wait.
Thus either the abort wins before publication or it competes through the exact
generation-tagged wait; there is no unobserved interval between those cases.

The ordinary-Ada demonstration lets a pinned task enter a one-second delay,
aborts it from the environment task, rejects execution after the delay, and
requires the retained language identity to be terminated and not callable
before `FLYOLOGY:M4:ABORT:PASS`. On SMP4 the target is pinned to the last core,
so deadline cancellation and wakeup cross cores; SMP1 covers the same state
machine locally. This checkpoint intentionally does not claim asynchronous
abort of a CPU-bound task, abort-before-activation, multi-task abort
statements, ATC, or full abnormal master/exception semantics.
The private abort identity does not match an ordinary `when others`. Compiler
zero-filter action-chain cleanups continue during phase two without terminating
phase-one search. Compiler `all_others` is a real internal handler used by the
generated exceptional synchronization wrappers, so those hooks must explicitly
preserve or continue the executing task's original occurrence. One exported,
LSDA-bearing `flyology_task_root_invoke` boundary is the only ordinary-catch
region allowed to contain abort. The demonstration places a user
`when others` around the interrupted delay and fails if it runs, then requires
the compiler task finalizer and runtime root to terminate the task normally.
The current abort tests do not claim an abort collision inside an exceptional
accept or protected-entry action. Interrupt-time forced delivery and the
decisive no-safe-point behavior remain M5 work.

The next abort-race increment extends the same single-winner rule to queued
task entry calls. If an unaccepted caller is aborted, the runtime matches the
call record by exact caller reference and wait token, removes it under the RTS
lock, cancels its exact deadline when the call is timed, and only then resolves
`Abort_Wake`. If acceptance won first, abort remains pending until normal
rendezvous completion, preserving the accepted-rendezvous deferral boundary.

Two ordinary-Ada tests pin a delayed server and its client to the last CPU.
The environment aborts an already queued client, then makes a fresh call that
the server must accept; this proves the stale call was not later selected. The
timed variant additionally requires that neither acceptance nor timeout code
runs in the aborted client. A third variant lets the server accept first and
remain inside the rendezvous while the environment requests abort; the caller
is woken normally only after the server completes, then delivers the retained
abort before returning to user code. `FLYOLOGY:M4:ABORT_RENDEZVOUS:PASS`,
`FLYOLOGY:M4:ABORT_TIMEOUT:PASS`, and `FLYOLOGY:M4:ABORT_ACCEPTED:PASS` are
required in every QEMU cell and every SMP4 stress repeat. The timing is
deliberately separated rather than a near-simultaneous boundary collision;
adversarial accept/timeout/abort ordering stress remains an M4 closure gate.

The protected-entry abort composition uses distinct protected wait kinds, so
it cannot be confused with a server-side rendezvous accept wait. An abort of a
blocked protected caller cancels its exact deadline when present and resolves
the same generation-tagged wait with `Abort_Wake`. On resumption the caller
removes its exact queue record and per-task parameter record while holding the
protected-object lock, then delivers the retained abort before returning to
user code. If entry service or timeout wins first, the existing single-winner
path removes the losing registration and delivers any concurrently retained
abort at the same safe boundary.

The ordinary-Ada test pins blocking and timed callers to the last configured
CPU. For each it waits until `Wait'Count` is one, aborts it from the
environment task, and requires normal master observation of termination, no
execution of the accepted/timeout/continuation paths, and a zero count. The
blocking case opens the gate immediately after the abort request, exercising
the race in which entry service removes the already-resolved stale record
before the caller resumes. The timed case checks exact deadline cancellation
before `FLYOLOGY:M4:ABORT_PROTECTED:PASS`. SMP4 exercises the remote wake path
while SMP1 exercises the same arbitration locally. This is deterministic
separated-order evidence; simultaneous service/timeout/abort stress remains
required before M4 closure.

## Model and stress closure gates

The authoritative M4 host model enumerates 32,540 deterministic operations
over the production wait-arbitration, exact FIFO token, deadline, priority,
ceiling, clock, and exceptional-completion kernels. It covers
winner-before-block and winner-after-
commit for normal wake, timeout, and abort; every second resolution is required
to be a state-preserving duplicate. Stale task incarnations, stale/future wait
generations, invalid phases, full/duplicate queues, exact queue removal,
deadline cancellation and order, priority
reordering, ceiling overflow/violation, and checked conversion boundaries are
also enumerated. Every completion phase is checked for legal normal/exceptional
completion, consumption, and identity-presence invariants. The gate pins both
the edge count and serialized-state hash so an accidental search reduction
fails. GNATprove 16.1 reports all 336 generated checks proved across the
SPARK-analyzed deterministic core units. The concurrent Task_Core facade, the
imported `Task_Primitives_Contract` declarations, compiler-facing GNARL
facades, architecture assembly, and C unwinder remain outside SPARK behind
typed boundaries.

`scripts/stress-m4.sh` complements that pure model with ten complete SMP4
ordinary-Ada runs per architecture. Each run repeats cross-core delay wakeups,
conditional and timed protected entries, rendezvous and timed calls, dynamic
priority changes, master observation, abort against delay/rendezvous/protected
waits, execution-slot reclamation, and post-`adafinal` protected-object
teardown. These runs exercise the production global lock, architecture timer,
IPI/SGI, context switch, and compiler wrappers; they are bounded integration
stress, not an exhaustive concurrent-state proof. Interrupt-time forced task
preemption remains M5.
