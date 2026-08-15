--  SPDX-License-Identifier: MIT OR Apache-2.0

procedure Simple_Rendezvous_Probe is
   task Server is
      entry Ping (Value : in out Integer);
   end Server;

   task body Server is
   begin
      accept Ping (Value : in out Integer) do
         Value := Value + 1;
      end Ping;
   end Server;

   Value : Integer := 1;
begin
   Server.Ping (Value);
   if Value /= 2 then
      raise Program_Error;
   end if;
end Simple_Rendezvous_Probe;
