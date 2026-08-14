--  SPDX-License-Identifier: MIT OR Apache-2.0

with Ada.Text_IO;

procedure Abort_Exception_Protected_Black_Box is
   Entered        : Boolean := False with Atomic;
   Release_Action : Boolean := False with Atomic;
   Caller_Started : Boolean := False with Atomic;
   Caller_Caught  : Boolean := False with Atomic;
   Caller_After   : Boolean := False with Atomic;

   protected Gate is
      procedure Open;
      entry Call;
   private
      Opened : Boolean := False;
   end Gate;

   protected body Gate is
      procedure Open is
      begin
         Opened := True;
      end Open;

      entry Call when Opened is
      begin
         Entered := True;
         while not Release_Action loop
            null;
         end loop;
         raise Constraint_Error;
      end Call;
   end Gate;

   task Caller;
   task Aborter;

   task body Caller is
   begin
      Caller_Started := True;
      begin
         Gate.Call;
      exception
         when Constraint_Error =>
            Caller_Caught := True;
            delay 0.010;
      end;
      Caller_After := True;
   end Caller;

   task body Aborter is
   begin
      while not Entered loop
         delay 0.001;
      end loop;
      abort Caller;
      Release_Action := True;
   end Aborter;
begin
   while not Caller_Started loop
      delay 0.001;
   end loop;
   Gate.Open;

   if Caller_Caught or else Caller_After then
      raise Program_Error;
   end if;
   Ada.Text_IO.Put_Line
     ("FLYOLOGY:M4:ABORT_EXCEPTION_BLACK_BOX:PASS:PROTECTED");
end Abort_Exception_Protected_Black_Box;
