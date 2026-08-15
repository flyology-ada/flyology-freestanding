--  SPDX-License-Identifier: MIT OR Apache-2.0

procedure Conditional_Rendezvous_Probe is
   task Server is
      entry Ping;
   end Server;

   task body Server is
   begin
      accept Ping;
   end Server;

   Accepted : Boolean := False;
begin
   select
      Server.Ping;
      Accepted := True;
   else
      null;
   end select;
   if not Accepted then
      Server.Ping;
   end if;
end Conditional_Rendezvous_Probe;
