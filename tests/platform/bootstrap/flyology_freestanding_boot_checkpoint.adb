--  SPDX-License-Identifier: MIT OR Apache-2.0

with Flyology_Freestanding.Elaboration_Probe;

procedure Flyology_Freestanding_Boot_Checkpoint is
begin
   if not Flyology_Freestanding.Elaboration_Probe.Ready then
      loop
         null;
      end loop;
   end if;
end Flyology_Freestanding_Boot_Checkpoint;
