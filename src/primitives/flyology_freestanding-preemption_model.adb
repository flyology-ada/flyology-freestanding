--  SPDX-License-Identifier: MIT OR Apache-2.0

package body Flyology_Freestanding.Preemption_Model
  with SPARK_Mode => On
is
   function Quantum_Ticks
     (Slice : Binder_Time_Slice;
      Rate  : Clock.Frequency) return Clock.Tick
   is
   begin
      return Clock.To_Ticks_Ceiling (Slice_Nanoseconds (Slice), Rate);
   end Quantum_Ticks;

   function Start_Budget
     (Policy  : Policy_Kind;
      Now     : Clock.Tick;
      Quantum : Clock.Tick) return Budget_State
   is
   begin
      if Policy = Round_Robin_Within_Priorities then
         return (Armed => True, Remaining => Quantum, Last_Accounted => Now);
      end if;
      return (Armed => False, Remaining => 0, Last_Accounted => Now);
   end Start_Budget;

   function Account
     (Before : Budget_State;
      Now    : Clock.Tick) return Budget_State
   is
      Result  : Budget_State := Before;
      Elapsed : Clock.Tick;
   begin
      if not Before.Armed then
         return Result;
      end if;
      Elapsed := Now - Before.Last_Accounted;
      Result.Last_Accounted := Now;
      if Elapsed >= Before.Remaining then
         Result.Remaining := 0;
      else
         Result.Remaining := Before.Remaining - Elapsed;
      end if;
      return Result;
   end Account;

   function Resume_Retained
     (Before : Budget_State;
      Now    : Clock.Tick) return Budget_State
   is
      Result : Budget_State := Before;
   begin
      if Result.Armed then
         Result.Last_Accounted := Now;
      end if;
      return Result;
   end Resume_Retained;

   function Decide
     (Policy                  : Policy_Kind;
      Current_Active_Priority : Dispatcher.Priority;
      Ready                   : Boolean;
      Highest_Ready_Priority  : Dispatcher.Priority;
      Budget                  : Budget_State;
      Has_Inherited_Priority  : Boolean;
      Inside_Protected_Action : Boolean) return Preemption_Cause
   is
   begin
      if Ready and then Highest_Ready_Priority > Current_Active_Priority then
         return Higher_Priority_Ready;
      elsif Policy = Round_Robin_Within_Priorities
        and then Budget.Armed
        and then Budget.Remaining = 0
        and then not Has_Inherited_Priority
        and then not Inside_Protected_Action
      then
         return Budget_Exhausted;
      end if;
      return Continue_Running;
   end Decide;
end Flyology_Freestanding.Preemption_Model;
