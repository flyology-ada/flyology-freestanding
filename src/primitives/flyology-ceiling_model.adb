--  SPDX-License-Identifier: MIT OR Apache-2.0

package body Flyology.Ceiling_Model
  with SPARK_Mode => On
is
   function Enter
     (Before  : Ceiling_State;
      Ceiling : Priority) return Enter_Result
   is
      Result : Enter_Result :=
        (State => Before, Status => Ceiling_Violation);
   begin
      if Before.Active > Ceiling then
         return Result;
      elsif Before.Depth = Capacity then
         Result.Status := Stack_Full;
         return Result;
      end if;
      Result.State.Depth := Before.Depth + 1;
      Result.State.Previous (Stack_Index (Result.State.Depth)) :=
        Before.Active;
      Result.State.Active := Ceiling;
      Result.Status := Entered;
      return Result;
   end Enter;

   function Change_Base
     (Before   : Ceiling_State;
      Priority : Ceiling_Model.Priority) return Ceiling_State
   is
      Result : Ceiling_State := Before;
   begin
      Result.Base := Priority;
      if Result.Depth = 0 then
         Result.Active := Priority;
      end if;
      return Result;
   end Change_Base;

   function Leave (Before : Ceiling_State) return Leave_Result is
      Result : Leave_Result := (State => Before, Status => Empty);
   begin
      if Before.Depth = 0 then
         return Result;
      end if;
      if Before.Depth = 1 then
         Result.State.Active := Before.Base;
      else
         Result.State.Active :=
           Before.Previous (Stack_Index (Before.Depth));
      end if;
      Result.State.Previous (Stack_Index (Before.Depth)) := Priority'First;
      Result.State.Depth := Before.Depth - 1;
      Result.Status := Left;
      return Result;
   end Leave;
end Flyology.Ceiling_Model;
