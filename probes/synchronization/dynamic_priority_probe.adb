--  SPDX-License-Identifier: MIT OR Apache-2.0

with Ada.Dynamic_Priorities;
with Ada.Task_Identification;
with System;

procedure Dynamic_Priority_Probe is
   use type System.Any_Priority;
   Self : constant Ada.Task_Identification.Task_Id :=
     Ada.Task_Identification.Current_Task;
begin
   Ada.Dynamic_Priorities.Set_Priority (7, Self);
   if Ada.Dynamic_Priorities.Get_Priority (Self) /=
     System.Any_Priority (7)
   then
      raise Program_Error;
   end if;
end Dynamic_Priority_Probe;
