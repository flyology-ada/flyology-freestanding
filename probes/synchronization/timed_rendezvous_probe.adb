--  SPDX-License-Identifier: MIT OR Apache-2.0

procedure Timed_Rendezvous_Probe is
   task Server is
      entry Ping (Value : in out Integer);
   end Server;

   task body Server is
   begin
      delay 0.010;
      accept Ping (Value : in out Integer) do
         Value := Value + 1;
      end Ping;
   end Server;

   Value    : Integer := 1;
   Accepted : Boolean := False;
begin
   select
      Server.Ping (Value);
      Accepted := True;
   or
      delay 0.100;
   end select;
   if not Accepted or else Value /= 2 then
      raise Program_Error;
   end if;
end Timed_Rendezvous_Probe;
