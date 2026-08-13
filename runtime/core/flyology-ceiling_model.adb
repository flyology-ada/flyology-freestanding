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

   function Leave (Before : Ceiling_State) return Leave_Result is
      Result : Leave_Result := (State => Before, Status => Empty);
   begin
      if Before.Depth = 0 then
         return Result;
      end if;
      Result.State.Active :=
        Before.Previous (Stack_Index (Before.Depth));
      Result.State.Previous (Stack_Index (Before.Depth)) := Priority'First;
      Result.State.Depth := Before.Depth - 1;
      Result.Status := Left;
      return Result;
   end Leave;
end Flyology.Ceiling_Model;
