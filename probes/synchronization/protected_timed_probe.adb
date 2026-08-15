--  SPDX-License-Identifier: MIT OR Apache-2.0

procedure Protected_Timed_Probe is
   protected Gate is
      entry Wait;
   private
      Opened : Boolean := False;
   end Gate;

   protected body Gate is
      entry Wait when Opened is
      begin
         null;
      end Wait;
   end Gate;

   Timed_Out : Boolean := False;
begin
   select
      Gate.Wait;
   or
      delay 0.01;
      Timed_Out := True;
   end select;

   if not Timed_Out then
      raise Program_Error;
   end if;
end Protected_Timed_Probe;
