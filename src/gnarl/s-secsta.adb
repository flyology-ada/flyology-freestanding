--  SPDX-License-Identifier: MIT OR Apache-2.0

package body System.Secondary_Stack is
   use type System.Storage_Elements.Integer_Address;
   use type System.Storage_Elements.Storage_Count;

   Task_Capacity : constant := 16;
   Stack_Size    : constant := 1_024;
   type Byte is mod 2 ** 8 with Size => 8;
   type Secondary_Area is array (Natural range 0 .. Stack_Size - 1) of Byte
     with Component_Size => 8, Alignment => 16;
   type Area_Array is array (Natural range 0 .. Task_Capacity - 1) of
     aliased Secondary_Area;
   type Cursor_Array is array (Natural range 0 .. Task_Capacity - 1) of
     System.Storage_Elements.Storage_Count;

   Areas   : Area_Array;
   Cursors : Cursor_Array := [others => 0];

   function Current_Slot return Natural;

   function Current_Task_Slot return System.Address
   with Import, Convention => C,
        External_Name => "flyology_freestanding_exception_task_slot";

   procedure Raise_Storage_Error (Location : System.Address; Line : Integer)
   with Import, Convention => C,
        External_Name => "__gnat_rcheck_SE_Explicit_Raise", No_Return;

   function Current_Slot return Natural is
      Raw : constant System.Address := Current_Task_Slot;
   begin
      if Raw >= Task_Capacity then
         Raise_Storage_Error (System.Null_Address, 0);
      end if;
      return Natural (Raw);
   end Current_Slot;

   function SS_Mark return Mark_Id is
     (Mark_Id (Cursors (Current_Slot)));

   procedure SS_Release (Mark : Mark_Id) is
      Slot : constant Natural := Current_Slot;
   begin
      if System.Storage_Elements.Storage_Count (Mark) > Cursors (Slot) then
         Raise_Storage_Error (System.Null_Address, 0);
      end if;
      Cursors (Slot) := System.Storage_Elements.Storage_Count (Mark);
   end SS_Release;

   procedure SS_Allocate
     (Addr         : out System.Address;
      Storage_Size : System.Storage_Elements.Storage_Count;
      Alignment    : System.Storage_Elements.Storage_Count)
   is
      Slot    : constant Natural := Current_Slot;
      Current : constant System.Storage_Elements.Storage_Count :=
        Cursors (Slot);
      Address_Remainder : System.Storage_Elements.Storage_Count;
      Padding           : System.Storage_Elements.Storage_Count;
      Start             : System.Storage_Elements.Storage_Count;
   begin
      if Alignment = 0 or else Alignment > Stack_Size
        or else Storage_Size > Stack_Size
      then
         Raise_Storage_Error (System.Null_Address, 0);
      end if;
      Address_Remainder := System.Storage_Elements.Storage_Count
        (System.Storage_Elements.To_Integer (Areas (Slot) (0)'Address)
         mod System.Storage_Elements.Integer_Address (Alignment));
      Padding :=
        (Alignment - ((Address_Remainder + Current) mod Alignment))
        mod Alignment;
      if Padding > Stack_Size - Current
        or else Storage_Size > Stack_Size - Current - Padding
      then
         Raise_Storage_Error (System.Null_Address, 0);
      end if;
      Start := Current + Padding;
      Addr := Areas (Slot) (Natural (Start))'Address;
      Cursors (Slot) := Start + Storage_Size;
   end SS_Allocate;
end System.Secondary_Stack;
