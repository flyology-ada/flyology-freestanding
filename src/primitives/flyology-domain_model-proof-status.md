# Proof Status: Flyology.Domain_Model
<!-- Reflect the top-level goal given. Items in the list below are moved from
     Not Started to In Progress to Reviewed and finally to Proved and Finalized. -->

The bounded domains scheduling-domain transition model is under proof at level 2.

## Proved and Finalized
<!-- Before marking an item complete here, follow the Widen Scope step
     (Strategic Loop Step 5) in workflow.md in the /gnatprove Skill. -->

- [x] Flyology.Domain_Model (level 2, proof: whole project 476/476 checks)

## Reviewed
<!-- Before marking an item complete here, review it following the Review
     step (Strategic Loop Step 4) in workflow.md in the /gnatprove Skill. -->

## In Progress
<!-- A subagent executes the Tactical Loop for the subprogram below. -->

- [x] Valid (level 2, scoped proof: 437/437 checks)
  - [x] Runtime checks in the validity predicate
  - [x] Exact initial shape implies a valid state
- [x] Initial (level 2, scoped proof: 1/1 checks)
  - [x] Exact canonical initial shape
  - [x] Valid-result postcondition
- [x] Try_Create (level 2, scoped proof: 3/3 checks)
  - [x] Runtime checks in the wrapper
  - [x] Valid-result postcondition
  - [x] Created exactly when Can_Create holds
  - [x] Exact new domain identifier, count, selected cores, and policy
  - [x] Every unrelated domain, core owner, and task is unchanged
  - [x] Byte-for-byte unchanged state on rejection
- [x] Create_Valid_State (level 2, all scoped checks proved)
  - [x] Runtime checks
  - [x] Valid-result postcondition
  - [x] Exact all-or-none creation frame
- [x] Place (level 2, all scoped checks proved)
  - [x] Both compiler automatic-CPU sentinels remain inside the domain
  - [x] Specific CPU placement is accepted exactly when it belongs to the domain
  - [x] Rejection preserves the cursor and returns no placement
- [x] Try_Admit (level 2, all scoped checks proved)
  - [x] Valid-result postcondition
  - [x] Explicit and inherited domain selection
  - [x] Specific CPU agreement
  - [x] Byte-for-byte unchanged state on rejection

## Not Started
<!-- Whenever a subprogram is added or discovered during assessment, list it
     here so it is not forgotten. -->

- None.

## Discovered Obligations

- [x] Prove the exact-frame assertion in `Create_Valid_State`.
- [x] Prove the `Create_Valid_State` body against its validity-preservation and
      exact creation-frame contract.
- [x] Expose decomposed domain-table, ownership, task-table, and environment
      validity predicates plus an exact declarative `Can_Create` predicate.
- [x] Re-verify the declarative `Can_Create` predicate through `Try_Create`.
- [x] Prove the `Valid` contract that an exact `Has_Initial_Shape` state is
      valid; the scoped `Initial` run consumes this modular contract but does
      not analyze the `Valid` body.
- [x] Re-verify `Try_Admit` against the tightened validity invariants: every
      used domain owns an active core and every absent task slot has canonical
      zero-valued placement fields.
- [x] Prove domain-aware placement for both compiler automatic CPU sentinels.
- [x] Widen from each scoped proof to the complete whole proof project.
- [x] Confirm the final report attributes checks to all transition bodies and
      reports 476/476 checks with no justified or unproved checks.
