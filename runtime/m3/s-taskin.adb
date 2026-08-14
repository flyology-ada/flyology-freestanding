--  SPDX-License-Identifier: MIT OR Apache-2.0

package body System.Tasking is
   --  Stable Task_Id values outlive execution-slot reclamation.  Keep their
   --  bounded lifetime pool distinct from Max_Tasks, which bounds one
   --  activation chain and the concurrently admitted execution substrate.
   Identity_Capacity : constant := 256;
   type Identity_Array is array (Natural range 0 .. Identity_Capacity - 1) of
     aliased Ada_Task_Control_Block;

   Identities : Identity_Array;

   function Identity_For_Slot (Slot : Natural) return Task_Id is
   begin
      if Slot /= 0 then
         return null;
      end if;
      Identities (Slot).Slot := Slot;
      Identities (Slot).Execution_Slot := 0;
      Identities (Slot).Incarnation := 1;
      Identities (Slot).Used := True;
      Identities (Slot).Terminated := False;
      return Identities (Slot)'Access;
   end Identity_For_Slot;

   function Create_Identity
     (Execution_Slot : Natural;
      Incarnation    : Natural) return Task_Id
   is
   begin
      if Execution_Slot = 0 or else Incarnation = 0 then
         return null;
      end if;
      for Slot in Positive range 1 .. Identity_Capacity - 1 loop
         if not Identities (Slot).Used then
            Identities (Slot).Slot := Slot;
            Identities (Slot).Execution_Slot := Execution_Slot;
            Identities (Slot).Incarnation := Incarnation;
            Identities (Slot).Used := True;
            Identities (Slot).Terminated := False;
            return Identities (Slot)'Access;
         end if;
      end loop;
      return null;
   end Create_Identity;

   function Slot_Of (Item : Task_Id) return Natural is
   begin
      if Item = null or else not Item.Used
        or else Item.Slot >= Identity_Capacity
      then
         return Identity_Capacity;
      end if;
      return Item.Slot;
   end Slot_Of;

   function Execution_Slot_Of (Item : Task_Id) return Natural is
   begin
      if Item = null or else not Item.Used then
         return Identity_Capacity;
      end if;
      return Item.Execution_Slot;
   end Execution_Slot_Of;

   function Incarnation_Of (Item : Task_Id) return Natural is
   begin
      if Item = null or else not Item.Used then
         return 0;
      end if;
      return Item.Incarnation;
   end Incarnation_Of;

   procedure Mark_Terminated (Item : Task_Id) is
   begin
      if Item = null or else not Item.Used or else Item.Terminated then
         raise Program_Error;
      end if;
      Item.Terminated := True;
   end Mark_Terminated;

   function Identity_Is_Terminated (Item : Task_Id) return Boolean is
     (Item /= null and then Item.Used and then Item.Terminated);

   function Identity_Is_Callable (Item : Task_Id) return Boolean is
     (Item /= null and then Item.Used and then not Item.Terminated);
end System.Tasking;
