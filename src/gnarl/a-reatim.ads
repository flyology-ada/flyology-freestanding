--  SPDX-License-Identifier: MIT OR Apache-2.0

package Ada.Real_Time is
   Time_Error : exception renames Program_Error;
   type Time is private;
   type Time_Span is private;
   function Clock return Time;
   function "+" (Left : Time; Right : Time_Span) return Time;
   function "<" (Left, Right : Time) return Boolean;
   function Milliseconds (MS : Integer) return Time_Span;
   Time_Span_Zero : constant Time_Span;
private
   type Time is new Long_Long_Integer;
   type Time_Span is new Duration;
   Time_Span_Zero : constant Time_Span := 0.0;
end Ada.Real_Time;
