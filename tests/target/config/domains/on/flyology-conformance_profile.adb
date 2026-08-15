--  SPDX-License-Identifier: MIT OR Apache-2.0

with Flyology.Conformance.Domains;
with Flyology.Conformance.Tasking;
with Flyology.Domain_Configuration;

package body Flyology.Conformance_Profile is
   procedure Run is
   begin
      if Flyology.Domain_Configuration.Enabled then
         Flyology.Conformance.Domains.Run;
      else
         --  This branch is not selected by the domain profile, but retaining
         --  the dependency keeps the common tasking controlled-object
         --  finalization check in every conformance image.
         Flyology.Conformance.Tasking.Run;
      end if;
   end Run;
end Flyology.Conformance_Profile;
