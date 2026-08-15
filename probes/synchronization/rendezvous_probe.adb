--  SPDX-License-Identifier: MIT OR Apache-2.0

procedure Rendezvous_Probe is
   task Server is
      entry Ping (Value : in out Integer);
      entry Stop;
   end Server;

   task body Server is
   begin
      loop
         select
            accept Ping (Value : in out Integer) do
               Value := Value + 1;
            end Ping;
         or
            accept Stop;
            exit;
         end select;
      end loop;
   end Server;

   Value : Integer := 1;
begin
   Server.Ping (Value);
   Server.Stop;
   if Value /= 2 then
      raise Program_Error;
   end if;
end Rendezvous_Probe;
