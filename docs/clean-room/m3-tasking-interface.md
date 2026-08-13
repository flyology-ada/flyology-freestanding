# M3 ordinary-task compiler interface evidence

This record is limited to Flyology-owned sources under `probes/m3/`, compiler-generated expansion/ALI/object diagnostics, and black-box compilation with the pinned GNAT 15.3 cross compilers. No GNAT runtime source was inspected or used.

The authoritative discovery command is `scripts/probe-m3-interface.sh`. Generated expansion, undefined-symbol inventories, and objects remain ignored under `build/probes/m3/`.

## Observed static-task surface

The automatic and `CPU => 1` task probe generates one lexical activation chain. Each task object initializer calls `System.Tasking.Stages.Create_Task` with, in order: priority, primary stack size, secondary stack size, task info, CPU, relative deadline, dispatching domain, base CPU, master, body procedure, discriminants address, elaborated flag, activation chain, task name, and output `Task_Id`. The automatic task passes `System.Tasking.Unspecified_CPU`; the pinned object stores and passes Ada CPU value 1.

The compiler-generated body wrapper calls `Complete_Activation` before user statements. Its mandatory finalizer calls the `Abort_Defer` soft link, `Complete_Task`, then the `Abort_Undefer` soft link. The enclosing scope calls `Enter_Master`, reads `Current_Master`, calls `Activate_Tasks` on the chain, and its finalizer brackets `Complete_Master` with abort deferral. These four master/abort hooks are data symbols containing access-to-subprogram values, not direct procedure symbols. The activation chain itself is merely limited private; no compiler-required controlled initialization/finalization operation exists. `Task'Identity` is derived directly from the compiler-generated task value record's `_task_id`; standard current/callable/terminated queries remain calls to `Ada.Task_Identification`.

An owned hosted GNAT 15.3 black-box master test releases a dependent from the lexical body, lets it finish later, and checks its flag immediately after the scope returns. Five bounded runs returned only after the dependent finished. Together with the generated calls, this establishes that `Activate_Tasks` waits for activation completion while the scope-finalizer `Complete_Master` waits for termination. An owned abnormal-declarative-part probe raises after task creation but before activation; expansion still emits no activation-chain finalizer and routes scope cleanup through the master finalizer. Target QEMU behavior remains an M3 product gate.

Both targets require the same task lifecycle symbols. AArch64 may additionally require `__clear_cache` when a generated executable trampoline is present. Both restricted and unrestricted normal task objects contain exception-unwind references; the current `No_Exception_Propagation` restriction therefore does not itself establish full cleanup or propagation semantics.

## Contract and limits

These observations establish compatibility names, profiles, ordering, and values—not runtime semantic conformance. The product implementation must keep one stable TCB-backed `Task_Id`, create tasks dormant on their activation chain, atomically admit the chain, map Ada CPU 1 to dense `Core_Id` 0 only after validation, execute the compiler wrapper on a distinct stack, and route completion through GNARL before dispatcher transfer.

Activation failure details, full abnormal-master semantics, exception propagation, abort, dynamic task reclamation, rendezvous, protected objects, delays, and task attributes are not established by this probe. Freestanding master waiting and unactivated-task cleanup must pass their QEMU semantic gates before M3 can close.
