--  SPDX-License-Identifier: MIT OR Apache-2.0

with Flyology_Freestanding.Conformance.Preemption;
with Flyology_Freestanding.Conformance.Tasking;
with Flyology_Freestanding.Binder_Support;

package body Flyology_Freestanding.Conformance_Profile is
   procedure Run is
   begin
      Flyology_Freestanding.Conformance.Tasking.Run;
      if Flyology_Freestanding.Binder_Support.Task_Dispatching_Policy /= ' ' then
         Flyology_Freestanding.Conformance.Preemption.Run
           (Flyology_Freestanding.Binder_Support.Task_Dispatching_Policy);
      end if;
   end Run;
end Flyology_Freestanding.Conformance_Profile;
