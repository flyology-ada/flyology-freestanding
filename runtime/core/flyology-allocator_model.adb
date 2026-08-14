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
end Flyology.Allocator_Model;
