--  SPDX-License-Identifier: MIT OR Apache-2.0

with Ada.Task_Identification;

procedure Identity_Probe is
   package Ids renames Ada.Task_Identification;
   use type Ids.Task_Id;
   Seen : Ids.Task_Id := Ids.Null_Task_Id;

   task Worker;
   task body Worker is
   begin
      Seen := Ids.Current_Task;
   end Worker;
begin
   if Worker'Identity = Seen
     and then Ids.Is_Callable (Seen)
     and then not Ids.Is_Terminated (Seen)
   then
      null;
   end if;
end Identity_Probe;
