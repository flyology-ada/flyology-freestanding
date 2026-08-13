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
        (RBX           => 0,
         RBP           => 0,
         R12           => Contexts.Unsigned_64 (Core_Value),
         R13           => 0,
         R14           => 0,
         R15           => 0,
         Stack_Pointer => Contexts.Unsigned_64
           (Stack_Top and not (Stack_Alignment - 1)),
         Instruction   => Contexts.Unsigned_64 (Contexts.Start'Address),
         MXCSR         => 16#1F80#,
         X87_Control   => 16#037F#,
         Reserved      => 0,
         FS_Base       => 0);
   end Initialize;

   procedure Initialize_Dispatcher
     (Item       : out Context;
      Stack_Top  : System.Address;
      Core_Value : System.Address)
   is
   begin
      Item :=
        (RBX           => 0,
         RBP           => 0,
         R12           => Contexts.Unsigned_64 (Core_Value),
         R13           => 0,
         R14           => 0,
         R15           => 0,
         Stack_Pointer => Contexts.Unsigned_64
           (Stack_Top and not (Stack_Alignment - 1)),
         Instruction   => Contexts.Unsigned_64
           (Contexts.Dispatcher_Start'Address),
         MXCSR         => 16#1F80#,
         X87_Control   => 16#037F#,
         Reserved      => 0,
         FS_Base       => 0);
   end Initialize_Dispatcher;

   procedure Switch
     (Outgoing : access Context;
      Incoming : access Context)
   is
   begin
      Contexts.Switch (Outgoing, Incoming);
   end Switch;
end Flyology.M2_Architecture;
