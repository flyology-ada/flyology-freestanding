--  SPDX-License-Identifier: MIT OR Apache-2.0

procedure Protected_Probe is
   protected Gate is
      procedure Open;
      entry Wait;
      function Is_Open return Boolean;
   private
      Opened : Boolean := False;
   end Gate;

   protected body Gate is
      procedure Open is
      begin
         Opened := True;
      end Open;

      entry Wait when Opened is
      begin
         null;
      end Wait;

      function Is_Open return Boolean is (Opened);
   end Gate;
begin
   Gate.Open;
   Gate.Wait;
   if not Gate.Is_Open then
      raise Program_Error;
   end if;
end Protected_Probe;
