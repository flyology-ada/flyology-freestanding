--  SPDX-License-Identifier: MIT OR Apache-2.0

package body Flyology.Clock_Model
  with SPARK_Mode => On
is
   function To_Ticks_Ceiling
     (Interval : Nanoseconds;
      Rate     : Frequency) return Tick
   is
      Seconds   : constant Nanoseconds := Interval / Nanoseconds_Per_Second;
      Remainder : constant Nanoseconds := Interval mod Nanoseconds_Per_Second;
      Whole     : constant Nanoseconds := Seconds * Nanoseconds (Rate);
      Fraction  : Nanoseconds := 0;
   begin
      if Remainder /= 0 then
         Fraction :=
           (Remainder * Nanoseconds (Rate) - 1) /
             Nanoseconds_Per_Second + 1;
      end if;
      return Tick (Whole + Fraction);
   end To_Ticks_Ceiling;

   function Add_Delay
     (Now       : Tick;
      Increment : Tick) return Tick
   is
   begin
      return Now + Increment;
   end Add_Delay;
end Flyology.Clock_Model;
