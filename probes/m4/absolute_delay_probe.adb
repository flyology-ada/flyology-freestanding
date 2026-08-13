--  SPDX-License-Identifier: MIT OR Apache-2.0

with Ada.Real_Time;

procedure Absolute_Delay_Probe is
   use type Ada.Real_Time.Time;
   Deadline : constant Ada.Real_Time.Time :=
     Ada.Real_Time.Clock + Ada.Real_Time.Milliseconds (1);
begin
   delay until Deadline;
   if Ada.Real_Time.Clock < Deadline then
      raise Program_Error;
   end if;
end Absolute_Delay_Probe;
