# Scheduling configuration

An application chooses its partition's initial policy in Ada source:

```ada
pragma Task_Dispatching_Policy (FIFO_Within_Priorities);
```

That declaration is required before application code runs because a
library-level task object can be created and activated during binder-controlled
elaboration. A task type declaration alone does not activate a task, but it
does not remove the need to configure packages that declare task objects.
[ADR-0011](adr/0011-source-selected-initial-scheduling.md) records this startup
boundary.

After elaboration, the original `Flyology.Scheduling` API can change effective
policy at three scopes:

```ada
with Flyology.Scheduling;
with System.Multiprocessors.Dispatching_Domains;

procedure Configure is
   package Scheduling renames Flyology.Scheduling;
   package Domains renames
     System.Multiprocessors.Dispatching_Domains;
begin
   Scheduling.Set_Global_Policy (Scheduling.FIFO);
   Scheduling.Set_Domain_Policy
     (Domains.Get_Dispatching_Domain,
      Scheduling.Round_Robin (Quantum => 5_000));
   Scheduling.Set_CPU_Policy
     (CPU => 2, Configuration => Scheduling.Round_Robin (2_000));
end Configure;
```

`Policy_Of (CPU)` returns the effective policy and quantum for one Ada CPU.
CPU numbers are standard one-based Ada CPU values; they are never hardware IDs
or dense internal core IDs.

Scope updates use deterministic replacement semantics:

| Operation | Domain defaults | Effective cores |
| --- | --- | --- |
| `Set_Global_Policy` | every used domain | every active core |
| `Set_Domain_Policy` | selected domain | every member core |
| `Set_CPU_Policy` | unchanged | selected core only |

A later wider-scope operation replaces narrower overrides in its target set.
Changes preserve domain membership, task placement, task priority, and current
ready ordering. They are committed under the RTS lock and prompt each affected
core to account the new budget and timer locally. See
[ADR-0012](adr/0012-live-scheduling-policy.md) for the exact transition rules.

Only `FIFO_Within_Priorities` and `Round_Robin_Within_Priorities` are currently
implemented. FIFO uses quantum zero. Round robin requires a positive quantum in
microseconds and defaults to 10,000 microseconds. Invalid record combinations
raise `Flyology.Scheduling.Scheduling_Error`; unsupported CPU values do the
same. This API is a Flyology extension and does not replace standard task,
priority, or dispatching-domain declarations.
