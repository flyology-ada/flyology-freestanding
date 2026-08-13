--  SPDX-License-Identifier: MIT OR Apache-2.0

procedure Task_Activation_Probe is
   Auto_Done   : Boolean := False with Volatile;
   Pinned_Done : Boolean := False with Volatile;

   task Auto_Worker;
   task Pinned_Worker with CPU => 1;

   task body Auto_Worker is
   begin
      Auto_Done := True;
   end Auto_Worker;

   task body Pinned_Worker is
   begin
      Pinned_Done := True;
   end Pinned_Worker;
begin
   null;
end Task_Activation_Probe;
