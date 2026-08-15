--  SPDX-License-Identifier: MIT OR Apache-2.0

with Flyology_Freestanding.Platform;
with Flyology_Freestanding.Ceiling_Model;
with Flyology_Freestanding.Domain_Model;
with Flyology_Freestanding.Preemption_Model;
with Flyology_Freestanding.Priority_Queue_Model;
with Flyology_Freestanding.Scheduling_Configuration_Model;
with Flyology_Freestanding.Timer_Model;
with Flyology_Freestanding.Wait_Arbitration_Model;

package body Flyology_Freestanding.Kernel is
   package Architecture renames Flyology_Freestanding.Platform;
   package Ceilings renames Flyology_Freestanding.Ceiling_Model;
   package Domains renames Flyology_Freestanding.Domain_Model;
   package Preemption renames Flyology_Freestanding.Preemption_Model;
   package Scheduler renames Flyology_Freestanding.Priority_Queue_Model;
   package Scheduling renames Flyology_Freestanding.Scheduling_Configuration_Model;
   package Timers renames Flyology_Freestanding.Timer_Model;
   package Waits renames Flyology_Freestanding.Wait_Arbitration_Model;
   pragma Compile_Time_Error
     (Scheduling.Max_Cores /= Max_Cores,
      "scheduling configuration and kernel core capacities differ");
   use type Dispatcher.Task_Ref;
   use type Dispatcher.Task_Slot;
   use type Dispatcher.Task_State;
   use type Domains.Create_Status;
   use type Domains.Policy_Kind;
   use type Dispatcher.Generation;
   use type Dispatcher.Priority;
   use type Scheduler.Enqueue_Status;
   use type Scheduler.Requeue_Status;
   use type Scheduler.Arrival_Sequence;
   use type Scheduler.Queue_Position;
   use type Timers.Register_Status;
   use type Timers.Cancel_Status;
   use type Timers.Tick;
   use type Timers.Timer_Table;
   use type Waits.Arm_Status;
   use type Waits.Commit_Status;
   use type Waits.Resolve_Status;
   use type Waits.Resolution;
   use type Waits.Wait_Phase;
   use type Waits.Resume_Status;
   use type Ceilings.Enter_Status;
   use type Ceilings.Leave_Status;
   use type Preemption.Policy_Kind;
   use type Preemption.Preemption_Cause;
   use type Preemption.Clock.Tick;
   use type Scheduling.Change_Status;
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
   type Full_Context_Array is
     array (Task_Slot) of aliased Architecture.Full_Context;
   type Dispatcher_Context_Array is
     array (Core_Number) of aliased Architecture.Context;

   type Kernel_Task is record
      Present       : Boolean := False;
      Reference     : Task_Ref := No_Task;
      State         : Task_State := Dispatcher.Dormant;
      Assigned_Core : Core_Number := 0;
      Domain        : Domain_Number := System_Domain;
      Priority      : Ceilings.Ceiling_State;
      Wait          : Waits.Wait_State;
      Budget        : Preemption.Budget_State := Preemption.Empty_Budget;
      Resume_Full   : Boolean := False;
   end record;
   type Kernel_Task_Array is array (Task_Slot) of Kernel_Task;
   type Current_Array is array (Core_Number) of Task_Ref;
   type Queue_Array is array (Core_Number) of Scheduler.Ready_Queue;
   type Timer_Array is array (Core_Number) of Timers.Timer_Table;
   type Boolean_Core_Array is array (Core_Number) of Boolean;
   type Domain_Core_Array is array (Core_Number) of Domain_Number;
   type Boolean_Domain_Array is array (Domain_Number) of Boolean;
   type Policy_Domain_Array is
     array (Domain_Number) of Preemption.Policy_Kind;
   type Policy_Core_Array is
     array (Core_Number) of Preemption.Policy_Kind;
   type Quantum_Core_Array is
     array (Core_Number) of Preemption.Clock.Tick;
   type Slice_Core_Array is
     array (Core_Number) of Preemption.Binder_Time_Slice;

   Dispatcher_Stacks   : Dispatcher_Stack_Array;
   Task_Stacks         : Task_Stack_Array;
   Task_Contexts       : Context_Array;
   Full_Contexts       : Full_Context_Array;
   Dispatcher_Contexts : Dispatcher_Context_Array;
   Bootstrap_Contexts  : Dispatcher_Context_Array;
   Dispatcher_Ready    : Boolean_Core_Array := [others => False];
   Tasks               : Kernel_Task_Array;
   Current_Tasks       : Current_Array := [others => No_Task];
   Ready_Queues        : Queue_Array;
   Timer_Tables        : Timer_Array := [others => Timers.Empty_Table];
   Next_Sequence       : Scheduler.Arrival_Sequence :=
     Scheduler.Arrival_Sequence'First + 1;
   Configured          : Positive range 1 .. Max_Cores := 1;
   On_Retirement       : Retirement_Hook := null;
   Core_Domains        : Domain_Core_Array := [others => System_Domain];
   Domain_Used         : Boolean_Domain_Array :=
     [System_Domain => True, others => False];
   Domain_Policies     : Policy_Domain_Array :=
     [others => Preemption.FIFO_Within_Priorities];
   Core_Policies       : Policy_Core_Array :=
     [others => Preemption.FIFO_Within_Priorities];
   Core_Quanta         : Quantum_Core_Array := [others => 0];
   Core_Slices         : Slice_Core_Array := [others => 0];
   Policy_Configured   : Boolean := False;

   procedure Enter_Kernel
   with Import, Convention => C, External_Name => "flyology_freestanding_rts_lock_acquire";

   function Try_Enter_Kernel return Boolean
   with Import, Convention => C,
        External_Name => "flyology_freestanding_rts_lock_try_acquire";

   procedure Leave_Kernel
   with Import, Convention => C, External_Name => "flyology_freestanding_rts_lock_release";

   procedure Publish_Ready
   with Import, Convention => C,
        External_Name => "flyology_freestanding_platform_dispatcher_ready";

   procedure Enable_Dispatch
   with Import, Convention => C,
        External_Name => "flyology_freestanding_platform_enable_dispatch";

   procedure Disable_Dispatch
   with Import, Convention => C,
        External_Name => "flyology_freestanding_platform_disable_dispatch";

   procedure Prepare_Idle
   with Import, Convention => C,
        External_Name => "flyology_freestanding_platform_prepare_idle";

   procedure Idle
   with Import, Convention => C, External_Name => "flyology_freestanding_platform_idle";

   procedure Report_Failure
   with Import, Convention => C, External_Name => "flyology_freestanding_conformance_report_failure";

   function Interrupt_Dispatch
     (Frame_Address : System.Address;
      Core_Address  : System.Address) return System.Address
   with Export, Convention => C,
        External_Name => "flyology_freestanding_kernel_interrupt_dispatch";

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

   function Policy_For (Core : Core_Number) return Preemption.Policy_Kind is
     (Core_Policies (Core));

   function Quantum_For (Core : Core_Number) return Preemption.Clock.Tick is
     (Core_Quanta (Core));

   procedure Initialize (CPU_Count : Positive) is
   begin
      if CPU_Count > Max_Cores then
         Stop;
      end if;
      Configured := CPU_Count;
      Current_Tasks := [others => No_Task];
      Ready_Queues := [others => (others => <>)];
      Timer_Tables := [others => Timers.Empty_Table];
      Next_Sequence := Scheduler.Arrival_Sequence'First + 1;
      Dispatcher_Ready := [others => False];
      Tasks := [others => (others => <>)];
      Core_Domains := [others => System_Domain];
      Domain_Used := [System_Domain => True, others => False];
      Domain_Policies := [others => Preemption.FIFO_Within_Priorities];
      Core_Policies := [others => Preemption.FIFO_Within_Priorities];
      Core_Quanta := [others => 0];
      Core_Slices := [others => 0];
      Policy_Configured := False;
   end Initialize;

   package Domain_Operations is
      procedure Configure_Dispatching
        (Policy : Dispatching_Policy;
         Slice  : Binder_Time_Slice);
      procedure Change_Global_Policy_Locked
        (Policy   : Dispatching_Policy;
         Slice    : Binder_Time_Slice;
         Affected : out Core_Set);
      procedure Change_Domain_Policy_Locked
        (Cores    : Core_Set;
         Policy   : Dispatching_Policy;
         Slice    : Binder_Time_Slice;
         Affected : out Core_Set);
      procedure Change_Core_Policy_Locked
        (Core     : Core_Number;
         Policy   : Dispatching_Policy;
         Slice    : Binder_Time_Slice;
         Affected : out Core_Set);
      function Policy_Of_Core_Locked
        (Core : Core_Number) return Dispatching_Policy;
      function Slice_Of_Core_Locked
        (Core : Core_Number) return Binder_Time_Slice;
      procedure Try_Create_Domain_Locked
        (Cores   : Core_Set;
         Policy  : Dispatching_Policy;
         Slice   : Binder_Time_Slice;
         Domain  : out Domain_Number;
         Created : out Boolean);
      function Domain_Is_Used_Locked
        (Domain : Domain_Number) return Boolean;
      function Domain_Policy_Locked
        (Domain : Domain_Number) return Dispatching_Policy;
      function Domain_Cores_Locked
        (Domain : Domain_Number) return Core_Set;
      function Domain_Of_Core_Locked
        (Core : Core_Number) return Domain_Number;
      function Domain_Of_Task_Locked
        (Reference : Task_Ref) return Domain_Number;
   end Domain_Operations;

   package body Domain_Operations is separate;

   procedure Configure_Dispatching
     (Policy : Dispatching_Policy;
      Slice  : Binder_Time_Slice)
   renames Domain_Operations.Configure_Dispatching;

   procedure Change_Global_Policy_Locked
     (Policy   : Dispatching_Policy;
      Slice    : Binder_Time_Slice;
      Affected : out Core_Set)
   renames Domain_Operations.Change_Global_Policy_Locked;

   procedure Change_Domain_Policy_Locked
     (Cores    : Core_Set;
      Policy   : Dispatching_Policy;
      Slice    : Binder_Time_Slice;
      Affected : out Core_Set)
   renames Domain_Operations.Change_Domain_Policy_Locked;

   procedure Change_Core_Policy_Locked
     (Core     : Core_Number;
      Policy   : Dispatching_Policy;
      Slice    : Binder_Time_Slice;
      Affected : out Core_Set)
   renames Domain_Operations.Change_Core_Policy_Locked;

   function Policy_Of_Core_Locked
     (Core : Core_Number) return Dispatching_Policy
   renames Domain_Operations.Policy_Of_Core_Locked;

   function Slice_Of_Core_Locked
     (Core : Core_Number) return Binder_Time_Slice
   renames Domain_Operations.Slice_Of_Core_Locked;

   procedure Try_Create_Domain_Locked
     (Cores   : Core_Set;
      Policy  : Dispatching_Policy;
      Slice   : Binder_Time_Slice;
      Domain  : out Domain_Number;
      Created : out Boolean)
   renames Domain_Operations.Try_Create_Domain_Locked;

   function Domain_Is_Used_Locked (Domain : Domain_Number) return Boolean
   renames Domain_Operations.Domain_Is_Used_Locked;

   function Domain_Policy_Locked
     (Domain : Domain_Number) return Dispatching_Policy
   renames Domain_Operations.Domain_Policy_Locked;

   function Domain_Cores_Locked (Domain : Domain_Number) return Core_Set
   renames Domain_Operations.Domain_Cores_Locked;

   function Domain_Of_Core_Locked (Core : Core_Number) return Domain_Number
   renames Domain_Operations.Domain_Of_Core_Locked;

   function Domain_Of_Task_Locked
     (Reference : Task_Ref) return Domain_Number
   renames Domain_Operations.Domain_Of_Task_Locked;

   function CPU_Count return Positive is (Configured);

   procedure Install_Retirement_Hook (Hook : Retirement_Hook) is
   begin
      if Hook = null or else On_Retirement /= null then
         Stop;
      end if;
      On_Retirement := Hook;
   end Install_Retirement_Hook;

   procedure Enqueue_Locked
     (Reference : Task_Ref;
      Core      : Core_Number;
      Position  : Scheduler.Queue_Position := Scheduler.At_Tail)
   is
      Slot    : constant Task_Slot := Slot_Of (Reference);
      Attempt : Scheduler.Enqueue_Result;
   begin
      if Next_Sequence = Scheduler.Arrival_Sequence'Last
        or else not Known_Locked (Reference)
        or else Tasks (Slot).Domain /= Core_Domains (Core)
      then
         Stop;
      end if;
      Attempt := Scheduler.Enqueue
        (Ready_Queues (Core),
         (Reference => Reference,
          Priority  => Tasks (Slot).Priority.Active,
          Sequence  => Next_Sequence,
          Position  => Position));
      if Attempt.Status /= Scheduler.Enqueued then
         Stop;
      end if;
      Ready_Queues (Core) := Attempt.Queue;
      if Position = Scheduler.At_Tail then
         Tasks (Slot).Budget := Preemption.Empty_Budget;
      end if;
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
         Domain => System_Domain,
         Priority => (others => <>),
         Wait =>
           (Reference => Reference, Kind => Waits.No_Wait,
            Phase => Waits.Idle, Generation => 0,
            Outcome => Waits.Pending),
         Budget => Preemption.Empty_Budget,
         Resume_Full => False);
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
         Domain => System_Domain,
         Priority => (others => <>),
         Wait =>
           (Reference => Reference, Kind => Waits.No_Wait,
            Phase => Waits.Idle, Generation => 0,
            Outcome => Waits.Pending),
         Budget => Preemption.Empty_Budget,
         Resume_Full => False);
      Initialize_Canary (Slot);
   end Register_Dormant_Locked;

   function Can_Cancel_Dormant_Locked
     (Reference : Task_Ref) return Boolean
   is
      Slot : Task_Slot;
   begin
      if Reference = No_Task
        or else Reference.Slot = 0
        or else Reference.Slot > Task_Slot'Last
      then
         return False;
      end if;
      Slot := Task_Slot (Reference.Slot);
      if not Known_Locked (Reference)
        or else Tasks (Slot).State /= Dispatcher.Dormant
        or else Tasks (Slot).Wait.Phase /= Waits.Idle
        or else not Canary_Is_Valid (Slot)
      then
         return False;
      end if;
      for Core in Core_Number loop
         if Current_Tasks (Core) = Reference
           or else Scheduler.Contains (Ready_Queues (Core), Reference)
           or else Timers.Contains_Task (Timer_Tables (Core), Reference)
         then
            return False;
         end if;
      end loop;
      return True;
   end Can_Cancel_Dormant_Locked;

   procedure Cancel_Dormant_Locked (Reference : Task_Ref) is
      Slot : constant Task_Slot := Slot_Of (Reference);
   begin
      if not Can_Cancel_Dormant_Locked (Reference) then
         Stop;
      end if;
      Tasks (Slot).State :=
        Apply (Tasks (Slot).State, Dispatcher.Cancel_Unactivated);
   end Cancel_Dormant_Locked;

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
      Domain    : Domain_Number;
      Core      : Core_Number;
      Priority  : Dispatcher.Priority)
   is
      Slot    : constant Task_Slot := Slot_Of (Reference);
      Base    : constant System.Address :=
        Task_Stacks (Slot) (Task_Stack'First)'Address;
   begin
      if Natural (Core) >= Configured
        or else not Domain_Used (Domain)
        or else Core_Domains (Core) /= Domain
        or else not Known_Locked (Reference)
      then
         Stop;
      end if;
      Tasks (Slot).State := Apply (Tasks (Slot).State, Dispatcher.Admit);
      Tasks (Slot).Assigned_Core := Core;
      Tasks (Slot).Domain := Domain;
      Tasks (Slot).Priority :=
        (Base => Priority, Active => Priority,
         Previous => [others => Dispatcher.Priority'First], Depth => 0);
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

   function Wait_Is_Pending_Locked (Token : Wait_Token) return Boolean is
      Slot : Task_Slot;
   begin
      if not Known_Locked (Token.Task_Reference) then
         return False;
      end if;
      Slot := Slot_Of (Token.Task_Reference);
      return Tasks (Slot).Wait.Reference = Token.Task_Reference
        and then Tasks (Slot).Wait.Generation = Token.Generation
        and then Tasks (Slot).Wait.Phase in Waits.Armed | Waits.Committed
        and then Tasks (Slot).Wait.Outcome = Waits.Pending;
   end Wait_Is_Pending_Locked;

   procedure Active_Wait_Locked
     (Reference : Task_Ref;
      Token     : out Wait_Token;
      Kind      : out Wait_Kind)
   is
      Slot : constant Task_Slot := Slot_Of (Reference);
   begin
      if not Known_Locked (Reference)
        or else Tasks (Slot).Wait.Phase not in Waits.Armed | Waits.Committed
        or else Tasks (Slot).Wait.Outcome /= Waits.Pending
      then
         Stop;
      end if;
      Token :=
        (Task_Reference => Reference,
         Generation => Tasks (Slot).Wait.Generation);
      Kind := Tasks (Slot).Wait.Kind;
   end Active_Wait_Locked;

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
      Tasks (Slot).Resume_Full := False;
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

   procedure Change_Base_Priority_Locked
     (Reference : Task_Ref;
      Priority  : Dispatcher.Priority)
   is
      Slot    : constant Task_Slot := Slot_Of (Reference);
      Core    : Core_Number;
      Attempt : Scheduler.Requeue_Result;
   begin
      if not Known_Locked (Reference) then
         Stop;
      end if;
      Tasks (Slot).Priority :=
        Ceilings.Change_Base (Tasks (Slot).Priority, Priority);
      if Tasks (Slot).State = Dispatcher.Ready then
         if Next_Sequence = Scheduler.Arrival_Sequence'Last then
            Stop;
         end if;
         Core := Tasks (Slot).Assigned_Core;
         Attempt := Scheduler.Requeue_Priority
           (Ready_Queues (Core), Reference, Tasks (Slot).Priority.Active,
            Next_Sequence);
         if Attempt.Status /= Scheduler.Requeued then
            Stop;
         end if;
         Ready_Queues (Core) := Attempt.Queue;
         Tasks (Slot).Budget := Preemption.Empty_Budget;
         Next_Sequence := Next_Sequence + 1;
      end if;
   end Change_Base_Priority_Locked;

   function Base_Priority_Locked
     (Reference : Task_Ref) return Dispatcher.Priority
   is
      Slot : constant Task_Slot := Slot_Of (Reference);
   begin
      if not Known_Locked (Reference) then
         Stop;
      end if;
      return Tasks (Slot).Priority.Base;
   end Base_Priority_Locked;

   function Active_Priority_Locked
     (Reference : Task_Ref) return Dispatcher.Priority
   is
      Slot : constant Task_Slot := Slot_Of (Reference);
   begin
      if not Known_Locked (Reference) then
         Stop;
      end if;
      return Tasks (Slot).Priority.Active;
   end Active_Priority_Locked;

   function Enter_Protected_Locked
     (Reference : Task_Ref;
      Ceiling   : Dispatcher.Priority) return Boolean
   is
      Slot    : constant Task_Slot := Slot_Of (Reference);
      Attempt : Ceilings.Enter_Result;
   begin
      if not Known_Locked (Reference)
        or else Tasks (Slot).State /= Dispatcher.Running
      then
         Stop;
      end if;
      Attempt := Ceilings.Enter (Tasks (Slot).Priority, Ceiling);
      if Attempt.Status = Ceilings.Ceiling_Violation then
         return False;
      elsif Attempt.Status /= Ceilings.Entered then
         Stop;
      end if;
      Tasks (Slot).Priority := Attempt.State;
      return True;
   end Enter_Protected_Locked;

   procedure Leave_Protected_Locked (Reference : Task_Ref) is
      Slot    : constant Task_Slot := Slot_Of (Reference);
      Attempt : Ceilings.Leave_Result;
   begin
      if not Known_Locked (Reference)
        or else Tasks (Slot).State /= Dispatcher.Running
      then
         Stop;
      end if;
      Attempt := Ceilings.Leave (Tasks (Slot).Priority);
      if Attempt.Status /= Ceilings.Left then
         Stop;
      end if;
      Tasks (Slot).Priority := Attempt.State;
   end Leave_Protected_Locked;

   function Read_Clock return Tick is
      Value : constant Architecture.Tick := Architecture.Read_Clock;
   begin
      return Tick (Value);
   end Read_Clock;

   function Clock_Frequency return Frequency is
      Raw : constant System.Address := Architecture.Clock_Frequency;
   begin
      if Raw < System.Address (Frequency'First)
        or else Raw > System.Address (Frequency'Last)
      then
         Stop;
      end if;
      return Frequency (Raw);
   end Clock_Frequency;

   procedure Register_Deadline_Locked
     (Token    : Wait_Token;
      Deadline : Tick)
   is
      Slot    : constant Task_Slot := Slot_Of (Token.Task_Reference);
      Core    : Core_Number;
      Attempt : Timers.Register_Result;
   begin
      if not Known_Locked (Token.Task_Reference) then
         Stop;
      end if;
      Core := Tasks (Slot).Assigned_Core;
      Attempt := Timers.Register (Timer_Tables (Core), Token, Deadline);
      if Attempt.Status /= Timers.Registered then
         Stop;
      end if;
      Timer_Tables (Core) := Attempt.Table;
   end Register_Deadline_Locked;

   procedure Cancel_Deadline_Locked
     (Token  : Wait_Token;
      Status : out Timer_Cancel_Status)
   is
      Slot    : constant Task_Slot := Slot_Of (Token.Task_Reference);
      Core    : Core_Number;
      Attempt : Timers.Cancel_Result;
   begin
      if not Known_Locked (Token.Task_Reference) then
         Stop;
      end if;
      Core := Tasks (Slot).Assigned_Core;
      Attempt := Timers.Cancel (Timer_Tables (Core), Token);
      Timer_Tables (Core) := Attempt.Table;
      Status := Attempt.Status;
   end Cancel_Deadline_Locked;

   procedure Drain_Timers_Locked (Core : Core_Number) is
      Now       : constant Tick := Read_Clock;
      Expiry    : Timers.Expiry_Result;
      Status    : Waits.Resolve_Status;
      Wake_Core : Core_Number;
   begin
      loop
         Expiry := Timers.Take_Due (Timer_Tables (Core), Now);
         exit when not Expiry.Found;
         Timer_Tables (Core) := Expiry.Table;
         Resolve_Exact_Locked
           (Expiry.Token, Waits.Timer_Expiry, Status, Wake_Core);
         if Status not in Waits.Won_Before_Block | Waits.Made_Ready |
           Waits.Duplicate | Waits.Stale
         then
            Stop;
         end if;
      end loop;
   end Drain_Timers_Locked;

   procedure Program_Next_Timer_Locked (Core : Core_Number) is
      Next      : constant Timers.Deadline_Result :=
        Timers.Earliest (Timer_Tables (Core));
      Found     : Boolean := Next.Found;
      Deadline  : Tick := Next.Deadline;
      Reference : Task_Ref;
      Slot      : Task_Slot;
   begin
      Reference := Current_Tasks (Core);
      if Reference /= No_Task then
         Slot := Slot_Of (Reference);
         if not Known_Locked (Reference)
           or else Tasks (Slot).State /= Dispatcher.Running
         then
            Stop;
         end if;
         if Policy_For (Core) = Preemption.Round_Robin_Within_Priorities
           and then Tasks (Slot).Budget.Armed
           and then Tasks (Slot).Budget.Remaining > 0
         then
            if not Preemption.Clock.Deadline_Fits
              (Tasks (Slot).Budget.Last_Accounted,
               Tasks (Slot).Budget.Remaining)
            then
               Stop;
            end if;
            declare
               Budget_Deadline : constant Tick := Tick
                 (Preemption.Clock.Add_Delay
                    (Tasks (Slot).Budget.Last_Accounted,
                     Tasks (Slot).Budget.Remaining));
            begin
               if not Found or else Budget_Deadline < Deadline then
                  Deadline := Budget_Deadline;
                  Found := True;
               end if;
            end;
         end if;
      end if;
      if Found then
         Architecture.Program_Timer (Architecture.Tick (Deadline));
      else
         Architecture.Cancel_Timer;
      end if;
   end Program_Next_Timer_Locked;

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
      Tasks (Slot).Resume_Full := False;
      Current_Tasks (Core) := No_Task;
   end Terminate_Current_Locked;

   procedure Begin_Retirement_Locked
     (Core      : Core_Number;
      Reference : Task_Ref)
   is
      Slot : constant Task_Slot := Slot_Of (Reference);
   begin
      if Slot = 0
        or else Current_Tasks (Core) /= Reference
        or else not Known_Locked (Reference)
        or else Tasks (Slot).Assigned_Core /= Core
      then
         Stop;
      end if;
      Tasks (Slot).State :=
        Apply (Tasks (Slot).State, Dispatcher.Begin_Retirement);
      Tasks (Slot).Resume_Full := False;
      Current_Tasks (Core) := No_Task;
   end Begin_Retirement_Locked;

   procedure Finish_Retirement_Locked (Reference : Task_Ref) is
      Slot : constant Task_Slot := Slot_Of (Reference);
   begin
      if Slot = 0
        or else not Known_Locked (Reference)
        or else Tasks (Slot).Wait.Phase /= Waits.Idle
      then
         Stop;
      end if;
      for Core in Core_Number loop
         if Current_Tasks (Core) = Reference
           or else Scheduler.Contains (Ready_Queues (Core), Reference)
           or else Timers.Contains_Task (Timer_Tables (Core), Reference)
         then
            Stop;
         end if;
      end loop;
      Tasks (Slot).State :=
        Apply (Tasks (Slot).State, Dispatcher.Finish_Retirement);
   end Finish_Retirement_Locked;

   procedure Release_Terminated_Locked (Reference : Task_Ref) is
      Slot : constant Task_Slot := Slot_Of (Reference);
   begin
      if not Known_Locked (Reference)
        or else Tasks (Slot).State /= Dispatcher.Terminated
        or else Tasks (Slot).Wait.Phase /= Waits.Idle
        or else not Canary_Is_Valid (Slot)
      then
         Stop;
      end if;
      for Core in Core_Number loop
         if Current_Tasks (Core) = Reference
           or else Scheduler.Contains (Ready_Queues (Core), Reference)
           or else Timers.Contains_Task (Timer_Tables (Core), Reference)
         then
            Stop;
         end if;
      end loop;
      Tasks (Slot) := (others => <>);
   end Release_Terminated_Locked;

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
        and then State_Locked (Reference) not in
          Dispatcher.Retiring | Dispatcher.Terminated;
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

   function Stack_Is_Valid_Locked
     (Core      : Core_Number;
      Reference : Task_Ref;
      Probe     : System.Address;
      Allow_Top : Boolean := False) return Boolean
   is
      Slot : constant Task_Slot := Slot_Of (Reference);
      Base : System.Address;
   begin
      if not Known_Locked (Reference)
        or else Tasks (Slot).Assigned_Core /= Core
      then
         return False;
      elsif Slot = 0 then
         return Core = 0
           and then Architecture.Validate_Environment_Stack
             (System.Address (Core), Probe) /= 0;
      end if;
      Base := Task_Stacks (Slot) (Task_Stack'First)'Address;
      return Base <= System.Address'Last - System.Address (Task_Stack_Size)
        and then Probe >= Base + System.Address (Stack_Canary_Length)
        and then
          (Probe < Base + System.Address (Task_Stack_Size)
           or else
             (Allow_Top
              and then Probe = Base + System.Address (Task_Stack_Size)))
        and then Canary_Is_Valid (Slot);
   end Stack_Is_Valid_Locked;

   function Validate_Current_Stack
     (Core  : Core_Number;
      Probe : System.Address) return Boolean
   is
      Reference : Task_Ref;
   begin
      Enter_Kernel;
      Reference := Current_Tasks (Core);
      if Reference = No_Task then
         Leave_Kernel;
         return False;
      end if;
      declare
         Result : constant Boolean :=
           Stack_Is_Valid_Locked (Core, Reference, Probe);
      begin
         Leave_Kernel;
         return Result;
      end;
   end Validate_Current_Stack;

   function Interrupt_Dispatch
     (Frame_Address : System.Address;
      Core_Address  : System.Address) return System.Address
   is
      Frame     : Architecture.Interrupt_Frame
        with Import, Address => Frame_Address;
      Dense     : Core_Number;
      Reference : Task_Ref;
      Slot      : Task_Slot;
      Choice    : Scheduler.Selection;
      Cause     : Preemption.Preemption_Cause;
      Now       : Preemption.Clock.Tick;
      Result    : System.Address := System.Null_Address;
   begin
      if Frame_Address = System.Null_Address
        or else Core_Address >= System.Address (Configured)
        or else not Policy_Configured
      then
         Stop;
      end if;
      Dense := Core_Number (Core_Address);
      if not Try_Enter_Kernel then
         --  Interrupt ingress must never wait behind a remote runtime or
         --  diagnostic critical section.  The request epoch remains pending;
         --  a short local one-shot guarantees another drain opportunity even
         --  when the original timer interrupt disabled its comparator.
         Architecture.Retry_Interrupt;
         return Result;
      end if;
      --  Acknowledge only the epoch this interrupt path is about to process.
      --  A concurrent later request remains visible to the atomic-idle gate.
      Prepare_Idle;
      Drain_Timers_Locked (Dense);
      Reference := Current_Tasks (Dense);
      if Reference = No_Task then
         Program_Next_Timer_Locked (Dense);
         Leave_Kernel;
         return Result;
      end if;
      Slot := Slot_Of (Reference);
      if not Known_Locked (Reference)
        or else Tasks (Slot).State /= Dispatcher.Running
        or else Tasks (Slot).Domain /= Core_Domains (Dense)
        or else not Stack_Is_Valid_Locked
          (Dense, Reference, Architecture.Interrupted_Stack (Frame),
           Allow_Top => True)
      then
         Leave_Kernel;
         Stop;
      end if;

      Now := Preemption.Clock.Tick (Read_Clock);
      if Tasks (Slot).Budget.Armed then
         if Now < Tasks (Slot).Budget.Last_Accounted then
            Leave_Kernel;
            Stop;
         end if;
         Tasks (Slot).Budget := Preemption.Account (Tasks (Slot).Budget, Now);
      end if;
      Choice := Scheduler.Select_Next (Ready_Queues (Dense));
      Cause := Preemption.Decide
        (Policy_For (Dense),
         Tasks (Slot).Priority.Active,
         Choice.Found,
         (if Choice.Found
          then Choice.Item.Priority
          else Dispatcher.Priority'First),
         Tasks (Slot).Budget,
         Tasks (Slot).Priority.Active > Tasks (Slot).Priority.Base,
         Tasks (Slot).Priority.Depth > 0);

      if Cause /= Preemption.Continue_Running then
         Architecture.Capture_Full_Context
           (Full_Contexts (Slot), Frame);
         Tasks (Slot).State :=
           Apply (Tasks (Slot).State, Dispatcher.Yield);
         Current_Tasks (Dense) := No_Task;
         Enqueue_Locked
           (Reference, Dense,
            (if Cause = Preemption.Higher_Priority_Ready
             then Scheduler.At_Head
             else Scheduler.At_Tail));
         Tasks (Slot).Resume_Full := True;
         Result := Dispatcher_Contexts (Dense)'Address;
      end if;
      Program_Next_Timer_Locked (Dense);
      Leave_Kernel;
      return Result;
   end Interrupt_Dispatch;

   function Validate_Dispatcher_Stack
     (Core  : Core_Number;
      Probe : System.Address) return Boolean
   is
      Base : constant System.Address :=
        Dispatcher_Stacks (Core) (Dispatcher_Stack'First)'Address;
   begin
      return Base <= System.Address'Last - System.Address (Dispatcher_Stack_Size)
        and then Probe >= Base
        and then Probe < Base + System.Address (Dispatcher_Stack_Size);
   end Validate_Dispatcher_Stack;

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
      Retiring  : Boolean;
      Use_Full  : Boolean;
      Now       : Preemption.Clock.Tick;
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
         --  Record the last request epoch that this dispatcher cycle will
         --  process before draining timers and examining the ready queue.
         --  Any interrupt or remote publication after this snapshot leaves
         --  Requested /= Observed, so Idle must not sleep.
         Prepare_Idle;
         Drain_Timers_Locked (Dense);
         Choice := Scheduler.Select_Next (Ready_Queues (Dense));
         if not Choice.Found then
            Program_Next_Timer_Locked (Dense);
            Leave_Kernel;
            Idle;
         else
            Ready_Queues (Dense) := Choice.Remainder;
            Reference := Choice.Item.Reference;
            Slot := Slot_Of (Reference);
            if not Known_Locked (Reference)
              or else Current_Tasks (Dense) /= No_Task
              or else Tasks (Slot).Assigned_Core /= Dense
              or else Tasks (Slot).Domain /= Core_Domains (Dense)
            then
               Leave_Kernel;
               Stop;
            end if;
            --  Keep the dispatcher-to-task ownership handoff indivisible to
            --  interrupt-time scheduling.  Switch_To_Task unmasks only after
            --  the incoming task stack and preserved context are installed;
            --  a full restore obtains its interrupt state from the frame.
            Disable_Dispatch;
            Tasks (Slot).State :=
              Apply (Tasks (Slot).State, Dispatcher.Dispatch);
            Current_Tasks (Dense) := Reference;
            Now := Preemption.Clock.Tick (Read_Clock);
            if Policy_For (Dense) =
              Preemption.Round_Robin_Within_Priorities
            then
               if Tasks (Slot).Budget.Armed
                 and then Tasks (Slot).Budget.Remaining > 0
               then
                  Tasks (Slot).Budget :=
                    Preemption.Resume_Retained (Tasks (Slot).Budget, Now);
               else
                  Tasks (Slot).Budget :=
                    Preemption.Start_Budget
                      (Policy_For (Dense), Now, Quantum_For (Dense));
               end if;
            else
               Tasks (Slot).Budget := Preemption.Empty_Budget;
            end if;
            Use_Full := Tasks (Slot).Resume_Full;
            --  A saved interrupt frame is a one-shot continuation.  Consume
            --  the ownership bit while interrupts are still masked; a later
            --  interrupt-time preemption will publish a fresh full frame and
            --  set it again.
            if Use_Full then
               Tasks (Slot).Resume_Full := False;
            end if;
            Program_Next_Timer_Locked (Dense);
            Leave_Kernel;
            if Use_Full then
               Architecture.Switch_To_Full
                 (Dispatcher_Contexts (Dense)'Access,
                  Full_Contexts (Slot)'Access);
            else
               Architecture.Switch_To_Task
                 (Dispatcher_Contexts (Dense)'Access,
                  Task_Contexts (Slot)'Access);
            end if;
            if Slot /= 0 and then not Canary_Is_Valid (Slot) then
               Stop;
            end if;
            Enter_Kernel;
            Retiring := Slot /= 0
              and then Known_Locked (Reference)
              and then Tasks (Slot).State = Dispatcher.Retiring;
            Leave_Kernel;
            if Retiring then
               if On_Retirement = null then
                  Stop;
               end if;
               On_Retirement.all
                 (System.Address (Dense), System.Address (Slot));
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
end Flyology_Freestanding.Kernel;
