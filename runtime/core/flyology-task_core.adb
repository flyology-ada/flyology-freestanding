--  SPDX-License-Identifier: MIT OR Apache-2.0

with Flyology.M2_Architecture;
with Flyology.Priority_Queue_Model;
with Flyology.Wait_Arbitration_Model;

package body Flyology.Task_Core is
   package Architecture renames Flyology.M2_Architecture;
   package Scheduler renames Flyology.Priority_Queue_Model;
   package Waits renames Flyology.Wait_Arbitration_Model;
   use type Dispatcher.Task_Ref;
   use type Dispatcher.Task_Slot;
   use type Dispatcher.Task_State;
   use type Dispatcher.Generation;
   use type Dispatcher.Priority;
   use type Scheduler.Enqueue_Status;
   use type Scheduler.Change_Status;
   use type Scheduler.Arrival_Sequence;
   use type Waits.Arm_Status;
   use type Waits.Commit_Status;
   use type Waits.Resolve_Status;
   use type Waits.Resume_Status;
   use type System.Address;

   Dispatcher_Stack_Size : constant := 16 * 1_024;
   Task_Stack_Size       : constant := 64 * 1_024;
   Stack_Canary_Length   : constant := 32;

   type Stack_Byte is mod 2 ** 8 with Size => 8;
   type Dispatcher_Stack is array
     (Natural range 0 .. Dispatcher_Stack_Size - 1) of Stack_Byte
     with Component_Size => 8, Alignment => 16;
   type Task_Stack is array
     (Natural range 0 .. Task_Stack_Size - 1) of Stack_Byte
     with Component_Size => 8, Alignment => 16;

   type Dispatcher_Stack_Array is
     array (Core_Number) of aliased Dispatcher_Stack;
   type Task_Stack_Array is array (Task_Slot) of aliased Task_Stack;
   type Context_Array is array (Task_Slot) of aliased Architecture.Context;
   type Dispatcher_Context_Array is
     array (Core_Number) of aliased Architecture.Context;

   type Kernel_Task is record
      Present       : Boolean := False;
      Reference     : Task_Ref := No_Task;
      State         : Task_State := Dispatcher.Dormant;
      Assigned_Core : Core_Number := 0;
      Base_Priority : Dispatcher.Priority := Dispatcher.Priority'First;
      Active_Priority : Dispatcher.Priority := Dispatcher.Priority'First;
      Wait          : Waits.Wait_State;
   end record;
   type Kernel_Task_Array is array (Task_Slot) of Kernel_Task;
   type Current_Array is array (Core_Number) of Task_Ref;
   type Queue_Array is array (Core_Number) of Scheduler.Ready_Queue;
   type Boolean_Core_Array is array (Core_Number) of Boolean;

   Dispatcher_Stacks   : Dispatcher_Stack_Array;
   Task_Stacks         : Task_Stack_Array;
   Task_Contexts       : Context_Array;
   Dispatcher_Contexts : Dispatcher_Context_Array;
   Bootstrap_Contexts  : Dispatcher_Context_Array;
   Dispatcher_Ready    : Boolean_Core_Array := [others => False];
   Tasks               : Kernel_Task_Array;
   Current_Tasks       : Current_Array := [others => No_Task];
   Ready_Queues        : Queue_Array;
   Next_Sequence       : Scheduler.Arrival_Sequence :=
     Scheduler.Arrival_Sequence'First + 1;
   Configured          : Positive range 1 .. Max_Cores := 1;

   procedure Enter_Kernel
   with Import, Convention => C, External_Name => "flyology_rts_lock_acquire";

   procedure Leave_Kernel
   with Import, Convention => C, External_Name => "flyology_rts_lock_release";

   procedure Publish_Ready
   with Import, Convention => C,
        External_Name => "flyology_m3_dispatcher_ready";

   procedure Enable_Dispatch
   with Import, Convention => C,
        External_Name => "flyology_m2_enable_dispatch";

   procedure Prepare_Idle
   with Import, Convention => C,
        External_Name => "flyology_m3_prepare_idle";

   procedure Idle
   with Import, Convention => C, External_Name => "flyology_m3_idle";

   procedure Report_Failure
   with Import, Convention => C, External_Name => "flyology_m2_report_failure";

   procedure Stop is
   begin
      Report_Failure;
      loop
         null;
      end loop;
   end Stop;

   function Slot_Of (Reference : Task_Ref) return Task_Slot is
   begin
      if Reference = No_Task or else Reference.Slot > Task_Slot'Last then
         Stop;
      end if;
      return Task_Slot (Reference.Slot);
   end Slot_Of;

   function Canary_Value (Slot : Task_Slot) return Stack_Byte is
     (Stack_Byte (16#A5# + Natural (Slot)));

   procedure Initialize_Canary (Slot : Task_Slot) is
   begin
      for Index in 0 .. Stack_Canary_Length - 1 loop
         Task_Stacks (Slot) (Index) := Canary_Value (Slot);
      end loop;
   end Initialize_Canary;

   function Canary_Is_Valid (Slot : Task_Slot) return Boolean is
   begin
      for Index in 0 .. Stack_Canary_Length - 1 loop
         if Task_Stacks (Slot) (Index) /= Canary_Value (Slot) then
            return False;
         end if;
      end loop;
      return True;
   end Canary_Is_Valid;

   function Apply
     (Before     : Task_State;
      Transition : Dispatcher.Transition_Kind) return Task_State
   is
      Attempt : constant Dispatcher.Transition_Attempt :=
        Dispatcher.Try_Transition (Before, Transition);
   begin
      if not Attempt.Accepted then
         Stop;
      end if;
      return Attempt.State;
   end Apply;

   procedure Initialize (CPU_Count : Positive) is
   begin
      if CPU_Count > Max_Cores then
         Stop;
      end if;
      Configured := CPU_Count;
      Current_Tasks := [others => No_Task];
      Ready_Queues := [others => (others => <>)];
      Next_Sequence := Scheduler.Arrival_Sequence'First + 1;
      Dispatcher_Ready := [others => False];
      Tasks := [others => (others => <>)];
   end Initialize;

   function CPU_Count return Positive is (Configured);

   procedure Enqueue_Locked
     (Reference : Task_Ref;
      Core      : Core_Number)
   is
      Slot    : constant Task_Slot := Slot_Of (Reference);
      Attempt : Scheduler.Enqueue_Result;
   begin
      if Next_Sequence = Scheduler.Arrival_Sequence'Last then
         Stop;
      end if;
      Attempt := Scheduler.Enqueue
        (Ready_Queues (Core),
         (Reference => Reference,
          Priority  => Tasks (Slot).Active_Priority,
          Sequence  => Next_Sequence));
      if Attempt.Status /= Scheduler.Enqueued then
         Stop;
      end if;
      Ready_Queues (Core) := Attempt.Queue;
      Next_Sequence := Next_Sequence + 1;
   end Enqueue_Locked;

   function Known_Locked (Reference : Task_Ref) return Boolean is
      Slot : Task_Slot;
   begin
      if Reference = No_Task or else Reference.Slot > Task_Slot'Last then
         return False;
      end if;
      Slot := Task_Slot (Reference.Slot);
      return Tasks (Slot).Present and then Tasks (Slot).Reference = Reference;
   end Known_Locked;

   procedure Register_Environment_Locked (Reference : Task_Ref) is
      Slot : constant Task_Slot := Slot_Of (Reference);
   begin
      if Slot /= 0 or else Tasks (Slot).Present
        or else Current_Tasks (0) /= No_Task
      then
         Stop;
      end if;
      Tasks (Slot) :=
        (Present => True, Reference => Reference,
         State => Dispatcher.Running, Assigned_Core => 0,
         Base_Priority => Dispatcher.Priority'First,
         Active_Priority => Dispatcher.Priority'First,
         Wait =>
           (Reference => Reference, Kind => Waits.No_Wait,
            Phase => Waits.Idle, Generation => 0,
            Outcome => Waits.Pending));
      Current_Tasks (0) := Reference;
   end Register_Environment_Locked;

   procedure Register_Dormant_Locked (Reference : Task_Ref) is
      Slot : constant Task_Slot := Slot_Of (Reference);
   begin
      if Slot = 0 or else Tasks (Slot).Present then
         Stop;
      end if;
      Tasks (Slot) :=
        (Present => True, Reference => Reference,
         State => Dispatcher.Dormant, Assigned_Core => 0,
         Base_Priority => Dispatcher.Priority'First,
         Active_Priority => Dispatcher.Priority'First,
         Wait =>
           (Reference => Reference, Kind => Waits.No_Wait,
            Phase => Waits.Idle, Generation => 0,
            Outcome => Waits.Pending));
   end Register_Dormant_Locked;

   function State_Locked (Reference : Task_Ref) return Task_State is
      Slot : constant Task_Slot := Slot_Of (Reference);
   begin
      if not Known_Locked (Reference) then
         Stop;
      end if;
      return Tasks (Slot).State;
   end State_Locked;

   function Current_Locked (Core : Core_Number) return Task_Ref is
     (Current_Tasks (Core));

   function Assigned_Core_Locked (Reference : Task_Ref) return Core_Number is
      Slot : constant Task_Slot := Slot_Of (Reference);
   begin
      if not Known_Locked (Reference) then
         Stop;
      end if;
      return Tasks (Slot).Assigned_Core;
   end Assigned_Core_Locked;

   function Queue_Space_Locked (Core : Core_Number) return Natural is
     (Scheduler.Capacity - Ready_Queues (Core).Length);

   procedure Activate_Locked
     (Reference : Task_Ref;
      Core      : Core_Number;
      Priority  : Dispatcher.Priority)
   is
      Slot    : constant Task_Slot := Slot_Of (Reference);
      Base    : constant System.Address :=
        Task_Stacks (Slot) (Task_Stack'First)'Address;
   begin
      if Natural (Core) >= Configured or else not Known_Locked (Reference) then
         Stop;
      end if;
      Tasks (Slot).State := Apply (Tasks (Slot).State, Dispatcher.Admit);
      Tasks (Slot).Assigned_Core := Core;
      Tasks (Slot).Base_Priority := Priority;
      Tasks (Slot).Active_Priority := Priority;
      Initialize_Canary (Slot);
      Architecture.Initialize
        (Task_Contexts (Slot), Base + System.Address (Task_Stack_Size),
         System.Address (Slot));
      Enqueue_Locked (Reference, Core);
   end Activate_Locked;

   procedure Arm_Wait_Locked
     (Reference : Task_Ref;
      Kind      : Wait_Kind;
      Token     : out Wait_Token)
   is
      Slot    : constant Task_Slot := Slot_Of (Reference);
      Attempt : Waits.Arm_Result;
   begin
      if not Known_Locked (Reference) then
         Stop;
      end if;
      Attempt := Waits.Arm (Tasks (Slot).Wait, Tasks (Slot).State, Kind);
      if Attempt.Status /= Waits.Armed_Now then
         Stop;
      end if;
      Tasks (Slot).Wait := Attempt.State;
      Token :=
        (Task_Reference => Reference,
         Generation => Tasks (Slot).Wait.Generation);
   end Arm_Wait_Locked;

   procedure Resolve_Exact_Locked
     (Token   : Wait_Token;
      Outcome : Wait_Resolution;
      Status  : out Wait_Resolve_Status;
      Core    : out Core_Number)
   is
      Reference : constant Task_Ref := Token.Task_Reference;
      Slot      : constant Task_Slot := Slot_Of (Reference);
      Attempt   : Waits.Resolve_Result;
   begin
      if not Known_Locked (Reference) then
         Stop;
      end if;
      Core := Tasks (Slot).Assigned_Core;
      Attempt := Waits.Resolve
        (Tasks (Slot).Wait, Tasks (Slot).State, Reference,
         Token.Generation, Outcome);
      Tasks (Slot).Wait := Attempt.State;
      Tasks (Slot).State := Attempt.Task_State;
      Status := Attempt.Status;
      if Status = Waits.Made_Ready then
         Enqueue_Locked (Reference, Core);
      end if;
   end Resolve_Exact_Locked;

   procedure Block_Current_And_Release
     (Core    : Core_Number;
      Token   : Wait_Token;
      Outcome : out Wait_Resolution)
   is
      Reference : constant Task_Ref := Token.Task_Reference;
      Slot      : constant Task_Slot := Slot_Of (Reference);
      Commit    : Waits.Commit_Result;
      Resume    : Waits.Resume_Result;
   begin
      if Current_Tasks (Core) /= Reference or else not Known_Locked (Reference)
        or else Tasks (Slot).Wait.Generation /= Token.Generation
      then
         Stop;
      end if;
      Commit := Waits.Commit_Block (Tasks (Slot).Wait, Tasks (Slot).State);
      if Commit.Status = Waits.Already_Satisfied then
         Tasks (Slot).Wait := Commit.State;
         Tasks (Slot).State := Commit.Task_State;
         Outcome := Commit.Outcome;
         Leave_Kernel;
         return;
      elsif Commit.Status /= Waits.Blocked_Now then
         Stop;
      end if;
      Tasks (Slot).Wait := Commit.State;
      Tasks (Slot).State := Commit.Task_State;
      Current_Tasks (Core) := No_Task;
      Leave_Kernel;
      Architecture.Switch
        (Task_Contexts (Slot)'Access, Dispatcher_Contexts (Core)'Access);
      Enter_Kernel;
      if Current_Tasks (Core) /= Reference
        or else Tasks (Slot).State /= Dispatcher.Running
      then
         Leave_Kernel;
         Stop;
      end if;
      Resume := Waits.Resume (Tasks (Slot).Wait, Tasks (Slot).State);
      if Resume.Status /= Waits.Consumed then
         Leave_Kernel;
         Stop;
      end if;
      Tasks (Slot).Wait := Resume.State;
      Outcome := Resume.Outcome;
      Leave_Kernel;
   end Block_Current_And_Release;

   procedure Change_Active_Priority_Locked
     (Reference : Task_Ref;
      Priority  : Dispatcher.Priority)
   is
      Slot    : constant Task_Slot := Slot_Of (Reference);
      Core    : Core_Number;
      Attempt : Scheduler.Change_Result;
   begin
      if not Known_Locked (Reference) then
         Stop;
      end if;
      if Tasks (Slot).State = Dispatcher.Ready then
         Core := Tasks (Slot).Assigned_Core;
         Attempt := Scheduler.Change_Priority
           (Ready_Queues (Core), Reference, Priority);
         if Attempt.Status /= Scheduler.Changed then
            Stop;
         end if;
         Ready_Queues (Core) := Attempt.Queue;
      end if;
      Tasks (Slot).Active_Priority := Priority;
   end Change_Active_Priority_Locked;

   function Active_Priority_Locked
     (Reference : Task_Ref) return Dispatcher.Priority
   is
      Slot : constant Task_Slot := Slot_Of (Reference);
   begin
      if not Known_Locked (Reference) then
         Stop;
      end if;
      return Tasks (Slot).Active_Priority;
   end Active_Priority_Locked;

   procedure Terminate_Current_Locked
     (Core      : Core_Number;
      Reference : Task_Ref)
   is
      Slot : constant Task_Slot := Slot_Of (Reference);
   begin
      if Current_Tasks (Core) /= Reference or else not Known_Locked (Reference)
      then
         Stop;
      end if;
      Tasks (Slot).State :=
        Apply (Tasks (Slot).State, Dispatcher.Terminate_Task);
      Current_Tasks (Core) := No_Task;
   end Terminate_Current_Locked;

   function Current (Core : Core_Number) return Task_Ref is
      Result : Task_Ref;
   begin
      Enter_Kernel;
      Result := Current_Tasks (Core);
      Leave_Kernel;
      return Result;
   end Current;

   function Is_Callable (Reference : Task_Ref) return Boolean is
      Result : Boolean;
   begin
      Enter_Kernel;
      Result := Known_Locked (Reference)
        and then State_Locked (Reference) /= Dispatcher.Terminated;
      Leave_Kernel;
      return Result;
   end Is_Callable;

   function Is_Terminated (Reference : Task_Ref) return Boolean is
      Result : Boolean;
   begin
      Enter_Kernel;
      Result := Known_Locked (Reference)
        and then State_Locked (Reference) = Dispatcher.Terminated;
      Leave_Kernel;
      return Result;
   end Is_Terminated;

   function Validate_Current_Stack
     (Core  : Core_Number;
      Probe : System.Address) return Boolean
   is
      Reference : Task_Ref;
      Slot      : Task_Slot;
      Base      : System.Address;
   begin
      Enter_Kernel;
      Reference := Current_Tasks (Core);
      if not Known_Locked (Reference) or else Reference.Slot = 0 then
         Leave_Kernel;
         return False;
      end if;
      Slot := Task_Slot (Reference.Slot);
      Base := Task_Stacks (Slot) (Task_Stack'First)'Address;
      declare
         Result : constant Boolean :=
           Base <= System.Address'Last - System.Address (Task_Stack_Size)
           and then Probe >= Base + System.Address (Stack_Canary_Length)
           and then Probe < Base + System.Address (Task_Stack_Size)
           and then Canary_Is_Valid (Slot);
      begin
         Leave_Kernel;
         return Result;
      end;
   end Validate_Current_Stack;

   procedure Initialize_Dispatcher (Core : Core_Number) is
      Base : constant System.Address :=
        Dispatcher_Stacks (Core) (Dispatcher_Stack'First)'Address;
   begin
      Architecture.Initialize_Dispatcher
        (Dispatcher_Contexts (Core),
         Base + System.Address (Dispatcher_Stack_Size), System.Address (Core));
   end Initialize_Dispatcher;

   procedure Prepare_Environment (Core : System.Address) is
   begin
      if Core /= 0 or else Dispatcher_Ready (0) then
         Stop;
      end if;
      Initialize_Dispatcher (0);
      Dispatcher_Ready (0) := True;
      Publish_Ready;
   end Prepare_Environment;

   procedure Prepare_AP (Core : System.Address) is
      Dense : Core_Number;
   begin
      if Core = 0 or else Core >= System.Address (Configured) then
         Stop;
      end if;
      Dense := Core_Number (Core);
      if Dispatcher_Ready (Dense) then
         Stop;
      end if;
      Initialize_Dispatcher (Dense);
      Architecture.Switch
        (Bootstrap_Contexts (Dense)'Access, Dispatcher_Contexts (Dense)'Access);
      Stop;
   end Prepare_AP;

   procedure Dispatcher_Start (Core : System.Address) is
      Dense     : Core_Number;
      Choice    : Scheduler.Selection;
      Reference : Task_Ref;
      Slot      : Task_Slot;
   begin
      if Core >= System.Address (Configured) then
         Stop;
      end if;
      Dense := Core_Number (Core);
      Enable_Dispatch;
      if Dense /= 0 then
         if Dispatcher_Ready (Dense) then
            Stop;
         end if;
         Dispatcher_Ready (Dense) := True;
         Publish_Ready;
      elsif not Dispatcher_Ready (Dense) then
         Stop;
      end if;
      loop
         Enter_Kernel;
         Choice := Scheduler.Select_Next (Ready_Queues (Dense));
         if not Choice.Found then
            Prepare_Idle;
            Leave_Kernel;
            Idle;
         else
            Ready_Queues (Dense) := Choice.Remainder;
            Reference := Choice.Item.Reference;
            Slot := Slot_Of (Reference);
            if not Known_Locked (Reference)
              or else Current_Tasks (Dense) /= No_Task
              or else Tasks (Slot).Assigned_Core /= Dense
            then
               Leave_Kernel;
               Stop;
            end if;
            Tasks (Slot).State :=
              Apply (Tasks (Slot).State, Dispatcher.Dispatch);
            Current_Tasks (Dense) := Reference;
            Leave_Kernel;
            Architecture.Switch
              (Dispatcher_Contexts (Dense)'Access,
               Task_Contexts (Slot)'Access);
            if Slot /= 0 and then not Canary_Is_Valid (Slot) then
               Stop;
            end if;
         end if;
      end loop;
   end Dispatcher_Start;

   procedure Switch_To_Dispatcher
     (Core      : Core_Number;
      Reference : Task_Ref)
   is
      Slot : constant Task_Slot := Slot_Of (Reference);
   begin
      Architecture.Switch
        (Task_Contexts (Slot)'Access, Dispatcher_Contexts (Core)'Access);
      Stop;
   end Switch_To_Dispatcher;

   procedure Environment_Complete is
      Environment : Task_Ref;
   begin
      Enter_Kernel;
      Environment := Current_Tasks (0);
      Terminate_Current_Locked (0, Environment);
      Leave_Kernel;
      Switch_To_Dispatcher (0, Environment);
   end Environment_Complete;
end Flyology.Task_Core;
