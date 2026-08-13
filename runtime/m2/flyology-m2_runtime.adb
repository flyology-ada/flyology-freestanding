--  SPDX-License-Identifier: MIT OR Apache-2.0

with Flyology.Dispatcher_Model;
with Flyology.M2_Architecture;
with Flyology.Reschedule_Model;
with Flyology.Scheduler_Contract;

package body Flyology.M2_Runtime is
   package Model renames Flyology.Dispatcher_Model;
   package Architecture renames Flyology.M2_Architecture;
   package Requests renames Flyology.Reschedule_Model;
   package Scheduler renames Flyology.Scheduler_Contract;
   use type Model.Task_Incarnation;
   use type Model.Task_Ref;
   use type Model.Task_State;
   use type Model.Wait_Phase;
   use type Model.Wait_State;
   use type Requests.Request_Epoch;
   use type System.Address;

   Max_Cores       : constant := 4;
   Task_Stack_Size : constant := 16 * 1_024;

   type Core_Number is range 0 .. Max_Cores - 1;
   type Step_Count is range 0 .. 2;
   type Stack_Byte is mod 2 ** 8 with Size => 8;
   type Task_Stack is array (Natural range 0 .. Task_Stack_Size - 1)
     of Stack_Byte
     with Component_Size => 8,
          Alignment      => 16;
   type Stack_Array is array (Core_Number) of aliased Task_Stack;
   type Context_Array is array (Core_Number) of aliased Architecture.Context;
   type State_Array is array (Core_Number) of Model.Task_State;
   type Step_Array is array (Core_Number) of Step_Count;

   Task_Stacks        : Stack_Array;
   Task_Contexts      : Context_Array;
   Dispatcher_Contexts : Context_Array;
   Task_States        : State_Array := [others => Model.Dormant];
   Task_Steps         : Step_Array := [others => 0];

   function Current_Core return System.Address
   with Import,
        Convention    => C,
        External_Name => "flyology_current_core";

   procedure Report_Pass (Core_Value : System.Address)
   with Import,
        Convention    => C,
        External_Name => "flyology_m2_report_pass";

   procedure Report_Failure
   with Import,
        Convention    => C,
        External_Name => "flyology_m2_report_failure";

   procedure Fail is
   begin
      Report_Failure;
      loop
         null;
      end loop;
   end Fail;

   function Reference_For (Core : Core_Number) return Model.Task_Ref is
   begin
      return
        (Slot        => Model.Task_Slot (Core_Number'Pos (Core) + 1),
         Incarnation => 1);
   end Reference_For;

   procedure Initialize is
   begin
      Task_States := [others => Model.Dormant];
      Task_Steps := [others => 0];
   end Initialize;

   procedure Check_Wait_Model (Core : Core_Number) is
      Reference : constant Model.Task_Ref := Reference_For (Core);
      Other     : constant Model.Task_Ref :=
        (Slot => Reference.Slot, Incarnation => 2);
      State     : Model.Wait_State :=
        (Reference  => Reference,
         State      => Model.Running,
         Phase      => Model.No_Wait,
         Token      => 0,
         Wake_Saved => False);
      Armed     : Model.Wait_State;
      Snapshot  : Model.Wait_State;
   begin
      Armed := Model.Begin_Wait (State);
      Snapshot := Model.Wake_Exact (Armed, Other, Armed.Token);
      if Snapshot /= Armed then
         Fail;
      end if;

      State := Model.Wake_Exact (Armed, Reference, Armed.Token);
      if State.State /= Model.Running
        or else State.Phase /= Model.No_Wait
        or else not State.Wake_Saved
      then
         Fail;
      end if;
      State := Model.Publish_Wait (State);
      if State.State /= Model.Running
        or else State.Phase /= Model.No_Wait
        or else State.Wake_Saved
      then
         Fail;
      end if;

      Armed := Model.Begin_Wait (State);
      State := Model.Publish_Wait (Armed);
      if State.State /= Model.Blocked or else State.Phase /= Model.Committed then
         Fail;
      end if;
      State := Model.Wake_Exact (State, Reference, State.Token);
      if State.State /= Model.Ready or else State.Phase /= Model.No_Wait then
         Fail;
      end if;
   end Check_Wait_Model;

   procedure Check_Queue_Model (Core : Core_Number) is
      First  : constant Model.Task_Ref := Reference_For (Core);
      Second : constant Model.Task_Ref :=
        (Slot        => First.Slot,
         Incarnation => First.Incarnation + 1);
      Queue  : Scheduler.Ready_Queue;
      Choice : Scheduler.Selection;
   begin
      Queue := Scheduler.Enqueue (Queue, First);
      Queue := Scheduler.Enqueue (Queue, Second);
      Choice := Scheduler.Select_Next (Queue);
      if Choice.Selected /= First
        or else Choice.Remainder.Length /= 1
        or else not Scheduler.Contains (Choice.Remainder, Second)
      then
         Fail;
      end if;
   end Check_Queue_Model;

   procedure Check_Request_Model is
      State : Requests.Request_State;
      Seen  : Requests.Dispatch_Snapshot;
   begin
      State := Requests.Post_Request (State, Requests.Remote_Ready);
      Seen := Requests.Snapshot (State);
      State := Requests.Post_Request (State, Requests.Timer);
      State := Requests.Acknowledge (State, Seen);
      if not Requests.Is_Pending (State)
        or else State.Acknowledged /= Seen.Epoch
        or else State.Requested = Seen.Epoch
      then
         Fail;
      end if;
   end Check_Request_Model;

   procedure Core_Entry is
      Raw_Core  : constant System.Address := Current_Core;
      Core      : Core_Number;
      Stack_Top : System.Address;
   begin
      if Raw_Core > System.Address (Core_Number'Last) then
         Fail;
      end if;
      Core := Core_Number (Raw_Core);

      Check_Wait_Model (Core);
      Check_Queue_Model (Core);
      Check_Request_Model;

      Task_States (Core) := Model.Ready;
      Task_States (Core) :=
        Model.Transition_Result (Task_States (Core), Model.Dispatch);
      Stack_Top := Task_Stacks (Core) (Task_Stack'Last)'Address + 1;
      Architecture.Initialize (Task_Contexts (Core), Stack_Top, Raw_Core);
      Architecture.Switch
        (Dispatcher_Contexts (Core)'Access, Task_Contexts (Core)'Access);

      if Task_States (Core) /= Model.Ready or else Task_Steps (Core) /= 1 then
         Fail;
      end if;
      Task_States (Core) :=
        Model.Transition_Result (Task_States (Core), Model.Dispatch);
      Architecture.Switch
        (Dispatcher_Contexts (Core)'Access, Task_Contexts (Core)'Access);

      if Task_States (Core) /= Model.Terminated or else Task_Steps (Core) /= 2
      then
         Fail;
      end if;
      Report_Pass (Raw_Core);
   end Core_Entry;

   procedure Task_Start (Core_Value : System.Address) is
      Core : Core_Number;
   begin
      if Core_Value > System.Address (Core_Number'Last) then
         Fail;
      end if;
      Core := Core_Number (Core_Value);
      if Task_States (Core) /= Model.Running or else Task_Steps (Core) /= 0 then
         Fail;
      end if;

      Task_Steps (Core) := 1;
      Task_States (Core) :=
        Model.Transition_Result (Task_States (Core), Model.Yield);
      Architecture.Switch
        (Task_Contexts (Core)'Access, Dispatcher_Contexts (Core)'Access);

      if Task_States (Core) /= Model.Running or else Task_Steps (Core) /= 1 then
         Fail;
      end if;
      Task_Steps (Core) := 2;
      Task_States (Core) :=
        Model.Transition_Result (Task_States (Core), Model.Terminate_Task);
      Architecture.Switch
        (Task_Contexts (Core)'Access, Dispatcher_Contexts (Core)'Access);
      Fail;
   end Task_Start;
end Flyology.M2_Runtime;
