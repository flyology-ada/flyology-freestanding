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

   procedure Core_Initialize (CPU_Count : System.Address)
   with Export, Convention => C,
        External_Name => "flyology_m3_core_initialize";

   procedure Prepare_Environment (Core : System.Address)
   with Export, Convention => C,
        External_Name => "flyology_m3_prepare_environment";

   procedure Prepare_AP (Core : System.Address)
   with Export, Convention => C,
        External_Name => "flyology_m3_prepare_ap";

   procedure Dispatcher_Start (Core : System.Address)
   with Export, Convention => C,
        External_Name => "flyology_dispatcher_start";

   procedure Task_Start (Task_Address : System.Address)
   with Export, Convention => C,
        External_Name => "flyology_task_start";

   procedure Environment_Complete
   with Export, Convention => C,
        External_Name => "flyology_m3_environment_complete";
end Flyology.M3_Runtime;
