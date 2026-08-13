--  SPDX-License-Identifier: MIT OR Apache-2.0

procedure Protected_Conditional_Probe is
   protected Gate is
      entry Wait;
      function Waiting return Natural;
   private
      Opened : Boolean := False;
   end Gate;

   protected body Gate is
      entry Wait when Opened is
      begin
         null;
      end Wait;

      function Waiting return Natural is (Wait'Count);
   end Gate;

   Rejected : Boolean := False;
begin
   select
      Gate.Wait;
   else
      Rejected := True;
   end select;

   if not Rejected or else Gate.Waiting /= 0 then
      raise Program_Error;
   end if;
end Protected_Conditional_Probe;
