--  SPDX-License-Identifier: MIT OR Apache-2.0

package Flyology.Clock_Model
  with Pure,
       SPARK_Mode => On
is
   type Tick is range 0 .. 2 ** 63 - 1;
   type Frequency is range 1 .. 4_000_000_000;
   type Nanoseconds is range 0 .. 2 ** 63 - 1;
   Nanoseconds_Per_Second : constant := 1_000_000_000;

   function Conversion_Fits
     (Interval : Nanoseconds;
      Rate     : Frequency) return Boolean
   is (Interval / Nanoseconds_Per_Second <=
         Nanoseconds (Tick'Last) / Nanoseconds (Rate)
       and then
         (Interval / Nanoseconds_Per_Second) * Nanoseconds (Rate) <=
           Nanoseconds (Tick'Last) -
             (if Interval mod Nanoseconds_Per_Second = 0 then 0
              else
                ((Interval mod Nanoseconds_Per_Second) *
                   Nanoseconds (Rate) - 1) /
                     Nanoseconds_Per_Second + 1));

   function To_Ticks_Ceiling
     (Interval : Nanoseconds;
      Rate     : Frequency) return Tick
   with Pre => Conversion_Fits (Interval, Rate),
        Post =>
          (if Interval = 0 then To_Ticks_Ceiling'Result = 0
           else To_Ticks_Ceiling'Result > 0);

   function Deadline_Fits
     (Now       : Tick;
      Increment : Tick) return Boolean
   is (Increment <= Tick'Last - Now);

   function Add_Delay
     (Now       : Tick;
      Increment : Tick) return Tick
   with Pre  => Deadline_Fits (Now, Increment),
        Post => Add_Delay'Result = Now + Increment
          and then Add_Delay'Result >= Now;
end Flyology.Clock_Model;
