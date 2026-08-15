# synchronization capability synchronization and exception interface evidence

This record is limited to Flyology Freestanding-owned probes, compiler-generated expansion,
ALI metadata, object relocations/disassembly, the public two-phase unwind ABI,
and black-box execution. No GNAT runtime source was inspected or copied.

## Exception boundary

The owned `probes/synchronization/exception_probe.adb` produces the same compiler-facing
surface on both pinned GNAT 15.3 targets: `_Unwind_Resume`,
`__gnat_personality_v0`, `__gnat_begin_handler_v1`,
`__gnat_end_handler_v1`, the Program_Error check entry, and the
`program_error` identity. The landing pad receives the generic unwind object
and selector in the target's standard exception data registers. Its normal
handler lifecycle is `begin_handler_v1(object)` followed by
`end_handler_v1(object, cookie, null)`.

Flyology Freestanding implements the Ada-specific exception object, LSDA matching,
personality, handler lifecycle, bounded allocation, and fail-closed behavior in
original code. It links the generic `libgcc` DWARF unwinder shipped inside each
pinned cross-toolchain; no copy is placed in the repository. This is a GCC
Runtime Library component governed by its upstream license and GCC Runtime
Library Exception, not original dual-licensed Flyology Freestanding material.
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

The task-root symbol is weak so the isolated exception probe can omit the full
tasking runtime. With the pinned C compilers, x86-64 emits two relocations to
`flyology_freestanding_task_root_invoke` for the availability check and region-start
comparison, while AArch64 folds the same expression into one relocation. The
unwind gate pins those target-specific shapes and still requires exactly one
`__register_frame` call.

`scripts/build-exception-probe.sh` builds a zero-unresolved freestanding image.
`scripts/run-exception-probe.sh` requires a caught Program_Error pass and unique
online-core markers under the pinned QEMU/UEFI contract for SMP1 and SMP4.
The Ada closure is owned by `gpr/flyology_freestanding_exception_probe.gpr`; the shell retains
only binder, architecture, C unwinder, linker, and boot-media composition. The
authoritative `scripts/verify-synchronization.sh` gate builds and runs all four
architecture/SMP cells, so this evidence cannot silently become documentary
only. The isolated image executes the allocator/unwinder probe only on the BSP;
its test-only allocator-lock adapter is therefore single-caller. Product images
link the same allocator arithmetic to the SMP runtime lock instead.

Removing only `No_Exception_Propagation` from the product configuration adds
one exact compiler-required source boundary on both targets:
`System.Soft_Links.Save_Library_Occurrence
(Ada.Exceptions.Exception_Occurrence_Access)`. Generated finalizers pass null,
and the binder later calls `__gnat_reraise_library_exception_if_any` after all
library finalizers. Flyology Freestanding snapshots only the first current exception
identity and reraises it once; messages and tracebacks remain unsupported.

Generated exceptional protected-entry and rendezvous handlers call
`Begin_Handler`, query `Get_Gnat_Exception`, call the exceptional completion
hook, and then call `End_Handler`. Flyology Freestanding therefore keeps a bounded current
handler stack per exact task slot, not per core, so a blocking handler does not
expose another task's occurrence. A separate bounded propagation stack per task
carries unwind identities through phase-two finalizers before `Begin_Handler`
runs. A nested exception that is raised and handled during outer cleanup pops
only its own propagation context; the outer context becomes current again.
Handler and propagation depths are published with release stores and observed
with acquire loads before cross-core task-slot reclamation; stack entries are
written before their corresponding depth publication. The RTS lock still owns
the Ada lifecycle transition, while this narrow atomic boundary makes the C
unwind state visible to the master that releases an execution slot.
Every owned exception also records the exact task slot that reserved it.
Unwind deletion removes every reference to that object from the owner's
propagation stack before it release-publishes the pool entry as free. A stale
propagation reference therefore cannot silently name a later exception that
reuses the same bounded pool address; retirement still fails closed if a
genuinely live occupied exception remains.
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
bind these facades to the single kernel state authority and exact-token wait
arbitration rather than introduce a second scheduler or public task API.

