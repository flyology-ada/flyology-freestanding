--  SPDX-License-Identifier: MIT OR Apache-2.0

with Ada.Unchecked_Deallocation;

procedure Abort_Dynamic_Probe is
   task type Worker;
   task body Worker is
   begin
      loop
         delay 0.001;
      end loop;
   end Worker;

   type Worker_Access is access Worker;
   procedure Free is new Ada.Unchecked_Deallocation (Worker, Worker_Access);
   Item : Worker_Access := new Worker;
begin
   abort Item.all;
   Free (Item);
end Abort_Dynamic_Probe;
