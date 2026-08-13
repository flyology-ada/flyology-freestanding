--  SPDX-License-Identifier: MIT OR Apache-2.0

package body System.Tasking is
   type Identity_Array is array (Natural range 0 .. Max_Tasks - 1) of
     aliased Ada_Task_Control_Block;

   Identities : Identity_Array;

   function Identity_For_Slot (Slot : Natural) return Task_Id is
   begin
      if Slot >= Max_Tasks then
         return null;
      end if;
      Identities (Slot).Slot := Slot;
      return Identities (Slot)'Access;
   end Identity_For_Slot;

   function Slot_Of (Item : Task_Id) return Natural is
   begin
      if Item = null or else Item.Slot >= Max_Tasks then
         return Max_Tasks;
      end if;
      return Item.Slot;
   end Slot_Of;
end System.Tasking;
