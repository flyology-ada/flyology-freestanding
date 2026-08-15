--  SPDX-License-Identifier: MIT OR Apache-2.0

with Flyology.Kernel;
with Flyology.Clock_Model;

package body Ada.Real_Time is
   package Model renames Flyology.Clock_Model;

   function Clock return Time is
     (Time (Flyology.Kernel.Read_Clock));

   function "+" (Left : Time; Right : Time_Span) return Time is
      Nanoseconds : Long_Long_Integer;
      Increment   : Model.Tick;
      Rate        : constant Model.Frequency :=
        Model.Frequency (Flyology.Kernel.Clock_Frequency);
   begin
      if Right < 0.0
        or else Right > Time_Span
          (Long_Long_Integer'Last / Model.Nanoseconds_Per_Second)
      then
         raise Program_Error;
      end if;
      Nanoseconds := Long_Long_Integer
        (Right * Model.Nanoseconds_Per_Second);
      if not Model.Conversion_Fits
          (Model.Nanoseconds (Nanoseconds), Rate)
      then
         raise Program_Error;
      end if;
      Increment := Model.To_Ticks_Ceiling
        (Model.Nanoseconds (Nanoseconds), Rate);
      if not Model.Deadline_Fits
          (Model.Tick (Left), Increment)
      then
         raise Program_Error;
      end if;
      return Time (Model.Add_Delay (Model.Tick (Left), Increment));
   end "+";

   function "<" (Left, Right : Time) return Boolean is
     (Long_Long_Integer (Left) < Long_Long_Integer (Right));

   function Milliseconds (MS : Integer) return Time_Span is
   begin
      if MS < 0 then
         raise Program_Error;
      end if;
      return Time_Span (MS) / 1_000;
   end Milliseconds;
end Ada.Real_Time;