The native GNAT 15.3 expansion of the owned delay probe lowers relative
`delay 0.001` to `Ada.Calendar.Delays.Delay_For (Duration)`. Flyology Freestanding's owned
facade routes that call through checked nanosecond-to-tick conversion, the
per-core exact-token timer table, and the common wait arbitration kernel. The
conversion splits a positive interval into checked whole seconds and a
sub-second remainder. Only the bounded remainder is scaled as fixed point;
the billion-scale whole-second operation uses checked integer arithmetic, so
it never forms the overflowing fixed-point intermediate
`Interval * 1_000_000_000`. The repeated multi-abort gate enters a valid
ten-second relative delay on both architectures and thus guards this boundary
as well as abort arbitration. The
ordinary-task QEMU gate requires four simultaneous delayed tasks in the SMP4
image, rejects early resume by comparing the architecture clock with the
registered absolute deadline, and emits one `FLYOLOGY:RTS:DELAYS:PASS` marker
only after their lexical master observes all completions. Absolute delays and
the bounded cancellation races exercised by timed entry calls use the same
kernel and are covered below.

The owned `absolute_delay_probe.adb` confirms on both targets that an Ada
`delay until` statement lowers to `Ada.Real_Time.Delays.Delay_Until (Time)`.
Flyology Freestanding represents `Ada.Real_Time.Time` as the validated architecture tick,
implements `Clock`, `Milliseconds`, time addition and comparison, and routes
the absolute deadline into the same per-core timer and exact-wait path used by
relative delay. The implementation checks conversion and deadline addition
before publishing a wait.

The ordinary-Ada image waits for a future absolute deadline, rejects any early
resume, then repeats `delay until` on the expired deadline to prove the
nonblocking path. All four QEMU cells require one
`FLYOLOGY:RTS:ABSOLUTE_DELAY:PASS` marker. This checkpoint does not yet provide
the full `Ada.Real_Time` arithmetic/conversion surface. Until exception
registration is implemented, the language-defined `Time_Error` name aliases
the existing `Program_Error` identity and only fail-closed error paths are
claimed; no test exercises an overflow condition as conforming `Time_Error`
propagation.

The owned `base_protected_probe.adb` forces aggregate protected state so GNAT
cannot lower the object to scalar lock-free atomics. It declares an explicit
`Priority => 8`; both cross compilers retain that aspect as an
`Any_Priority` value and pass it directly to `Initialize_Protection`. This
probe also corrects the clean-room `System.Any_Priority` declaration to the
ARM-shaped subtype of `Integer`, rather than a distinct integer type. Both
cross compilers then emit the same base lifecycle: `Protection` default
initialization,
`Initialize_Protection`, abort deferral, `Lock` or `Lock_Read_Only`, `Unlock`,
and `Finalize_Protection`, plus attachment through the compiler-required
finalization node. AArch64 additionally references `__clear_cache` for its
local trampoline; the probe gate records this target-specific difference
rather than hiding it. The product demonstration uses a library-level callback
and has no cache-trampoline dependency.

Flyology Freestanding implements those profiles from owned declarations. Lock and unlock
hold the existing nestable global RTS critical section across the protected
body and update the current task's proved nested ceiling state. Thus protected
actions are globally serialized while unrelated application code continues in
parallel on other cores. The QEMU gate requires four automatically placed
ordinary tasks to update a two-word protected counter after their delays and
the master to observe the exact total before
`FLYOLOGY:RTS:PROTECTED:PASS`.

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
RTS lock is held, then uses kernel's atomic block-and-release handoff. The
opening protected procedure evaluates barriers under the same lock, executes
the selected action, removes exactly that call, enqueues the exact waiter once,
releases the protected action, and only then sends the local or remote
reschedule notification. The ordinary-Ada gate blocks two tasks on the entry,
proves neither passed while closed, opens it from the environment task, checks
that the protected entry bodies ran in call order, and requires master-observed
completion before
`FLYOLOGY:RTS:PROTECTED_ENTRY:PASS` on x86-64 and AArch64 at SMP1 and SMP4.
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
`FLYOLOGY:RTS:FINALIZATION:PASS`. The QEMU gate requires that marker exactly
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
gate requires the immediate handler before
`FLYOLOGY:RTS:EXCEPTIONAL_PROTECTED_IMMEDIATE:PASS`, then a cross-core queued
handler, a subsequent normally serviced call, and an empty entry queue before
`FLYOLOGY:RTS:EXCEPTIONAL_PROTECTED_QUEUED:PASS`. The abort-over-transferred-
exception case must pass before `FLYOLOGY:RTS:EXCEPTION_ABORT_PROTECTED:PASS`,
and both rendezvous participants must catch the transferred identity before
`FLYOLOGY:RTS:EXCEPTIONAL_RENDEZVOUS:PASS`. The aggregate
`FLYOLOGY:RTS:EXCEPTIONAL_SYNC:PASS` follows all four boundaries. Only exception
identity is preserved; messages and tracebacks are not copied.

