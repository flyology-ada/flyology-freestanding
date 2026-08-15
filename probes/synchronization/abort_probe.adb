--  SPDX-License-Identifier: MIT OR Apache-2.0

procedure Abort_Probe is
   task First;
   task Second;

   task body First is
   begin
      delay 1.0;
   end First;

   task body Second is
   begin
      delay 1.0;
   end Second;
begin
   abort First, Second;
end Abort_Probe;
