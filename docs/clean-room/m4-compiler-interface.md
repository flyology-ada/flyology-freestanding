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
