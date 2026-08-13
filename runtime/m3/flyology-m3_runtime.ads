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
      Master         : Integer;
      Created_Task   : out Task_Id);

   procedure Activate_Tasks (Members : Task_List);
   procedure Complete_Activation;
   procedure Complete_Task;

   procedure Abort_Defer;
   procedure Abort_Undefer;
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
   procedure Protected_Enter (Ceiling : Integer);
   procedure Protected_Leave;

   procedure Core_Initialize (CPU_Count : System.Address)
   with Export, Convention => C,
        External_Name => "flyology_m3_core_initialize";

   procedure Task_Start (Task_Address : System.Address)
   with Export, Convention => C,
        External_Name => "flyology_task_start";

end Flyology.M3_Runtime;
