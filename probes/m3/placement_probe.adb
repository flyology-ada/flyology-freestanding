--  SPDX-License-Identifier: MIT OR Apache-2.0

with System.Multiprocessors;

procedure Placement_Probe is
   task type Worker (CPU_Number : System.Multiprocessors.CPU_Range)
     with CPU => CPU_Number;

   task body Worker is
   begin
      null;
   end Worker;

   First  : Worker (1);
   Second : Worker (2);
begin
   null;
end Placement_Probe;