An owned hosted GNAT 15.3 black-box queues a protected entry, begins its action,
requests abort of the caller, and then lets that action raise Constraint_Error.
The caller's named handler must not execute: abort is delivered at the end of
the abort-deferred call before the transferred exception. The product gate
forces the same rule without a runtime test hook. It pins the blocked caller to
the environment core, completes the failing entry from the environment task,
and issues an ordinary Ada abort before cooperative synchronization capability can resume that caller.
The retained completion record is cleared first, then the shared checked
delivery boundary chooses deliverable abort ahead of the stored exception.

This checkpoint does not claim absolute-delay timed protected calls, entry
families, requeue, priority-ordered entry service, or concurrent finalized-
object access.

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
wakes through the kernel. All four architecture/CPU-count cells require the
returned `in out` value before emitting `FLYOLOGY:RTS:RENDEZVOUS:PASS`.

For exceptional accept completion, the accepted call record remains owned by
the caller and changes from `Accepted` to `Completed_Exceptional`. The server
stores a stable exception identity, exact-wakes the caller, clears its active
call ownership, and reraises the original occurrence. The caller consumes and
clears the retained record before raising a fresh occurrence with the same
identity. The ordinary-Ada gate requires Program_Error handlers in both server
and caller, normal master completion, and the shared exceptional-sync marker.
An additional accepted rendezvous holds its server in an abort-deferred delay,
requests caller abort, and only then raises Program_Error. The client must
terminate without entering its Program_Error handler. The same outcome is
pinned by an owned hosted GNAT 15.3 black-box. Only after both this rendezvous
case and the protected-entry case terminate with empty retained records does
the product emit `FLYOLOGY:RTS:EXCEPTION_ABORT:PASS`.

This identity-only transfer is not full Exception_Occurrence copying.
Asynchronous calls, entry families, requeue, and priority-ordered entry queues
remain unsupported outside the bounded synchronization capability outcome.

