--  SPDX-License-Identifier: MIT OR Apache-2.0

package body Flyology.Scheduling_Configuration_Model
  with SPARK_Mode => On
is
   function Try_Change
     (Before  : Configuration_State;
      Targets : Core_Set;
      Policy  : Preemption.Policy_Kind;
      Slice   : Preemption.Binder_Time_Slice;
      Rate    : Clock.Frequency) return Change_Result
   is
      Result : Change_Result := (State => Before, others => <>);
   begin
      if not Has_Target (Targets) then
         Result.Status := Empty_Target;
         return Result;
      elsif not Targets_Are_Active (Before, Targets) then
         Result.Status := Inactive_Core;
         return Result;
      elsif not Preemption.Configuration_Is_Valid (Policy, Slice, Rate) then
         Result.Status := Invalid_Configuration;
         return Result;
      end if;

      for Core in Core_Number loop
         if Targets (Core) then
            Result.State.Policies (Core) := Policy;
            Result.State.Slices (Core) := Slice;
         end if;
      end loop;
      Result.Status := Changed;
      return Result;
   end Try_Change;
end Flyology.Scheduling_Configuration_Model;
