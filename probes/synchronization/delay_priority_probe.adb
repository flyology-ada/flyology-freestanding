--  SPDX-License-Identifier: MIT OR Apache-2.0

with Ada.Dynamic_Priorities;
with Ada.Real_Time;
with System;

procedure Delay_Priority_Probe is
   use type Ada.Real_Time.Time;
   Worker_Priority : constant System.Any_Priority := 7;

   task Worker with Priority => Worker_Priority;
   task body Worker is
   begin
      delay 0.001;
      delay until Ada.Real_Time.Clock + Ada.Real_Time.Milliseconds (1);
      Ada.Dynamic_Priorities.Set_Priority (6);
      if Ada.Dynamic_Priorities.Get_Priority /= 6 then
         raise Program_Error;
      end if;
   end Worker;
begin
   null;
end Delay_Priority_Probe;
