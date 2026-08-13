--  SPDX-License-Identifier: MIT OR Apache-2.0

with Ada.Real_Time;
with System.Parameters;
with System.Task_Info;

package System.Tasking.Stages is
   procedure Create_Task
     (Priority             : Integer;
      Stack_Size           : System.Parameters.Size_Type;
      Secondary_Stack_Size : System.Parameters.Size_Type;
      Task_Info            : System.Task_Info.Task_Info_Type;
      CPU                  : Integer;
      Relative_Deadline    : Ada.Real_Time.Time_Span;
      Domain               : System.Tasking.Dispatching_Domain_Access;
      Base_CPU             : Integer;
      Master               : Integer;
      Body_Procedure       : System.Tasking.Task_Procedure_Access;
      Discriminants        : System.Address;
      Elaborated           : System.Tasking.Boolean_Access;
      Chain                : in out System.Tasking.Activation_Chain;
      Task_Name            : String;
      Created_Task         : out System.Tasking.Task_Id);

   procedure Activate_Tasks (Chain : System.Tasking.Activation_Chain_Access);
   procedure Complete_Activation;
   procedure Complete_Task;
   procedure Expunge_Unactivated_Tasks
     (Chain : in out System.Tasking.Activation_Chain);
   procedure Abort_Tasks (Tasks : System.Tasking.Task_List);
end System.Tasking.Stages;
