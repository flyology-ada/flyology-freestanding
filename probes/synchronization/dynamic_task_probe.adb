--  SPDX-License-Identifier: MIT OR Apache-2.0

procedure Dynamic_Task_Probe is
   task type Worker;

   task body Worker is
   begin
      null;
   end Worker;

   type Worker_Access is access Worker;
   Item : Worker_Access := new Worker;
begin
   if Item = null then
      raise Program_Error;
   end if;
end Dynamic_Task_Probe;
