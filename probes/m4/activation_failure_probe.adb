--  SPDX-License-Identifier: MIT OR Apache-2.0

procedure Activation_Failure_Probe is
   function Fail return Integer is
   begin
      raise Program_Error;
      return 0;
   end Fail;

   task type Worker;

   task body Worker is
      Value : constant Integer := Fail;
      pragma Unreferenced (Value);
   begin
      null;
   end Worker;
begin
   declare
      Item : Worker;
      pragma Unreferenced (Item);
   begin
      null;
   end;
end Activation_Failure_Probe;
