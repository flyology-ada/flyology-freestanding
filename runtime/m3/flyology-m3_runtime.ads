--  SPDX-License-Identifier: MIT OR Apache-2.0

with System;
with System.Tasking;

package Flyology.M3_Runtime is
   subtype Task_Id is System.Tasking.Task_Id;
   type Task_List is array (Positive range <>) of Task_Id;

   procedure Create_Task
     (Body_Procedure : System.Tasking.Task_Procedure_Access;
      Discriminants  : System.Address;
      Elaborated     : System.Tasking.Boolean_Access;
      Priority       : Integer;
      CPU            : Integer;
      Entry_Count    : Natural;
      Master         : Integer;
      Created_Task   : out Task_Id);

   procedure Activate_Tasks (Members : Task_List);
   procedure Complete_Activation;
   procedure Complete_Task;

   procedure Abort_Defer;
   procedure Abort_Undefer;
   procedure Deliver_Pending_Abort;
   procedure Abort_Tasks (Members : Task_List);
   procedure Enter_Master;
   procedure Complete_Master;
   function Current_Master return Integer;

   function Current_Task return Task_Id;
   function Is_Callable (Item : Task_Id) return Boolean;
   function Is_Terminated (Item : Task_Id) return Boolean;
   function Number_Of_CPUs return Natural;
   function Current_Core_Number return Natural;
   function Validate_Current_Stack (Probe : System.Address) return Boolean;
   procedure Demo_Parallel_Barrier (Phase : Positive);
   procedure Delay_For (Interval : Duration);
   procedure Delay_Until (Deadline : Long_Long_Integer);
   procedure Protected_Enter (Ceiling : Integer);
   procedure Protected_Leave;

   procedure Set_Priority (Priority : Integer; Item : Task_Id);
   function Get_Priority (Item : Task_Id) return Integer;

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
   procedure Selective_Wait
     (Alternatives : System.Tasking.Accept_List_Access;
      Mode         : System.Tasking.Select_Mode;
      Parameters   : out System.Address;
      Selected     : out System.Tasking.Select_Index);
   procedure Unsupported_Exceptional_Rendezvous;

   procedure Core_Initialize (CPU_Count : System.Address)
   with Export, Convention => C,
        External_Name => "flyology_m3_core_initialize";

   procedure Task_Start (Task_Address : System.Address)
   with Export, Convention => C,
        External_Name => "flyology_task_start";

end Flyology.M3_Runtime;
