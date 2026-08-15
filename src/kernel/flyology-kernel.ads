--  SPDX-License-Identifier: MIT OR Apache-2.0

with Flyology.Dispatcher_Model;
with Flyology.Ceiling_Model;
with Flyology.Clock_Model;
with Flyology.Preemption_Model;
with Flyology.Task_Primitives_Contract;
with Flyology.Timer_Model;
with Flyology.Wait_Arbitration_Model;
with System;

package Flyology.Kernel is
   package Dispatcher renames Flyology.Dispatcher_Model;
   use type Dispatcher.Task_Slot;

   Max_Cores : constant := 4;
   Max_Domains : constant := 4;
   Max_Tasks : constant := 16;

   subtype Core_Number is Natural range 0 .. Max_Cores - 1;
   subtype Domain_Number is Natural range 0 .. Max_Domains - 1;
   System_Domain : constant Domain_Number := Domain_Number'First;
   type Core_Set is array (Core_Number) of Boolean;
   subtype Task_Slot is Dispatcher.Task_Slot range 0 .. Max_Tasks - 1;
   subtype Task_Ref is Dispatcher.Task_Ref;
   subtype Task_State is Dispatcher.Task_State;
   subtype Wait_Token is Flyology.Task_Primitives_Contract.Wait_Token;
   subtype Wait_Kind is Flyology.Wait_Arbitration_Model.Wait_Kind;
   subtype Wait_Resolution is Flyology.Wait_Arbitration_Model.Resolution;
   subtype Wait_Resolve_Status is
     Flyology.Wait_Arbitration_Model.Resolve_Status;
   subtype Tick is Flyology.Timer_Model.Tick;
   subtype Frequency is Flyology.Clock_Model.Frequency;
   subtype Timer_Cancel_Status is Flyology.Timer_Model.Cancel_Status;
   subtype Dispatching_Policy is Flyology.Preemption_Model.Policy_Kind;
   subtype Binder_Time_Slice is Flyology.Preemption_Model.Binder_Time_Slice;
   FIFO_Within_Priorities : constant Dispatching_Policy :=
     Flyology.Preemption_Model.FIFO_Within_Priorities;
   Round_Robin_Within_Priorities : constant Dispatching_Policy :=
     Flyology.Preemption_Model.Round_Robin_Within_Priorities;
   Cancelled : constant Timer_Cancel_Status := Flyology.Timer_Model.Cancelled;

   No_Task : Task_Ref renames Dispatcher.No_Task;

   type Retirement_Hook is access procedure
     (Core : System.Address;
      Slot : System.Address);

   procedure Initialize (CPU_Count : Positive);
   procedure Configure_Dispatching
     (Policy : Dispatching_Policy;
      Slice  : Binder_Time_Slice);
   procedure Try_Create_Domain_Locked
     (Cores  : Core_Set;
      Policy : Dispatching_Policy;
      Slice  : Binder_Time_Slice;
      Domain : out Domain_Number;
      Created : out Boolean);
   function Domain_Is_Used_Locked (Domain : Domain_Number) return Boolean;
   function Domain_Cores_Locked (Domain : Domain_Number) return Core_Set;
   function Domain_Of_Core_Locked (Core : Core_Number) return Domain_Number;
   function Domain_Of_Task_Locked (Reference : Task_Ref) return Domain_Number;
   procedure Install_Retirement_Hook (Hook : Retirement_Hook);
   function CPU_Count return Positive;

   procedure Register_Environment_Locked (Reference : Task_Ref);
   procedure Register_Dormant_Locked (Reference : Task_Ref);
   function Can_Cancel_Dormant_Locked (Reference : Task_Ref) return Boolean;
   procedure Cancel_Dormant_Locked (Reference : Task_Ref);

   function Known_Locked (Reference : Task_Ref) return Boolean;
   function State_Locked (Reference : Task_Ref) return Task_State;
   function Current_Locked (Core : Core_Number) return Task_Ref;
   function Assigned_Core_Locked (Reference : Task_Ref) return Core_Number;
   function Queue_Space_Locked (Core : Core_Number) return Natural;

   procedure Activate_Locked
     (Reference : Task_Ref;
      Domain    : Domain_Number;
      Core      : Core_Number;
      Priority  : Dispatcher.Priority);

   procedure Arm_Wait_Locked
     (Reference : Task_Ref;
      Kind      : Wait_Kind;
      Token     : out Wait_Token);

   procedure Resolve_Exact_Locked
     (Token   : Wait_Token;
      Outcome : Wait_Resolution;
      Status  : out Wait_Resolve_Status;
      Core    : out Core_Number);

   function Wait_Is_Pending_Locked (Token : Wait_Token) return Boolean;

   procedure Active_Wait_Locked
     (Reference : Task_Ref;
      Token     : out Wait_Token;
      Kind      : out Wait_Kind);

   procedure Block_Current_And_Release
     (Core    : Core_Number;
      Token   : Wait_Token;
      Outcome : out Wait_Resolution);

   procedure Change_Base_Priority_Locked
     (Reference : Task_Ref;
      Priority  : Dispatcher.Priority);

   function Base_Priority_Locked
     (Reference : Task_Ref) return Dispatcher.Priority;

   function Active_Priority_Locked
     (Reference : Task_Ref) return Dispatcher.Priority;

   function Enter_Protected_Locked
     (Reference : Task_Ref;
      Ceiling   : Dispatcher.Priority) return Boolean;

   procedure Leave_Protected_Locked (Reference : Task_Ref);

   function Read_Clock return Tick;
   function Clock_Frequency return Frequency;

   procedure Register_Deadline_Locked
     (Token    : Wait_Token;
      Deadline : Tick);

   procedure Cancel_Deadline_Locked
     (Token  : Wait_Token;
      Status : out Timer_Cancel_Status);

   procedure Terminate_Current_Locked
     (Core      : Core_Number;
      Reference : Task_Ref);

   procedure Begin_Retirement_Locked
     (Core      : Core_Number;
      Reference : Task_Ref);

   procedure Finish_Retirement_Locked (Reference : Task_Ref);

   procedure Release_Terminated_Locked (Reference : Task_Ref);

   function Current (Core : Core_Number) return Task_Ref;
   function Is_Callable (Reference : Task_Ref) return Boolean;
   function Is_Terminated (Reference : Task_Ref) return Boolean;
   function Validate_Current_Stack
     (Core  : Core_Number;
      Probe : System.Address) return Boolean;

   function Validate_Dispatcher_Stack
     (Core  : Core_Number;
      Probe : System.Address) return Boolean;

   procedure Prepare_Environment (Core : System.Address)
   with Export, Convention => C,
        External_Name => "flyology_m3_prepare_environment";

   procedure Prepare_AP (Core : System.Address)
   with Export, Convention => C,
        External_Name => "flyology_m3_prepare_ap";

   procedure Dispatcher_Start (Core : System.Address)
   with Export, Convention => C,
        External_Name => "flyology_dispatcher_start";

   procedure Switch_To_Dispatcher
     (Core      : Core_Number;
      Reference : Task_Ref);

   procedure Environment_Complete
   with Export, Convention => C,
        External_Name => "flyology_m3_environment_complete";
end Flyology.Kernel;
