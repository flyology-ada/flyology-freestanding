--  SPDX-License-Identifier: MIT OR Apache-2.0

with Flyology.Clock_Model;
with Flyology.Dispatcher_Model;

package Flyology.Preemption_Model
  with Pure,
       SPARK_Mode => On
is
   package Clock renames Flyology.Clock_Model;
   package Dispatcher renames Flyology.Dispatcher_Model;
   use type Clock.Nanoseconds;
   use type Clock.Tick;
   use type Dispatcher.Priority;

   type Policy_Kind is
     (FIFO_Within_Priorities,
      Round_Robin_Within_Priorities);

   subtype Binder_Time_Slice is Natural range 0 .. Integer'Last;

   function Slice_Nanoseconds
     (Slice : Binder_Time_Slice) return Clock.Nanoseconds
   is (Clock.Nanoseconds (Slice) * Clock.Nanoseconds'(1_000));

   function Configuration_Is_Valid
     (Policy : Policy_Kind;
      Slice  : Binder_Time_Slice;
      Rate   : Clock.Frequency) return Boolean
   is (case Policy is
          when FIFO_Within_Priorities => Slice = 0,
          when Round_Robin_Within_Priorities =>
            Slice > 0
              and then Clock.Conversion_Fits
                (Slice_Nanoseconds (Slice), Rate));

   function Quantum_Ticks
     (Slice : Binder_Time_Slice;
      Rate  : Clock.Frequency) return Clock.Tick
   with Pre => Slice > 0
          and then Clock.Conversion_Fits (Slice_Nanoseconds (Slice), Rate),
        Post => Quantum_Ticks'Result > 0;

   type Budget_State is record
      Armed          : Boolean := False;
      Remaining      : Clock.Tick := 0;
      Last_Accounted : Clock.Tick := 0;
   end record;

   Empty_Budget : constant Budget_State := (others => <>);

   function Valid (State : Budget_State) return Boolean
   is (State.Armed or else State.Remaining = 0);

   function Start_Budget
     (Policy  : Policy_Kind;
      Now     : Clock.Tick;
      Quantum : Clock.Tick) return Budget_State
   with Pre => Quantum > 0,
        Post => Valid (Start_Budget'Result)
          and then Start_Budget'Result.Last_Accounted = Now
          and then
            (if Policy = Round_Robin_Within_Priorities
             then Start_Budget'Result.Armed
               and then Start_Budget'Result.Remaining = Quantum
             else not Start_Budget'Result.Armed
               and then Start_Budget'Result.Remaining = 0);

   function Account
     (Before : Budget_State;
      Now    : Clock.Tick) return Budget_State
   with Pre => Valid (Before) and then Now >= Before.Last_Accounted,
        Post => Valid (Account'Result)
          and then
            (if not Before.Armed
             then Account'Result = Before
             else Account'Result.Armed
               and then Account'Result.Last_Accounted = Now
               and then Account'Result.Remaining =
                 (if Now - Before.Last_Accounted >= Before.Remaining
                  then 0
                  else Before.Remaining - (Now - Before.Last_Accounted)));

   function Resume_Retained
     (Before : Budget_State;
      Now    : Clock.Tick) return Budget_State
   with Pre => Valid (Before),
        Post => Valid (Resume_Retained'Result)
          and then Resume_Retained'Result.Armed = Before.Armed
          and then Resume_Retained'Result.Remaining = Before.Remaining
          and then
            (if Before.Armed then
                Resume_Retained'Result.Last_Accounted = Now
             else
                Resume_Retained'Result = Before);

   type Preemption_Cause is
     (Continue_Running,
      Higher_Priority_Ready,
      Budget_Exhausted);

   function Decide
     (Policy                 : Policy_Kind;
      Current_Active_Priority : Dispatcher.Priority;
      Ready                  : Boolean;
      Highest_Ready_Priority : Dispatcher.Priority;
      Budget                 : Budget_State;
      Has_Inherited_Priority : Boolean;
      Inside_Protected_Action : Boolean) return Preemption_Cause
   with Pre => Valid (Budget),
        Post => Decide'Result =
          (if Ready
             and then Highest_Ready_Priority > Current_Active_Priority
           then Higher_Priority_Ready
           elsif Policy = Round_Robin_Within_Priorities
             and then Budget.Armed
             and then Budget.Remaining = 0
             and then not Has_Inherited_Priority
             and then not Inside_Protected_Action
           then Budget_Exhausted
           else Continue_Running);
end Flyology.Preemption_Model;
