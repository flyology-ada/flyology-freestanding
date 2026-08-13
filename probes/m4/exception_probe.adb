--  SPDX-License-Identifier: MIT OR Apache-2.0

procedure Exception_Probe is
   Caught : Boolean := False;

   procedure Raise_And_Catch is
   begin
      raise Program_Error;
   exception
      when Program_Error =>
         Caught := True;
   end Raise_And_Catch;
begin
   Raise_And_Catch;
   if not Caught then
      raise Program_Error;
   end if;
end Exception_Probe;
