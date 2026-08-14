--  SPDX-License-Identifier: MIT OR Apache-2.0

package Flyology.Allocator_Model
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
end Flyology.Allocator_Model;
