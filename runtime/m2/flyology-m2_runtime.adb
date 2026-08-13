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
   use type Model.Generation;
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
   type Reference_Array is array (Core_Number) of Model.Task_Ref;
   type Queue_Array is array (Core_Number) of Scheduler.Ready_Queue;
   type Wait_Array is array (Core_Number) of Model.Wait_State;
   type Request_Array is array (Core_Number) of Requests.Request_State;

   Task_Stacks        : Stack_Array;
   Task_Contexts      : Context_Array;
   Dispatcher_Contexts : Context_Array;
   Task_States        : State_Array := [others => Model.Dormant];
   Task_Steps         : Step_Array := [others => 0];
   Current_Tasks      : Reference_Array := [others => Model.No_Task];
   Ready_Queues       : Queue_Array;
   Wait_States        : Wait_Array;
   Request_States     : Request_Array;

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

   procedure Enter_Kernel
   with Import,
        Convention    => C,
        External_Name => "flyology_rts_lock_acquire";

   procedure Leave_Kernel
   with Import,
        Convention    => C,
        External_Name => "flyology_rts_lock_release";

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

   procedure Apply_Transition
     (State      : in out Model.Task_State;
      Transition : Model.Transition_Kind)
   is
      Attempt : constant Model.Transition_Attempt :=
        Model.Try_Transition (State, Transition);
   begin
      if not Attempt.Accepted then
         Fail;
      end if;
      State := Attempt.State;
   end Apply_Transition;

   procedure Enqueue_Ready
     (Core      : Core_Number;
      Reference : Model.Task_Ref)
   is
      Attempt : constant Scheduler.Enqueue_Attempt :=
        Scheduler.Try_Enqueue (Ready_Queues (Core), Reference);
   begin
      if not Attempt.Accepted then
         Fail;
      end if;
      Ready_Queues (Core) := Attempt.Queue;
   end Enqueue_Ready;

   procedure Dispatch_Next (Core : Core_Number) is
      Choice : constant Scheduler.Selection :=
        Scheduler.Select_Next (Ready_Queues (Core));
   begin
      if Choice.Selected = Model.No_Task
        or else Choice.Selected /= Reference_For (Core)
        or else Current_Tasks (Core) /= Model.No_Task
        or else Task_States (Core) /= Model.Ready
      then
         Fail;
      end if;
      Ready_Queues (Core) := Choice.Remainder;
      Apply_Transition (Task_States (Core), Model.Dispatch);
      Current_Tasks (Core) := Choice.Selected;
   end Dispatch_Next;

   procedure Arm_Wait
     (Core  : Core_Number;
      Token : out Model.Generation)
   is
   begin
      if Task_States (Core) /= Model.Running
        or else Current_Tasks (Core) /= Reference_For (Core)
        or else Wait_States (Core).Phase /= Model.No_Wait
        or else Wait_States (Core).Token = Model.Generation'Last
        or else Wait_States (Core).Wake_Saved
      then
         Fail;
      end if;
      Wait_States (Core) := Model.Begin_Wait (Wait_States (Core));
      Token := Wait_States (Core).Token;
   end Arm_Wait;

   procedure Make_Ready_Exact
     (Core  : Core_Number;
      Token : Model.Generation;
      Won   : out Boolean)
   is
      Before : constant Model.Wait_State := Wait_States (Core);
      After  : constant Model.Wait_State :=
        Model.Wake_Exact (Before, Reference_For (Core), Token);
   begin
      Won := After /= Before;
      if not Won then
         return;
      end if;

      Wait_States (Core) := After;
      if Before.State = Model.Blocked
        and then Before.Phase = Model.Committed
      then
         if Task_States (Core) /= Model.Blocked
           or else After.State /= Model.Ready
         then
            Fail;
         end if;
         Apply_Transition (Task_States (Core), Model.Wake);
         Enqueue_Ready (Core, Reference_For (Core));
      elsif Before.State /= Model.Running
        or else Before.Phase /= Model.Armed
        or else After.State /= Model.Running
        or else not After.Wake_Saved
      then
         Fail;
      end if;
   end Make_Ready_Exact;

   procedure Block_Current_And_Release
     (Core    : Core_Number;
      Token   : Model.Generation;
      Blocked : out Boolean)
   is
      Published : Model.Wait_State;
   begin
      if Wait_States (Core).Token /= Token
        or else Task_States (Core) /= Model.Running
        or else Current_Tasks (Core) /= Reference_For (Core)
      then
         Fail;
      end if;

      Published := Model.Publish_Wait (Wait_States (Core));
      Wait_States (Core) := Published;
      Blocked := Published.State = Model.Blocked;
      if Blocked then
         Apply_Transition (Task_States (Core), Model.Block);
         Current_Tasks (Core) := Model.No_Task;
      elsif Published.State /= Model.Running
        or else Published.Phase /= Model.No_Wait
      then
         Fail;
      end if;
      Leave_Kernel;
   end Block_Current_And_Release;

   procedure Initialize is
   begin
      Task_States := [others => Model.Dormant];
      Task_Steps := [others => 0];
      Current_Tasks := [others => Model.No_Task];
      Ready_Queues :=
        [others =>
           (Storage => [others => Model.No_Task], Length => 0)];
      Request_States :=
        [others =>
           (Requested    => Requests.Request_Epoch'First,
            Acknowledged => Requests.Request_Epoch'First,
            Reasons      => Requests.No_Reasons)];
      for Core in Core_Number loop
         Wait_States (Core) :=
           (Reference  => Reference_For (Core),
            State      => Model.Running,
            Phase      => Model.No_Wait,
            Token      => Model.Generation'First,
            Wake_Saved => False);
      end loop;
   end Initialize;

   procedure Check_Request_Model (Core : Core_Number) is
      Seen  : Requests.Dispatch_Snapshot;
   begin
      Request_States (Core) := Requests.Post_Request
        (Request_States (Core), Requests.Remote_Ready);
      Seen := Requests.Snapshot (Request_States (Core));
      Request_States (Core) := Requests.Post_Request
        (Request_States (Core), Requests.Timer);
      Request_States (Core) := Requests.Acknowledge
        (Request_States (Core), Seen);
      if not Requests.Is_Pending (Request_States (Core))
        or else Request_States (Core).Acknowledged /= Requests.Epoch_Of (Seen)
        or else Request_States (Core).Requested = Requests.Epoch_Of (Seen)
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

      Check_Request_Model (Core);

      if Task_Stacks (Core) (Task_Stack'First)'Address
        > System.Address'Last - System.Address (Task_Stack_Size)
      then
         Fail;
      end if;
      Stack_Top := Task_Stacks (Core) (Task_Stack'First)'Address
        + System.Address (Task_Stack_Size);
      Architecture.Initialize (Task_Contexts (Core), Stack_Top, Raw_Core);

      Enter_Kernel;
      Apply_Transition (Task_States (Core), Model.Admit);
      Enqueue_Ready (Core, Reference_For (Core));
      Dispatch_Next (Core);
      Leave_Kernel;
      Architecture.Switch
        (Dispatcher_Contexts (Core)'Access, Task_Contexts (Core)'Access);

      Enter_Kernel;
      if Task_States (Core) /= Model.Blocked
        or else Task_Steps (Core) /= 1
        or else Current_Tasks (Core) /= Model.No_Task
      then
         Fail;
      end if;
      declare
         Won : Boolean;
      begin
         Make_Ready_Exact (Core, Wait_States (Core).Token, Won);
         if not Won then
            Fail;
         end if;
      end;
      Dispatch_Next (Core);
      Leave_Kernel;
      Architecture.Switch
        (Dispatcher_Contexts (Core)'Access, Task_Contexts (Core)'Access);

      Enter_Kernel;
      if Task_States (Core) /= Model.Terminated
        or else Task_Steps (Core) /= 2
        or else Current_Tasks (Core) /= Model.No_Task
      then
         Fail;
      end if;
      Leave_Kernel;
      Report_Pass (Raw_Core);
   end Core_Entry;

   procedure Task_Start (Core_Value : System.Address) is
      Core       : Core_Number;
      Token      : Model.Generation;
      Won        : Boolean;
      Did_Block  : Boolean;
   begin
      if Core_Value > System.Address (Core_Number'Last) then
         Fail;
      end if;
      Core := Core_Number (Core_Value);
      Enter_Kernel;
      if Task_States (Core) /= Model.Running
        or else Task_Steps (Core) /= 0
        or else Current_Tasks (Core) /= Reference_For (Core)
      then
         Fail;
      end if;

      Arm_Wait (Core, Token);
      Make_Ready_Exact (Core, Token, Won);
      if not Won then
         Fail;
      end if;
      Block_Current_And_Release (Core, Token, Did_Block);
      if Did_Block then
         Fail;
      end if;

      Enter_Kernel;
      Arm_Wait (Core, Token);
      Task_Steps (Core) := 1;
      Block_Current_And_Release (Core, Token, Did_Block);
      if not Did_Block then
         Fail;
      end if;
      Architecture.Switch
        (Task_Contexts (Core)'Access, Dispatcher_Contexts (Core)'Access);

      Enter_Kernel;
      if Task_States (Core) /= Model.Running
        or else Task_Steps (Core) /= 1
        or else Current_Tasks (Core) /= Reference_For (Core)
      then
         Fail;
      end if;
      Task_Steps (Core) := 2;
      Apply_Transition (Task_States (Core), Model.Terminate_Task);
      Current_Tasks (Core) := Model.No_Task;
      Leave_Kernel;
      Architecture.Switch
        (Task_Contexts (Core)'Access, Dispatcher_Contexts (Core)'Access);
      Fail;
   end Task_Start;
end Flyology.M2_Runtime;
