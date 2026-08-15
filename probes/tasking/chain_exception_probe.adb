--  SPDX-License-Identifier: MIT OR Apache-2.0

procedure Chain_Exception_Probe is
   task Worker;
   task body Worker is
   begin
      null;
   end Worker;

   function Fail return Integer is
   begin
      raise Program_Error;
      return 0;
   end Fail;

   Value : constant Integer := Fail;
   pragma Unreferenced (Value);
begin
   null;
end Chain_Exception_Probe;