The language-defined `Ada.Dynamic_Priorities` facade follows
[Ada RM D.5.1](https://www.adaic.org/resources/add_content/standards/22rm/html/RM-D-5-1.html).
The owned `dynamic_priority_probe.adb` confirms that both targets retain
`Set_Priority`, `Get_Priority`, and `Current_Task` calls with the RM parameter
ordering. Flyology Freestanding maps these calls to kernel's base-priority field; a Ready
task is removed and reinserted by the proved priority policy, and a remote
target receives a reschedule request. The proved ceiling model defers the
active effect of a base-priority change while a protected action is in
progress, then restores the new base at the outer leave.

The QEMU demonstration changes two callers while both are blocked on one
protected entry, then releases them together. Entry service remains FIFO, but
the proved ready policy dispatches the higher-priority caller first; the test
records both independent orders. It separately changes a blocked rendezvous
server's base priority from the environment task, verifies the target query,
and has the server verify the same value through the default-current-task call
before completing the cross-core rendezvous.
`FLYOLOGY:RTS:DYNAMIC_PRIORITY:PASS` is emitted only after all observations.

Two configured protected objects exercise ceilings 8 and 10. A caller at
priority 9 is rejected before the ceiling-8 body runs. An admitted caller
changes its base from 2 to 3 inside the ceiling-8 action; the test-only passive
observer sees active priority remain 8, rise to 10 for a nested protected
action, return to 8, and finally restore to the new base 3 at outer unlock.
Only then is `FLYOLOGY:RTS:CEILING:PASS` emitted. Interrupt-time priority
preemption remains an preemption capability gate; this synchronization capability checkpoint requests rescheduling at
cooperative safe boundaries.

The owned `conditional_rendezvous_probe.adb` confirms that both target
compilers lower a conditional task entry call to `Task_Entry_Call` with
`Conditional_Call` and an out acceptance flag. Flyology Freestanding performs the acceptor
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
flag. Flyology Freestanding arms one `Timed_Object_Wait` token and registers that exact token
with the per-core timer table. Acceptance under the RTS lock cancels the exact
timer before exposing the call to the server; timeout resolves the same token,
and a later server scan discards the stale record rather than accepting it.

The QEMU image proves both outcomes with ordinary Ada: an open server completes
before a long timeout, while a delayed server loses to a short timeout and
subsequently accepts a fresh normal call. Only then is
`FLYOLOGY:RTS:TIMED_ENTRY:PASS` emitted. The later six-case collision campaign
adds equal-boundary accept/timeout/abort ordering and is repeated by the SMP4
stress gate.

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
hook runs. Flyology Freestanding now prevalidates a nonempty unconsumed chain under the one
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

The allocator is a bounded 64-KiB pool divided into 4,096 16-byte units. The
production `Flyology_Freestanding.Allocator` SPARK package owns the exact occupancy, head
length, live-count, and live-byte state. Under the existing recursive RTS
critical section, its deterministic first-fit selection marks a complete free
run and records its exact head and length. Raw free
accepts null, but rejects an interior, stale, out-of-pool, or double-free
pointer before changing metadata; a valid release clears the exact run, so
adjacent free ranges are immediately reusable without a second free-list
authority. A zero-size request consumes one unit. Exhaustion enters the
compiler's `Storage_Error` check path instead of returning null.

The thin Ada `Flyology_Freestanding.Allocator_ABI` package owns the aligned byte pool,
converts raw addresses to checked offsets, serializes state transitions with the
existing RTS lock, and exports the observed `malloc`, `free`, `__gnat_malloc`,
and `__gnat_free` C conventions. It contains no independent selection or
metadata algorithm. A pinned native Ada eight-task test uses the exact
production state package and covers alignment, pairwise-disjoint simultaneously
live allocations, first-fit hole reuse, exact live-byte accounting, whole-pool
recovery after fragmentation, capacity edges, zero-size uniqueness, and
unchanged state after invalid or duplicate releases. Both target QEMU images
catch `Storage_Error` from
an ordinary Ada 65,537-byte allocator request, release a small object through
compiler-lowered `Ada.Unchecked_Deallocation`, then allocate, validate, and
release forty 4-KiB objects sequentially. The cumulative traffic exceeds the
entire pool twice and cannot reach `FLYOLOGY:RTS:ALLOCATOR_TARGET:PASS` if raw
free remains a no-op. The unwind gate requires FDEs covering both
`__gnat_malloc` and `__gnat_free` on each target.
The QEMU demonstration allocates a task with ordinary `new`, then uses standard
`Is_Terminated` under a bounded real-time deadline to observe its stable
language identity and normal termination. It does not incorrectly treat return
from the allocating helper as a master-completion boundary: the access type's
collection has the wider library-level lifetime. Only after that explicit
observation does it emit `FLYOLOGY:RTS:DYNAMIC_TASK:PASS` in all four
architecture and CPU-count cells. Adding the allocator also exposed and fixed
an earlier lifecycle omission: the registered environment task now owns an
open root master before application package elaboration can query
`Current_Master`.

The owned `abort_dynamic_probe.adb` is also compiled against the pinned hosted
GNAT 15.3 runtime as black-box lowering evidence. Its generated relocation
order is `Abort_Tasks`, `System.Tasking.Stages.Free_Task`, then raw
`__gnat_free`; only after those calls does the generated instance null the
access value. The exact `Free_Task (Item : Task_Id)` profile and ordering are
therefore observed rather than guessed. Flyology Freestanding supplies the ARM-prescribed
generic declaration, including `Preelaborate` and intrinsic convention, but no
generic body. Both cross compilers then perform the same intrinsic lowering
directly to the clean-room `System.Tasking.Stages.Free_Task`, raw free, and
access nulling. This avoids a second object-address lifecycle API and lets the
compiler pass the exact stable `Task_Id` it created.

The product gate repeatedly creates a task pinned to the last configured Ada
CPU, observes that it has started, and invokes ordinary
`Ada.Unchecked_Deallocation` without a preceding abort statement. `Free_Task`
issues the task abort itself and blocks the environment task on an
exact termination token if the target has not yet completed dispatcher-side
retirement. The target is held inside an accepted, abort-deferred rendezvous
until the test releases its independent server; this causally exercises the
termination-wait path rather than relying on elapsed time. Only the dispatcher,
after switching off the victim stack, marks
the identity terminated and wakes that exact waiter. The deallocator then
validates the terminated incarnation, releases its execution slot and stack,
advances the incarnation, calls raw free, and nulls the access value. Sixteen
iterations exceed the fifteen non-environment execution slots, so
`FLYOLOGY:RTS:FREE_TASK:PASS` cannot be reached if any execution slot leaks.
Every retained old `Task_Id` remains terminated and not callable. GNAT's
expansion captures the master at the access-type declaration, so a legal
deallocator is itself within the master relation that must finish before
lexical master cleanup can reclaim the dependent. The product relies on that
compiler-observed accessibility/master invariant rather than adding a second
reclamation-reservation state machine.

The gate also aborts a second task while it is itself blocked inside
`Free_Task`. A termination wait deliberately retains that pending abort until
the target's natural retirement wake lets the compiler's indivisible
`Free_Task`/raw-free/null sequence finish; the freer then reaches a delay safe
point and terminates by abort. The test requires the shared access value to be
null first, rejects continuation past that safe point, and subsequently reuses
the released execution slot. Raw free now releases the dynamic heap object's
exact allocation after this task-lifecycle transaction, so the checkpoint
covers execution-slot, stack, and heap-object reuse as three distinct
lifetimes while retaining the stable language identity tombstone. General
controlled-object adjustment/finalization races remain outside the exercised
bounded semantics.

The owned `selective_wait_probe.adb` confirms that both compilers construct an
`Accept_List`, mark a null accept body in its `Accept_Alternative`, and call
`System.Tasking.Rendezvous.Selective_Wait` with `Terminate_Mode`, an out
parameter address, and an out selected alternative index. AArch64 again adds
only the local-probe cache trampoline; the package-level product task avoids
it and the ELF gate rejects it.

Flyology Freestanding's selective-wait increment accepts exactly one alternative. It uses
the established rendezvous call table and generation-tagged waits, and
completes a compiler-marked null body before returning its selected index. The
ordinary-Ada demonstration couples that server with a concurrent client and
requires master-observed task completion before
`FLYOLOGY:RTS:SELECTIVE_WAIT:PASS` in every QEMU cell.

The terminate branch implements the collective rule from ARM 9.3. A task
publishes both its open terminate alternative and exact accept wait under the
RTS lock. The production wrapper constructs a bounded snapshot and calls the
SPARK `Termination_Model`; selection is permitted only after a depended-on
master is closed and every task transitively dependent on that master is
already terminated or similarly waiting. All selected waits are resolved in
one locked transaction. A queued call wins first if it was published first;
after collective selection, later calls receive `Tasking_Error`. GNAT's
generated task wrapper does not branch around statements following the select,
so the runtime raises an internal termination signal. The clean-room
personality admits that signal through compiler-generated cleanup handlers and
only the task-root containment frame; ordinary user `when others` handlers do
not intercept it, and it is not classified as abort.

The product declares two ordinary sibling tasks on CPU 1 and the last
configured CPU, makes no entry calls, and leaves their master. Both must have
published the open alternative before collective completion, neither may
execute its post-select statement, both identities must be terminated and not
callable, and only then is `FLYOLOGY:RTS:TERMINATE_ALTERNATIVE:PASS` emitted.
Multiple accept alternatives, guarded alternatives, else/delay alternatives,
timed selective wait, and priority queueing remain unsupported outside the
bounded synchronization capability outcome.

Normal task destruction now separates the stable language identity from its
bounded execution slot. Completion is also explicitly two-phase: the task
changes from `Running` to `Retiring` and relinquishes current-core ownership,
then switches to the independent per-core dispatcher stack. Only a callback
whose live stack address is validated inside that dispatcher extent may change
`Retiring` to `Terminated`, publish the standard identity state, decrement the
master, or wake its owner. A different core therefore cannot reclaim a stack
that still contains the terminating task's frames. After the owning master has
observed every dependent termination, the kernel verifies that the exact
incarnation is terminated,
not current, absent from every ready queue and timer table, has no active wait,
and retains its stack canary. It then releases only the execution record,
context, and stack slot. The next occupant receives the SPARK-checked successor
incarnation; wrap or the reserved zero incarnation fails closed.

The QEMU image creates more cumulative ordinary tasks than the 15 non-
environment execution slots while retaining earlier standard `Task_Id` values.
Later tasks validate their reused stack bounds, and the old identities remain
pairwise distinct, terminated, and not callable before
`FLYOLOGY:RTS:RECLAMATION:PASS`. The stable identity table is bounded at 256 and
is deliberately not reused yet. The compiler activation chain remains bounded
at 32 tasks, separately from the lifetime identity pool, so terminated
identities do not consume the live execution-slot capacity. Identity exhaustion
follows the checked `Storage_Error` path. The explicit `Free_Task` hook now
reclaims the execution slot while retaining the standard identity tombstone;
compiler raw free separately releases the heap object. The bounded stable
identity table remains deliberately unreclaimed.

## Abort checkpoint

The owned `abort_probe.adb` confirms on both pinned cross targets that a plain
two-name Ada abort statement constructs one two-element
`System.Tasking.Task_List` containing the exact task identities and calls
`System.Tasking.Stages.Abort_Tasks`. The target wrapper's compiler-generated
cleanup defers abort, calls `Complete_Task`, calls `Abort_Undefer`, and
continues the
generic unwind. The separate owned `task_root_probe.adb` records the minimal
catch-all handler surface used to contain that unwind before a dead task stack
is retired. These probes establish compiler shape; the QEMU test establishes
the implemented behavior.

Flyology Freestanding records an abort request in the stable task record under the single
RTS lock. For the supported blocked-delay path it retrieves the task's current
generation-tagged wait token, cancels that exact deadline, and resolves the
same wait with `Abort_Wake`. Timeout and abort therefore cannot both win or
enqueue the task twice. Delivery occurs only with abort depth zero: the runtime
clears the pending request, marks delivery in progress to make duplicate abort
requests idempotent, and raises a private bounded exception occurrence. The
compiler cleanup marks completion, and the task-root handler contains the
unwind before normal kernel termination, exact master notification, stack
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
before `FLYOLOGY:RTS:ABORT:PASS`. A repeated declaration places two tasks on
CPU 1 and the last configured CPU, waits until both are blocked in delays, and
executes one `abort First, Second` statement in each of four complete
create/block/abort/retire cycles. `Abort_Tasks` validates and
deduplicates the exact identities, rejects dormant named tasks before
publication, and serializes both requests under one RTS-lock acquisition;
both identities must be terminated and not callable, with neither continuation
executed, before `FLYOLOGY:RTS:MULTI_ABORT:PASS`. The repeated cycles force
bounded exception-pool and execution-slot reuse. SMP4 therefore covers four
atomic request plans spanning two cores, while SMP1 covers the same state
machine locally.

Before publishing that plan, the runtime also snapshots the direct lexical
master owner of every live task under the RTS lock. The SPARK
`Abort_Closure_Model` computes the exact transitive closure of the named tasks
over those owner links. Production rejects a dormant selected task or a
malformed owner before changing any abort state, then applies the existing
single-winner abort path to every selected exact task reference while still
holding the same lock. The ordinary-Ada gate creates a child task inside a
parent task body, pins the parent to the last configured CPU and the child to
CPU 1, and names only the parent in the abort statement. Both language
identities must become terminated and not callable, and neither body may run
past its interrupted delay, before
`FLYOLOGY:RTS:DEPENDENT_ABORT:PASS`. SMP4 therefore exercises a remote
dependent wake while SMP1 covers the same ownership closure locally.

This checkpoint intentionally does not claim asynchronous abort of a
CPU-bound task, abort-before-activation or dormant dependent cancellation,
ATC, or full abnormal master/exception semantics.
The private abort identity does not match an ordinary `when others`. Compiler
zero-filter action-chain cleanups continue during phase two without terminating
phase-one search. Compiler `all_others` is a real internal handler used by the
generated exceptional synchronization wrappers, so those hooks must explicitly
preserve or continue the executing task's original occurrence. One exported,
LSDA-bearing `flyology_freestanding_task_root_invoke` boundary is the only ordinary-catch
region allowed to contain abort. The demonstration places a user
`when others` around the interrupted delay and fails if it runs, then requires
the compiler task finalizer and runtime root to terminate the task normally.
The current abort tests do not claim an abort collision inside an exceptional
accept or protected-entry action. Interrupt-time forced delivery and the
decisive no-safe-point behavior remain preemption capability work.

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
abort before returning to user code. `FLYOLOGY:RTS:ABORT_RENDEZVOUS:PASS`,
`FLYOLOGY:RTS:ABORT_TIMEOUT:PASS`, and `FLYOLOGY:RTS:ABORT_ACCEPTED:PASS` are
required in every QEMU cell and every SMP4 stress repeat. The timing is
driven by a passive exact queued-call count read under the RTS lock, so abort is
requested only after the compiler-created caller record is actually published.
The observer does not schedule, wake, or create tasks. A subsequent bounded
collision campaign creates a fresh server and timed caller for each of six
orderings: acceptance before timeout, timeout before acceptance, abort of an
unaccepted caller, an equal accept/timeout boundary, abort just before that
boundary, and abort while an accepted rendezvous is held open. Each case
requires exactly one server acceptance, exact caller termination, exactly one
normal timed outcome when not aborted, no queued call, and normal server master
completion. The server and caller use separate compiler activation chains so
activation handshakes are not mistaken for rendezvous arbitration evidence.

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
before `FLYOLOGY:RTS:ABORT_PROTECTED:PASS`. SMP4 exercises the remote wake path
while SMP1 exercises the same arbitration locally. A six-case follow-on
campaign covers service before timeout, timeout before service, abort before
service, service at the timeout boundary, abort immediately before that
boundary, and service followed immediately by an abort request. In the last two
cases the remote caller may legitimately resume before or after the environment
issues abort, so the gate accepts either one normal winner or abort. Every case
requires exactly one terminal outcome, a zero entry count, terminated/noncallable
caller identity, and a fresh successful protected call afterward. The shared
`FLYOLOGY:RTS:COLLISION_STRESS:PASS` marker is emitted only after both the task-
entry and protected-entry campaigns complete. These forced orderings are
bounded production integration stress, not an exhaustive concurrency proof.

## Model and stress closure gates

The authoritative synchronization capability host model enumerates 224,969 deterministic operations
over the production wait-arbitration, exact FIFO token, deadline, priority,
ceiling, clock, allocator-arithmetic, exceptional-completion, and collective-
termination kernels, plus the fixed-capacity abort-owner closure. It
enumerates winner-before-block and winner-after-commit for normal wake,
timeout, and abort; every second resolution is required to be a
state-preserving duplicate. Stale task incarnations, stale/future wait
generations, invalid phases, full/duplicate queues, exact queue removal,
deadline cancellation and order, priority reordering, ceiling
overflow/violation, and checked conversion boundaries are also enumerated.
All 256 occupancy patterns in the lower half of the bounded allocator map are
combined with request lengths one through four; the model requires the first
legal run and proves that marking then releasing that exact run restores the
complete prior map.
Every four-task owner-map shape and named-task subset is closed over the same
16-slot model used by production, with every output bit serialized into the
pinned hash. Every completion phase is checked for legal normal/exceptional
completion, consumption, identity-presence, and abort-before-transferred-
exception delivery invariants. The gate pins both
the edge count and serialized-state hash so an accidental search reduction
fails. The current serialized GNATprove 16.1 gate reports all 543 generated
checks proved across the
SPARK-analyzed deterministic primitive units, including the exact allocator
state engine. The data-only `Task_Primitives` token package is analyzed, but the
concurrent `Flyology_Freestanding.Kernel`, compiler-facing GNARL facades, architecture
assembly, C unwinder, and synchronized allocator address/critical-section
facade remain outside SPARK behind typed boundaries.

`scripts/stress-synchronization.sh` complements that pure model with ten complete SMP4
ordinary-Ada runs per architecture. Each run repeats cross-core delay wakeups,
conditional and timed protected entries, rendezvous and timed calls, dynamic
priority changes, master observation, abort against delay/rendezvous/protected
wakes, the six-case protected and rendezvous collision campaigns, execution-
slot reclamation, and post-`adafinal` protected-object teardown. The baseline
image also performs cumulative dynamic heap traffic
larger than the bounded pool. These runs exercise the production global lock,
architecture timer,
IPI/SGI, context switch, and compiler wrappers; they are bounded integration
stress, not an exhaustive concurrent-state proof. Interrupt-time forced task
preemption remains preemption capability.
