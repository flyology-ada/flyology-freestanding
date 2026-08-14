--  SPDX-License-Identifier: MIT OR Apache-2.0

with Ada.Text_IO;

procedure Abort_Exception_Rendezvous_Black_Box is
   Accepted       : Boolean := False with Atomic;
   Release_Server : Boolean := False with Atomic;
   Caller_Started : Boolean := False with Atomic;
   Caller_Caught  : Boolean := False with Atomic;
   Caller_After   : Boolean := False with Atomic;
   Server_Caught  : Boolean := False with Atomic;

   task Server is
      entry Call;
   end Server;

   task body Server is
   begin
      begin
         accept Call do
            Accepted := True;
            while not Release_Server loop
               delay 0.001;
            end loop;
            raise Constraint_Error;
         end Call;
      exception
         when Constraint_Error =>
            Server_Caught := True;
      end;
   end Server;

   task type Caller_Type;

   task body Caller_Type is
   begin
      Caller_Started := True;
      begin
         Server.Call;
      exception
         when Constraint_Error =>
            Caller_Caught := True;
            delay 0.010;
      end;
      Caller_After := True;
   end Caller_Type;
begin
   declare
      Caller : Caller_Type;
   begin
      while not Caller_Started or else not Accepted loop
         delay 0.001;
      end loop;
      abort Caller;
      Release_Server := True;
   end;

   if not Server_Caught or else Caller_Caught or else Caller_After then
      raise Program_Error;
   end if;
   Ada.Text_IO.Put_Line
     ("FLYOLOGY:M4:ABORT_EXCEPTION_BLACK_BOX:PASS:RENDEZVOUS");
end Abort_Exception_Rendezvous_Black_Box;
