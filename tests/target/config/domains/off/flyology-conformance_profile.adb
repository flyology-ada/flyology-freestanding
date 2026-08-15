--  SPDX-License-Identifier: MIT OR Apache-2.0

with Flyology.Conformance.Preemption;
with Flyology.Conformance.Tasking;
with Flyology.Binder_Support;

package body Flyology.Conformance_Profile is
   procedure Run is
   begin
      Flyology.Conformance.Tasking.Run;
      if Flyology.Binder_Support.Task_Dispatching_Policy /= ' ' then
         Flyology.Conformance.Preemption.Run
           (Flyology.Binder_Support.Task_Dispatching_Policy);
      end if;
   end Run;
end Flyology.Conformance_Profile;
