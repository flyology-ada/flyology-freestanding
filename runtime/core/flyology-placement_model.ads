--  SPDX-License-Identifier: MIT OR Apache-2.0

package Flyology.Placement_Model
  with SPARK_Mode
is
   Max_Cores : constant := 4;

   type Core_Count is range 1 .. Max_Cores;
   type Core_Id is range 0 .. Max_Cores - 1;
   type Ada_CPU is range -1 .. Max_Cores;
   Unspecified_CPU : constant Ada_CPU := -1;

   type Placement_Result is record
      Accepted    : Boolean;
      Core        : Core_Id;
      Next_Cursor : Core_Id;
   end record;

   function Place
     (Requested : Ada_CPU;
      Count     : Core_Count;
      Cursor    : Core_Id) return Placement_Result
   with
     Post =>
       (if Place'Result.Accepted then
          Integer (Place'Result.Core) < Integer (Count)
          and then Integer (Place'Result.Next_Cursor) < Integer (Count)
        else
          Place'Result.Core = Cursor
          and then Place'Result.Next_Cursor = Cursor);
end Flyology.Placement_Model;
