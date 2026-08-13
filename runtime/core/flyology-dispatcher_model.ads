--  SPDX-License-Identifier: MIT OR Apache-2.0

package Flyology.Dispatcher_Model
  with Pure,
       SPARK_Mode => On
is
   Max_Tasks : constant := 1_024;

   type Task_Slot is range 0 .. Max_Tasks - 1;
   type Task_Incarnation is range 0 .. 2 ** 31 - 1;

   type Task_Ref is record
      Slot        : Task_Slot := Task_Slot'First;
      Incarnation : Task_Incarnation := Task_Incarnation'First;
   end record;

   No_Task : constant Task_Ref :=
     (Slot => Task_Slot'First, Incarnation => Task_Incarnation'First);

   function Is_Valid_Task (Reference : Task_Ref) return Boolean
   is (Reference.Incarnation /= Task_Incarnation'First);

   function Can_Advance_Incarnation
     (Value : Task_Incarnation) return Boolean
   is (Value /= Task_Incarnation'First
       and then Value /= Task_Incarnation'Last);

   function Next_Incarnation
     (Value : Task_Incarnation) return Task_Incarnation
   with Pre  => Can_Advance_Incarnation (Value),
        Post => Next_Incarnation'Result = Value + 1
          and then Next_Incarnation'Result /= Task_Incarnation'First;

   type Core_Id is range 0 .. 255;
   type Domain_Id is range 0 .. 255;
   type Priority is range 0 .. 255;
   type Generation is range 0 .. 2 ** 63 - 1;

   type Task_State is (Dormant, Ready, Running, Blocked, Terminated);

   type Transition_Kind is
     (Admit,
      Dispatch,
      Yield,
      Block,
      Wake,
      Terminate_Task);

   function Transition_Is_Legal
     (State      : Task_State;
      Transition : Transition_Kind) return Boolean
   is (case Transition is
          when Admit          => State = Dormant,
          when Dispatch       => State = Ready,
          when Yield          => State = Running,
          when Block          => State = Running,
          when Wake           => State = Blocked,
          when Terminate_Task => State in Ready | Running);

   type Transition_Attempt is record
      State    : Task_State := Dormant;
      Accepted : Boolean := False;
   end record;

   function Try_Transition
     (State      : Task_State;
      Transition : Transition_Kind) return Transition_Attempt
   with Post =>
          Try_Transition'Result.Accepted =
            Transition_Is_Legal (State, Transition)
          and then
            (if Try_Transition'Result.Accepted
             then Try_Transition'Result.State =
               (case Transition is
                   when Admit | Yield | Wake => Ready,
                   when Dispatch             => Running,
                   when Block                => Blocked,
                   when Terminate_Task       => Terminated)
             else Try_Transition'Result.State = State);

   type Wait_Phase is (No_Wait, Armed, Committed);

   type Wait_State is record
      Reference  : Task_Ref := No_Task;
      State      : Task_State := Dormant;
      Phase      : Wait_Phase := No_Wait;
      Token      : Generation := Generation'First;
      Wake_Saved : Boolean := False;
   end record;

   function Begin_Wait (Before : Wait_State) return Wait_State
   with Pre  => Is_Valid_Task (Before.Reference)
          and then Before.State = Running
          and then Before.Phase = No_Wait
          and then Before.Token /= Generation'Last
          and then not Before.Wake_Saved,
        Post => Begin_Wait'Result.Reference = Before.Reference
          and then Begin_Wait'Result.State = Running
          and then Begin_Wait'Result.Phase = Armed
          and then Begin_Wait'Result.Token = Before.Token + 1
          and then not Begin_Wait'Result.Wake_Saved;

   function Publish_Wait (Before : Wait_State) return Wait_State
   with Pre  => Before.State = Running
          and then
            (Before.Phase = Armed
             or else (Before.Phase = No_Wait and then Before.Wake_Saved)),
        Post => Publish_Wait'Result.Reference = Before.Reference
          and then Publish_Wait'Result.Token = Before.Token
          and then
            (if Before.Wake_Saved then
                Publish_Wait'Result.State = Running
                  and then Publish_Wait'Result.Phase = No_Wait
             else
                Publish_Wait'Result.State = Blocked
                  and then Publish_Wait'Result.Phase = Committed)
          and then not Publish_Wait'Result.Wake_Saved;

   function Wake_Exact
     (Before   : Wait_State;
      Reference : Task_Ref;
      Expected : Generation) return Wait_State
   with Post => Wake_Exact'Result.Token = Before.Token
          and then
            (if Reference /= Before.Reference
               or else Expected /= Before.Token
               or else
                 (not (Before.State = Running and then Before.Phase = Armed)
                  and then
                    not (Before.State = Blocked
                         and then Before.Phase = Committed))
             then Wake_Exact'Result = Before
             elsif Before.Phase = Armed
             then Wake_Exact'Result.State = Running
               and then Wake_Exact'Result.Phase = No_Wait
               and then Wake_Exact'Result.Wake_Saved
             else Wake_Exact'Result.State = Ready
               and then Wake_Exact'Result.Phase = No_Wait
               and then not Wake_Exact'Result.Wake_Saved);

   subtype Preemption_Depth is Natural range 0 .. 255;

   type Preemption_State is record
      Depth      : Preemption_Depth := 0;
      Deferred   : Boolean := False;
   end record;

   type Leave_Result is record
      State      : Preemption_State;
      Reschedule : Boolean;
   end record;

   function Enter_Critical
     (Before : Preemption_State) return Preemption_State
   with Pre  => Before.Depth < Preemption_Depth'Last,
        Post => Enter_Critical'Result.Depth = Before.Depth + 1
          and then Enter_Critical'Result.Deferred = Before.Deferred;

   function Request_Reschedule
     (Before : Preemption_State) return Preemption_State
   with Post => Request_Reschedule'Result.Depth = Before.Depth
          and then Request_Reschedule'Result.Deferred;

   function Leave_Critical
     (Before : Preemption_State) return Leave_Result
   with Pre  => Before.Depth > 0,
        Post => Leave_Critical'Result.State.Depth = Before.Depth - 1
          and then Leave_Critical'Result.Reschedule
            = (Before.Depth = 1 and then Before.Deferred)
          and then Leave_Critical'Result.State.Deferred
            = (Before.Depth > 1 and then Before.Deferred);

end Flyology.Dispatcher_Model;
