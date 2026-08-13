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
path. It does not yet establish exception occurrences/messages, nested handler
replacement, re-raise, task-root containment, abort delivery, allocation
reclamation, or abnormal master semantics. Those require additional ordinary
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
only after their lexical master observes all completions. Absolute delays,
timed entry calls, and cancellation races remain separate M4 gates.

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
