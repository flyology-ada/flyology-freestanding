--  SPDX-License-Identifier: MIT OR Apache-2.0

with Flyology.Dispatcher_Model;

package Flyology.Ceiling_Model
  with Pure,
       SPARK_Mode => On
is
   subtype Priority is Flyology.Dispatcher_Model.Priority;
   use type Priority;
   Capacity : constant := 8;
   subtype Stack_Index is Positive range 1 .. Capacity;
   subtype Stack_Length is Natural range 0 .. Capacity;
   type Priority_Stack is array (Stack_Index) of Priority;

   type Ceiling_State is record
      Base     : Priority := Priority'First;
      Active   : Priority := Priority'First;
      Previous : Priority_Stack := [others => Priority'First];
      Depth    : Stack_Length := 0;
   end record;

   function Valid (State : Ceiling_State) return Boolean
   is ((if State.Depth = 0 then State.Active = State.Base)
       and then
         (for all Index in Stack_Index =>
            (if Index <= State.Depth
             then
               (if Index > Stack_Index'First
                then State.Previous (Index) >=
                  State.Previous (Stack_Index'Pred (Index))
                else True)
             else State.Previous (Index) = Priority'First))
       and then
         (if State.Depth > 0
          then State.Active >=
            State.Previous (Stack_Index (State.Depth))));

   type Enter_Status is (Entered, Ceiling_Violation, Stack_Full);
   type Enter_Result is record
      State  : Ceiling_State;
      Status : Enter_Status := Ceiling_Violation;
   end record;

   function Enter
     (Before  : Ceiling_State;
      Ceiling : Priority) return Enter_Result
   with Pre => Valid (Before),
        Post => Valid (Enter'Result.State)
          and then
            (if Enter'Result.Status = Entered
             then Enter'Result.State.Depth = Before.Depth + 1
               and then Enter'Result.State.Active = Ceiling
               and then Enter'Result.State.Base = Before.Base
             else Enter'Result.State = Before);

   function Change_Base
     (Before   : Ceiling_State;
      Priority : Ceiling_Model.Priority) return Ceiling_State
   with Pre => Valid (Before),
        Post => Valid (Change_Base'Result)
          and then Change_Base'Result.Base = Priority
          and then Change_Base'Result.Depth = Before.Depth
          and then
            (if Before.Depth = 0
             then Change_Base'Result.Active = Priority
             else Change_Base'Result.Active = Before.Active);

   type Leave_Status is (Left, Empty);
   type Leave_Result is record
      State  : Ceiling_State;
      Status : Leave_Status := Empty;
   end record;

   function Leave (Before : Ceiling_State) return Leave_Result
   with Pre => Valid (Before),
        Post => Valid (Leave'Result.State)
          and then
            (if Leave'Result.Status = Left
             then Leave'Result.State.Depth = Before.Depth - 1
               and then Leave'Result.State.Active =
                 (if Before.Depth = 1
                  then Before.Base
                  else Before.Previous (Stack_Index (Before.Depth)))
               and then Leave'Result.State.Base = Before.Base
             else Leave'Result.State = Before);
end Flyology.Ceiling_Model;
