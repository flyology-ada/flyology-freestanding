--  SPDX-License-Identifier: MIT OR Apache-2.0

procedure Base_Protected_Probe is
   type Pair is array (Positive range 1 .. 2) of Natural;

   protected Counter with Priority => 8 is
      procedure Increment;
      function Value return Natural;
   private
      Current : Pair := [others => 0];
   end Counter;

   protected body Counter is
      procedure Increment is
      begin
         Current (1) := Current (1) + 1;
         Current (2) := Current (2) + 1;
      end Increment;

      function Value return Natural is (Current (1) + Current (2));
   end Counter;
begin
   Counter.Increment;
   if Counter.Value /= 2 then
      raise Program_Error;
   end if;
end Base_Protected_Probe;
