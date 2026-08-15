--  SPDX-License-Identifier: MIT OR Apache-2.0

with Flyology.Elaboration_Probe;

procedure Flyology_Boot_Checkpoint is
begin
   if not Flyology.Elaboration_Probe.Ready then
      loop
         null;
      end loop;
   end if;
end Flyology_Boot_Checkpoint;
