--  SPDX-License-Identifier: MIT OR Apache-2.0

with Flyology.Conformance.Preemption;
with Flyology.Conformance.Tasking;
with Flyology.M5_Configuration;
with Flyology.M6_Hook;
with Flyology.M6_Configuration;

procedure Flyology_M3 is
begin
   if Flyology.M6_Configuration.Enabled then
      Flyology.M6_Hook.Run;
   else
      Flyology.Conformance.Tasking.Run;
      if Flyology.M5_Configuration.Enabled then
         Flyology.Conformance.Preemption.Run
           (Flyology.M5_Configuration.Policy_Code);
      end if;
   end if;
end Flyology_M3;
