# Deterministic primitive library

`libflyology_freestanding_primitives.a` is the reusable, host-buildable part of Flyology_Freestanding. It
contains bounded deterministic algorithms and their contracts; it does not
contain task creation, mutable concurrent kernel state, context transfer,
compiler facades, exception unwinding, or privileged platform code.

The root Alire crate and `gpr/flyology_freestanding_primitives.gpr` build the library from
`src/primitives/`. `proof/flyology_freestanding_proof.gpr` analyzes the SPARK-enabled bodies.
Host model gates execute the same packages at production and reduced bounds,
while the TLA+ models explore cross-operation ordering that is deliberately not
encoded as a second production state authority.

## Package groups

| Responsibility | Packages | Boundary |
| --- | --- | --- |
| Checked values and boot geometry | `Validation`, `Boot_Validation`, `Clock_Model`, `Allocator_Model`, `Allocator` | Pure validation and conversion plus the exact bounded first-fit allocator state engine used by the freestanding ABI facade. |
| Task lifecycle | `Dispatcher_Model`, `Activation_Model`, `Termination_Model`, `Placement_Model` | Legal task states, activation groups, retirement, ownership, and placement decisions. |
| Waiting and notification | `Wait_Arbitration_Model`, `Wait_Queue_Model`, `Timer_Model`, `Reschedule_Model` | Exact references/generations, one-winner outcomes, bounded deadlines, and request epochs. |
| Scheduling | `Scheduler_Contract`, `Priority_Queue_Model`, `Preemption_Model`, `Scheduling_Configuration_Model`, `Ceiling_Model` | Ready ordering, priority changes, budgets, atomic per-core configuration changes, preemption decisions, and ceiling arithmetic. Policy selects; it never transfers a context. |
| Domains | `Domain_Model` | Immutable domain creation, core ownership, admission, and isolation. |
| Exceptional lifecycle | `Exceptional_Completion_Model`, `Abort_Closure_Model` | Retained completion ownership and bounded dependent-task abort closure. |
| Concurrent boundary | `Task_Primitives` | Imported typed contract only. Its operations are implemented by `Flyology_Freestanding.Kernel` and are explicitly outside the deterministic-library proof claim. |

`Flyology_Freestanding.Kernel` is the only production owner of mutable current-task, ready,
wait, timer, and context state. It calls these packages while holding the
appropriate runtime critical section and performs publication/context transfer
only after the deterministic result is validated. `Flyology_Freestanding.RTS` adds GNARL
language semantics above that boundary. Neither layer is duplicated in this
library.

## Supported use

Build the archive with:

```sh
alr build --release
```

Run the deterministic proof and model family with:

```sh
scripts/verify-formal-models.sh
```

The archive is an internal engineering library at `0.1.0-dev`: package names
and contracts are reviewed source interfaces, but semantic-version stability is
not promised before the first release. It must not be presented as a public
spawn/fiber API or as a complete hosted Ada tasking runtime.
