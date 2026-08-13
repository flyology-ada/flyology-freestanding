--  SPDX-License-Identifier: MIT OR Apache-2.0

package body Flyology.Placement_Model
  with SPARK_Mode
is
   function Place
     (Requested : Ada_CPU;
      Count     : Core_Count;
      Cursor    : Core_Id) return Placement_Result
   is
      Last : constant Core_Id := Core_Id (Count - 1);
   begin
      if Cursor > Last then
         return (Accepted => False, Core => Cursor, Next_Cursor => Cursor);
      elsif Requested = Unspecified_CPU then
         return
           (Accepted    => True,
            Core        => Cursor,
            Next_Cursor => (if Cursor = Last then 0 else Cursor + 1));
      elsif Requested < 1 or else Requested > Ada_CPU (Count) then
         return (Accepted => False, Core => Cursor, Next_Cursor => Cursor);
      else
         return
           (Accepted    => True,
            Core        => Core_Id (Requested - 1),
            Next_Cursor => Cursor);
      end if;
   end Place;
end Flyology.Placement_Model;
