--  SPDX-License-Identifier: MIT OR Apache-2.0

with Flyology.Clock_Model;
with Flyology.Preemption_Model;

package Flyology.Scheduling_Configuration_Model
  with Pure,
       SPARK_Mode => On
is
   package Clock renames Flyology.Clock_Model;
   package Preemption renames Flyology.Preemption_Model;
   use type Preemption.Policy_Kind;

   Max_Cores : constant := 4;
   subtype Core_Count is Positive range 1 .. Max_Cores;
   subtype Core_Number is Natural range 0 .. Max_Cores - 1;
   type Core_Set is array (Core_Number) of Boolean;
   type Policy_Array is array (Core_Number) of Preemption.Policy_Kind;
   type Slice_Array is
     array (Core_Number) of Preemption.Binder_Time_Slice;

   type Configuration_State is record
      Cores    : Core_Count := Core_Count'First;
      Policies : Policy_Array :=
        [others => Preemption.FIFO_Within_Priorities];
      Slices   : Slice_Array := [others => 0];
   end record;

   function Valid
     (State : Configuration_State;
      Rate  : Clock.Frequency) return Boolean
   is
     ((for all Core in Core_Number =>
         (if Core < State.Cores
          then Preemption.Configuration_Is_Valid
            (State.Policies (Core), State.Slices (Core), Rate)
          else State.Policies (Core) =
              Preemption.FIFO_Within_Priorities
            and then State.Slices (Core) = 0)));

   function Has_Target (Targets : Core_Set) return Boolean
   is (for some Core in Core_Number => Targets (Core));

   function Targets_Are_Active
     (State   : Configuration_State;
      Targets : Core_Set) return Boolean
   is
     (for all Core in Core_Number =>
        (if Targets (Core) then Core < State.Cores));

   function Can_Change
     (Before : Configuration_State;
      Targets : Core_Set;
      Policy : Preemption.Policy_Kind;
      Slice  : Preemption.Binder_Time_Slice;
      Rate   : Clock.Frequency) return Boolean
   is
     (Valid (Before, Rate)
      and then Has_Target (Targets)
      and then Targets_Are_Active (Before, Targets)
      and then Preemption.Configuration_Is_Valid (Policy, Slice, Rate));

   type Change_Status is
     (Changed, Empty_Target, Inactive_Core, Invalid_Configuration);

   type Change_Result is record
      State  : Configuration_State;
      Status : Change_Status := Invalid_Configuration;
   end record;

   function Try_Change
     (Before  : Configuration_State;
      Targets : Core_Set;
      Policy  : Preemption.Policy_Kind;
      Slice   : Preemption.Binder_Time_Slice;
      Rate    : Clock.Frequency) return Change_Result
   with Pre => Valid (Before, Rate),
        Post => Valid (Try_Change'Result.State, Rate)
          and then
            (Try_Change'Result.Status = Changed) =
              Can_Change (Before, Targets, Policy, Slice, Rate)
          and then
            (if Try_Change'Result.Status = Changed
             then Try_Change'Result.State.Cores = Before.Cores
               and then
                 (for all Core in Core_Number =>
                    Try_Change'Result.State.Policies (Core) =
                      (if Targets (Core)
                       then Policy
                       else Before.Policies (Core))
                    and then Try_Change'Result.State.Slices (Core) =
                      (if Targets (Core)
                       then Slice
                       else Before.Slices (Core)))
             else Try_Change'Result.State = Before);
end Flyology.Scheduling_Configuration_Model;
