--  SPDX-License-Identifier: MIT OR Apache-2.0

package body Flyology.Allocator_Model
with SPARK_Mode
is
   function Reserve
     (Cursor : Byte_Offset;
      Count  : Byte_Count) return Reservation
   is
      Size : constant Byte_Count := Rounded_Size (Count);
   begin
      if not Can_Reserve (Cursor, Count) then
         return (Accepted => False, Start => Cursor, Size => 0,
                 Next => Cursor);
      end if;
      return
        (Accepted => True,
         Start    => Cursor,
         Size     => Byte_Offset (Size),
         Next     => Byte_Offset (Cursor + Size));
   end Reserve;

   function Find_First_Fit
     (Used   : Occupancy_Map;
      Needed : Model_Unit_Count) return Fit_Result
   is
   begin
      for Candidate in Model_Unit_Index loop
         if Range_Is_Free (Used, Candidate, Needed) then
            return (Accepted => True, Start => Candidate);
         end if;
         pragma Loop_Invariant
           (for all Earlier in Model_Unit_Index range
              Model_Unit_Index'First .. Candidate =>
                not Range_Is_Free (Used, Earlier, Needed));
      end loop;
      return (Accepted => False, Start => Model_Unit_Index'First);
   end Find_First_Fit;

   function Mark_Allocated
     (Used   : Occupancy_Map;
      Start  : Model_Unit_Index;
      Needed : Model_Unit_Count) return Occupancy_Map
   is
      Result : Occupancy_Map := Used;
   begin
      for Offset in Natural range 0 .. Natural (Needed) - 1 loop
         Result (Model_Unit_Index (Natural (Start) + Offset)) := True;
         pragma Loop_Invariant
           (for all Unit in Model_Unit_Index =>
              Result (Unit) =
                (Used (Unit)
                 or else
                   (Unit >= Start
                    and then Unit <=
                      Natural (Start) + Offset)));
      end loop;
      return Result;
   end Mark_Allocated;

   function Release_Range
     (Used   : Occupancy_Map;
      Start  : Model_Unit_Index;
      Length : Model_Unit_Count) return Occupancy_Map
   is
      Result : Occupancy_Map := Used;
   begin
      for Offset in Natural range 0 .. Natural (Length) - 1 loop
         Result (Model_Unit_Index (Natural (Start) + Offset)) := False;
         pragma Loop_Invariant
           (for all Unit in Model_Unit_Index =>
              Result (Unit) =
                (Used (Unit)
                 and then not
                   (Unit >= Start
                    and then Unit <=
                      Natural (Start) + Offset)));
      end loop;
      return Result;
   end Release_Range;
end Flyology.Allocator_Model;
