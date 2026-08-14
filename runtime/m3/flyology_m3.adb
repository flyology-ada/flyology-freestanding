--  SPDX-License-Identifier: MIT OR Apache-2.0

with Flyology.M3_Demo;
with Flyology.M5_Demo;
with Flyology.M5_Configuration;

procedure Flyology_M3 is
begin
   Flyology.M3_Demo.Run;
   if Flyology.M5_Configuration.Enabled then
      Flyology.M5_Demo.Run
        (Flyology.M5_Configuration.Policy_Code);
   end if;
end Flyology_M3;
