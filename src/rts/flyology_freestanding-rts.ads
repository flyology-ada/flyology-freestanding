--  SPDX-License-Identifier: MIT OR Apache-2.0

with System;
with System.Tasking;

package Flyology_Freestanding.RTS is
   subtype Task_Id is System.Tasking.Task_Id;
   type Task_List is array (Positive range <>) of Task_Id;
   subtype Domain_CPU is Positive range 1 .. 4;
   type Domain_CPU_Set is array (Domain_CPU) of Boolean;
   type Scheduling_Policy is
     (FIFO_Within_Priorities,
      Round_Robin_Within_Priorities);
   subtype Scheduling_Quantum_Microseconds is Natural range 0 .. Integer'Last;

   procedure Create_Task
     (Body_Procedure : System.Tasking.Task_Procedure_Access;
      Discriminants  : System.Address;
      Elaborated     : System.Tasking.Boolean_Access;
      Priority       : Integer;
      CPU            : Integer;
      Domain_Address : System.Address;
      Entry_Count    : Natural;
      Master         : Integer;
      Created_Task   : out Task_Id);

   procedure Activate_Tasks
     (Members : Task_List;
      Failed  : out Boolean);
   procedure Raise_Activation_Failure with No_Return;
   procedure Expunge_Unactivated_Tasks (Members : Task_List);
   procedure Free_Task (Item : Task_Id);
   function Any_Free_Wait_Is_Active return Boolean;
   procedure Complete_Activation;
   procedure Complete_Task;
   procedure Observe_Abort_Cleanup;

   procedure Abort_Defer;
   procedure Abort_Undefer;
   procedure Deliver_Pending_Abort;
   procedure Deliver_Pending_Abort_Locked;
   procedure Deliver_Completion (Exception_Identity : System.Address);
   procedure Abort_Tasks (Members : Task_List);
   procedure Enter_Master;
   procedure Complete_Master;
   function Current_Master return Integer;

   function Current_Task return Task_Id;
   function Is_Callable (Item : Task_Id) return Boolean;
   function Is_Terminated (Item : Task_Id) return Boolean;
   function Number_Of_CPUs return Natural;
   function Current_Core_Number return Natural;
   procedure Register_Domain_Alias
     (Identifier     : Natural;
      Object_Address : System.Address);
   procedure Create_Domain
     (Set            : Domain_CPU_Set;
      Identifier     : out Natural;
      Created        : out Boolean);
   function Domain_CPUs (Identifier : Natural) return Domain_CPU_Set;
   procedure Freeze_Domains;
   function Task_Domain (Item : Task_Id) return Natural;
   function Assigned_CPU (Item : Task_Id) return Natural;
   procedure Set_Global_Scheduling_Policy
     (Policy  : Scheduling_Policy;
      Quantum : Scheduling_Quantum_Microseconds);
   procedure Set_Domain_Scheduling_Policy
     (Set     : Domain_CPU_Set;
      Policy  : Scheduling_Policy;
      Quantum : Scheduling_Quantum_Microseconds);
   procedure Set_CPU_Scheduling_Policy
     (CPU     : Domain_CPU;
      Policy  : Scheduling_Policy;
      Quantum : Scheduling_Quantum_Microseconds);
   procedure Get_CPU_Scheduling_Configuration
     (CPU     : Domain_CPU;
      Policy  : out Scheduling_Policy;
      Quantum : out Scheduling_Quantum_Microseconds);
   function Validate_Current_Stack (Probe : System.Address) return Boolean;
   procedure Delay_For (Interval : Duration);
   procedure Delay_Until (Deadline : Long_Long_Integer);
   procedure Protected_Enter (Ceiling : Integer);
   procedure Protected_Leave;

   procedure Set_Priority (Priority : Integer; Item : Task_Id);
   function Get_Priority (Item : Task_Id) return Integer;
   function Current_Active_Priority return Integer;

   procedure Call_Simple
     (Target      : Task_Id;
      Entry_Index : System.Tasking.Task_Entry_Index;
      Parameters  : System.Address);

   procedure Task_Entry_Call
     (Target      : Task_Id;
      Entry_Index : System.Tasking.Task_Entry_Index;
      Parameters  : System.Address;
      Mode        : System.Tasking.Call_Modes;
      Accepted    : out Boolean);

   procedure Timed_Task_Entry_Call
     (Target      : Task_Id;
      Entry_Index : System.Tasking.Task_Entry_Index;
      Parameters  : System.Address;
      Timeout     : Duration;
      Mode        : Integer;
      Accepted    : out Boolean);

   procedure Accept_Call
     (Entry_Index : System.Tasking.Task_Entry_Index;
      Parameters  : out System.Address);

   procedure Complete_Rendezvous;
   procedure Exceptional_Complete_Rendezvous
     (Occurrence : System.Address);
   procedure Selective_Wait
     (Alternatives : System.Tasking.Accept_List_Access;
      Mode         : System.Tasking.Select_Mode;
      Parameters   : out System.Address;
      Selected     : out System.Tasking.Select_Index);

   procedure Core_Initialize (CPU_Count : System.Address)
   with Export, Convention => C,
        External_Name => "flyology_freestanding_rts_initialize";

   procedure Task_Start (Task_Address : System.Address)
   with Export, Convention => C,
        External_Name => "flyology_freestanding_task_start";

   procedure Finish_Task_Retirement
     (Core_Address : System.Address;
      Slot_Address : System.Address);

end Flyology_Freestanding.RTS;
