--  SPDX-License-Identifier: MIT OR Apache-2.0

procedure Selective_Wait_Probe is
   task Server is
      entry Ping;
   end Server;

   task body Server is
   begin
      select
         accept Ping;
      or
         terminate;
      end select;
   end Server;
begin
   Server.Ping;
end Selective_Wait_Probe;
