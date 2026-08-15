package Ada.Real_Time is
   type Time is private;
   type Time_Span is private;
   Time_Span_Zero : constant Time_Span;
private
   type Time is new Long_Long_Integer;
   type Time_Span is new Duration;
   Time_Span_Zero : constant Time_Span := 0.0;
end Ada.Real_Time;
