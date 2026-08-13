--  SPDX-License-Identifier: MIT OR Apache-2.0

procedure Abort_Probe is
   task Worker;

   task body Worker is
   begin
      delay 1.0;
   end Worker;
begin
   abort Worker;
end Abort_Probe;
