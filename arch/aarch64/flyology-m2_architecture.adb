--  SPDX-License-Identifier: MIT OR Apache-2.0

package body Flyology.M2_Architecture is
   package Contexts renames Flyology.Architecture_Context;
   use type System.Address;

   Stack_Alignment : constant System.Address := 16;

   procedure Initialize
     (Item       : out Context;
      Stack_Top  : System.Address;
      Core_Value : System.Address)
   is
   begin
      Item :=
        (X19_To_X30    => [others => 0],
         Stack_Pointer => Contexts.Unsigned_64
           (Stack_Top and not (Stack_Alignment - 1)),
         Reserved      => 0,
         D8_To_D15     => [others => 0],
         FPCR          => 0,
         FPSR          => 0);
      Item.X19_To_X30 (0) := Contexts.Unsigned_64 (Core_Value);
      Item.X19_To_X30 (11) := Contexts.Unsigned_64 (Contexts.Start'Address);
   end Initialize;

   procedure Initialize_Dispatcher
     (Item       : out Context;
      Stack_Top  : System.Address;
      Core_Value : System.Address)
   is
   begin
      Initialize (Item, Stack_Top, Core_Value);
      Item.X19_To_X30 (11) :=
        Contexts.Unsigned_64 (Contexts.Dispatcher_Start'Address);
   end Initialize_Dispatcher;

   procedure Switch
     (Outgoing : access Context;
      Incoming : access Context)
   is
   begin
      Contexts.Switch (Outgoing, Incoming);
   end Switch;
end Flyology.M2_Architecture;
