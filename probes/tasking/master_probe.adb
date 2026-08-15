--  SPDX-License-Identifier: MIT OR Apache-2.0

procedure Master_Probe is
   Finished : Boolean := False with Volatile;

   procedure Inner is
      task Dependent;
      task body Dependent is
      begin
         Finished := True;
      end Dependent;
   begin
      null;
   end Inner;
begin
   Inner;
end Master_Probe;
