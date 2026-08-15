--  SPDX-License-Identifier: MIT OR Apache-2.0

with System;

package body Flyology.Conformance.Observations is
   procedure Raw_Parallel_Barrier (Phase : System.Address)
   with Import, Convention => C,
        External_Name => "flyology_test_parallel_barrier";

   function Raw_Queued_Call_Count return System.Address
   with Import, Convention => C,
        External_Name => "flyology_test_queued_call_count";

   procedure Parallel_Barrier (Phase : Positive) is
   begin
      Raw_Parallel_Barrier (System.Address (Phase));
   end Parallel_Barrier;

   function Queued_Call_Count return Natural is
     (Natural (Raw_Queued_Call_Count));
end Flyology.Conformance.Observations;
