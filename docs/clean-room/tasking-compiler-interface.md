# tasking capability ordinary-task compiler interface evidence

This record is limited to Flyology Freestanding-owned sources under `probes/tasking/`, compiler-generated expansion/ALI/object diagnostics, and black-box compilation with the pinned GNAT 15.3 cross compilers. No GNAT runtime source was inspected or used.

The authoritative discovery command is `scripts/probe-tasking-interface.sh`. Generated expansion, undefined-symbol inventories, and objects remain ignored under `build/probes/tasking/`.

## Observed static-task surface

The automatic and `CPU => 1` task probe generates one lexical activation chain. Each task object initializer calls `System.Tasking.Stages.Create_Task` with, in order: priority, primary stack size, secondary stack size, task info, CPU, relative deadline, dispatching domain, base CPU, master, body procedure, discriminants address, elaborated flag, activation chain, task name, and output `Task_Id`. The automatic task passes `System.Tasking.Unspecified_CPU`; the pinned object stores and passes Ada CPU value 1.

The compiler-generated body wrapper calls `Complete_Activation` before user statements. Its mandatory finalizer calls the `Abort_Defer` soft link, `Complete_Task`, then the `Abort_Undefer` soft link. The enclosing scope calls `Enter_Master`, reads `Current_Master`, calls `Activate_Tasks` on the chain, and its finalizer brackets `Complete_Master` with abort deferral. These four master/abort hooks are data symbols containing access-to-subprogram values, not direct procedure symbols. The activation chain itself is merely limited private; no compiler-required controlled initialization/finalization operation exists. `Task'Identity` is derived directly from the compiler-generated task value record's `_task_id`; standard current/callable/terminated queries remain calls to `Ada.Task_Identification`.

An isolated owned hosted GNAT 15.3 black-box master experiment released a
dependent from the lexical body and observed that scope return followed its
completion. That experiment informed the design but is not an authoritative,
reproducible repository gate. The tracked expansion does establish the call
split: `Activate_Tasks` receives the activation chain, while the scope
finalizer invokes `Complete_Master`. The freestanding tasking capability QEMU gate verifies
normal activation acknowledgement and normal master waiting directly.

Both targets require the same task lifecycle symbols. AArch64 may additionally require `__clear_cache` when a generated executable trampoline is present. Both restricted and unrestricted normal task objects contain exception-unwind references; the current `No_Exception_Propagation` restriction therefore does not itself establish full cleanup or propagation semantics.

## Contract and limits

These observations establish compatibility names, profiles, ordering, and values—not runtime semantic conformance. The product implementation must keep one stable TCB-backed `Task_Id`, create tasks dormant on their activation chain, atomically admit the chain, map Ada CPU 1 to dense `Core_Id` 0 only after validation, execute the compiler wrapper on a distinct stack, and route completion through GNARL before dispatcher transfer.

Activation failure details, unactivated-task cleanup, full abnormal-master
semantics, exception propagation, abort, dynamic task reclamation, rendezvous,
protected objects, delays, and task attributes are not established by this
probe. tasking capability closes only the normal activation/completion/master path. Abnormal
and unactivated cleanup is an explicit synchronization capability gate and remains fail-closed here.

## Product implementation

The clean-room implementation of this observed surface lives under `src/gnarl/`
and delegates through `Flyology_Freestanding.RTS` to `Flyology_Freestanding.Kernel`. It uses
compiler-created task objects only: the staging facade
creates dormant bounded TCBs, activation publishes a whole lexical chain,
the core dispatcher selects ready work, and the compiler wrapper reports
activation and normal completion. There is no public task-creation, spawn, or
fiber API. Task slots and 64 KiB stacks are retained rather than reclaimed in
this tasking capability increment.

The demonstration deliberately uses library-level task *types* and local task
objects. That keeps compiler-created body entry points in executable text and
avoids an AArch64 `__clear_cache` dependency or executable-stack trampoline.
At SMP4, a task-type CPU aspect driven by a compiler-owned discriminant creates
four ordinary tasks with `CPU => 1 .. 4`; each checks the corresponding dense
core and all four must enter a barrier before any may finish. A second phase
assigns four tasks without CPU aspects to distinct eligible cores and uses an
independent barrier. At SMP1 the specific phase creates only `CPU => 1`, and
the four unpinned objects all run on core 0 without a multicore barrier. Each
lexical master observes termination, and standard identity/callable/terminated
queries validate the retained TCB identities. The owned placement probe records
the exact discriminant-to-`Create_Task` lowering on both target compilers.

Every task phase also validates a live aliased local object against its assigned
64 KiB stack extent. The dispatcher checks a slot-specific bottom canary after
every return, and normal completion checks it before retiring the task. A parent
ordinary task creates a nested ordinary child and cannot report completion until
its inner master has observed that child's termination; the environment master
then observes the parent. Slot 0 is deliberately excluded from the task-pool
canary rule because the environment owns the independently validated BSP stack.

The compiler still emits unwind metadata and references for task finalizers.
For this normal-path checkpoint, `__gnat_personality_v0` and `_Unwind_Resume`
are deliberate fail-closed architecture entries: reaching either terminates
with a structured boot failure. This is not exception propagation or abnormal
task cleanup support. Those entries must be replaced by real semantics before
any later capability claims such behavior.
