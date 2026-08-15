--  SPDX-License-Identifier: MIT OR Apache-2.0

package Flyology_Freestanding.Allocator_Model
with SPARK_Mode
is
   Alignment : constant := 16;
   Capacity  : constant := 65_536;

   type Byte_Count is mod 2 ** 64;
   subtype Byte_Offset is Byte_Count range 0 .. Capacity;

   type Reservation is record
      Accepted : Boolean := False;
      Start    : Byte_Offset := 0;
      Size     : Byte_Offset := 0;
      Next     : Byte_Offset := 0;
   end record;

   function Rounded_Size (Count : Byte_Count) return Byte_Count
   is (if Count = 0 then Alignment
       elsif Count > Capacity then 0
       else ((Count - 1) / Alignment + 1) * Alignment)
   with Post =>
     (if Rounded_Size'Result = 0
      then Count > Capacity
      else Rounded_Size'Result >= Count
        and then Rounded_Size'Result mod Alignment = 0
        and then Rounded_Size'Result <= Capacity);

   function Can_Reserve
     (Cursor : Byte_Offset;
      Count  : Byte_Count) return Boolean
   is (Cursor mod Alignment = 0
       and then Rounded_Size (Count) > 0
       and then Rounded_Size (Count) <= Capacity - Cursor);

   function Reserve
     (Cursor : Byte_Offset;
      Count  : Byte_Count) return Reservation
   with Post =>
     (Reserve'Result.Accepted = Can_Reserve (Cursor, Count)
      and then Reserve'Result.Start = Cursor
      and then
        (if Reserve'Result.Accepted
         then Reserve'Result.Size = Rounded_Size (Count)
           and then Reserve'Result.Next = Cursor + Rounded_Size (Count)
         else Reserve'Result.Size = 0
           and then Reserve'Result.Next = Cursor));

   --  The production allocator uses the same first-fit operation over 4,096
   --  units.  This bounded state model keeps the proof and exhaustive host
   --  enumeration small while retaining the exact selection and range-update
   --  rules.
   Model_Units : constant := 16;
   subtype Model_Unit_Index is Natural range 0 .. Model_Units - 1;
   subtype Model_Unit_Count is Positive range 1 .. Model_Units;
   type Occupancy_Map is array (Model_Unit_Index) of Boolean;

   type Fit_Result is record
      Accepted : Boolean := False;
      Start    : Model_Unit_Index := Model_Unit_Index'First;
   end record;

   function Range_Is_Free
     (Used   : Occupancy_Map;
      Start  : Model_Unit_Index;
      Needed : Model_Unit_Count) return Boolean
   is (Natural (Start) + Natural (Needed) <= Model_Units
       and then
         (for all Offset in Natural range 0 .. Natural (Needed) - 1 =>
            not Used (Model_Unit_Index (Natural (Start) + Offset))));

   function Find_First_Fit
     (Used   : Occupancy_Map;
      Needed : Model_Unit_Count) return Fit_Result
   with Post =>
     (if Find_First_Fit'Result.Accepted
      then Range_Is_Free
        (Used, Find_First_Fit'Result.Start, Needed)
        and then
          (for all Earlier in Model_Unit_Index =>
             (if Earlier < Find_First_Fit'Result.Start
              then not Range_Is_Free (Used, Earlier, Needed)))
      else
        (for all Candidate in Model_Unit_Index =>
           not Range_Is_Free (Used, Candidate, Needed)));

   function Mark_Allocated
     (Used   : Occupancy_Map;
      Start  : Model_Unit_Index;
      Needed : Model_Unit_Count) return Occupancy_Map
   with Pre => Range_Is_Free (Used, Start, Needed),
        Post =>
          (for all Unit in Model_Unit_Index =>
             Mark_Allocated'Result (Unit) =
               (Used (Unit)
                or else
                  (Unit >= Start
                   and then Unit <
                     Natural (Start) + Natural (Needed))));

   function Release_Range
     (Used   : Occupancy_Map;
      Start  : Model_Unit_Index;
      Length : Model_Unit_Count) return Occupancy_Map
   with Pre =>
     Natural (Start) + Natural (Length) <= Model_Units
     and then
       (for all Offset in Natural range 0 .. Natural (Length) - 1 =>
          Used (Model_Unit_Index (Natural (Start) + Offset))),
        Post =>
          (for all Unit in Model_Unit_Index =>
             Release_Range'Result (Unit) =
               (Used (Unit)
                and then not
                  (Unit >= Start
                   and then Unit <
                     Natural (Start) + Natural (Length))));
end Flyology_Freestanding.Allocator_Model;
