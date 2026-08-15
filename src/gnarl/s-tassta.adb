--  SPDX-License-Identifier: MIT OR Apache-2.0

with Flyology_Freestanding.RTS;

package body System.Tasking.Stages is
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
      Created_Task         : out System.Tasking.Task_Id)
   is
      pragma Unreferenced
        (Stack_Size, Secondary_Stack_Size, Task_Info,
         Relative_Deadline, Task_Name);
   begin
      if Chain.Length = System.Tasking.Max_Tasks then
         raise Storage_Error;
      end if;
      Flyology_Freestanding.RTS.Create_Task
        (Body_Procedure, Discriminants, Elaborated, Priority, CPU,
         (if Domain = null then System.Null_Address else Domain.all'Address),
         Natural (Base_CPU), Master, Created_Task);
      Chain.Length := Chain.Length + 1;
      Chain.Members (Chain.Length) := Created_Task;
   end Create_Task;

   procedure Activate_Tasks (Chain : System.Tasking.Activation_Chain_Access) is
   begin
      if Chain = null then
         raise Program_Error;
      end if;
      if Chain.Length > 0 then
         declare
            Members : Flyology_Freestanding.RTS.Task_List (1 .. Chain.Length);
            Failed  : Boolean;
         begin
            for Index in Members'Range loop
               Members (Index) := Chain.Members (Index);
            end loop;
            Flyology_Freestanding.RTS.Activate_Tasks (Members, Failed);
            Chain.Length := 0;
            Flyology_Freestanding.RTS.Abort_Undefer;
            if Failed then
               Flyology_Freestanding.RTS.Raise_Activation_Failure;
            end if;
         end;
      end if;
   end Activate_Tasks;

   procedure Complete_Activation is
   begin
      Flyology_Freestanding.RTS.Complete_Activation;
   end Complete_Activation;

   procedure Complete_Task is
   begin
      Flyology_Freestanding.RTS.Observe_Abort_Cleanup;
      Flyology_Freestanding.RTS.Complete_Task;
   end Complete_Task;

   procedure Expunge_Unactivated_Tasks
     (Chain : in out System.Tasking.Activation_Chain)
   is
   begin
      if Chain.Length > 0 then
         declare
            Members : Flyology_Freestanding.RTS.Task_List (1 .. Chain.Length);
         begin
            for Index in Members'Range loop
               Members (Index) := Chain.Members (Index);
            end loop;
            Flyology_Freestanding.RTS.Expunge_Unactivated_Tasks (Members);
            for Index in Members'Range loop
               Chain.Members (Index) := null;
            end loop;
            Chain.Length := 0;
         end;
      end if;
   end Expunge_Unactivated_Tasks;

   procedure Free_Task (Item : System.Tasking.Task_Id) is
      pragma No_Inline (Free_Task);
   begin
      Flyology_Freestanding.RTS.Free_Task (Item);
   end Free_Task;

   procedure Abort_Tasks (Tasks : System.Tasking.Task_List) is
      Members : Flyology_Freestanding.RTS.Task_List (Tasks'Range);
   begin
      for Index in Tasks'Range loop
         Members (Index) := Tasks (Index);
      end loop;
      Flyology_Freestanding.RTS.Abort_Tasks (Members);
   end Abort_Tasks;
end System.Tasking.Stages;
