--  SPDX-License-Identifier: MIT OR Apache-2.0

with Flyology.Conformance.Preemption;
with Flyology.Conformance.Tasking;
with Flyology.Scheduler_Configuration;

package body Flyology.Conformance_Profile is
   procedure Run is
   begin
      Flyology.Conformance.Tasking.Run;
      if Flyology.Scheduler_Configuration.Enabled then
         Flyology.Conformance.Preemption.Run
           (Flyology.Scheduler_Configuration.Policy_Code);
      end if;
   end Run;
end Flyology.Conformance_Profile;
