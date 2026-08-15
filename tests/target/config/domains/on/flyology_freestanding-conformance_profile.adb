--  SPDX-License-Identifier: MIT OR Apache-2.0

with Flyology_Freestanding.Conformance.Domains;
with Flyology_Freestanding.Conformance.Tasking;
with Flyology_Freestanding.Domain_Configuration;

package body Flyology_Freestanding.Conformance_Profile is
   procedure Run is
   begin
      if Flyology_Freestanding.Domain_Configuration.Enabled then
         Flyology_Freestanding.Conformance.Domains.Run;
      else
         --  This branch is not selected by the domain profile, but retaining
         --  the dependency keeps the common tasking controlled-object
         --  finalization check in every conformance image.
         Flyology_Freestanding.Conformance.Tasking.Run;
      end if;
   end Run;
end Flyology_Freestanding.Conformance_Profile;
