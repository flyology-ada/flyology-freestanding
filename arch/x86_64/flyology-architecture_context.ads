--  SPDX-License-Identifier: MIT OR Apache-2.0

package Flyology.Architecture_Context is
   type Unsigned_32 is mod 2 ** 32 with Size => 32;
   type Unsigned_16 is mod 2 ** 16 with Size => 16;
   type Unsigned_64 is mod 2 ** 64 with Size => 64;

   type Voluntary_Context is record
      RBX           : Unsigned_64;
      RBP           : Unsigned_64;
      R12           : Unsigned_64;
      R13           : Unsigned_64;
      R14           : Unsigned_64;
      R15           : Unsigned_64;
      Stack_Pointer : Unsigned_64;
      Instruction   : Unsigned_64;
      MXCSR         : Unsigned_32;
      X87_Control   : Unsigned_16;
      Reserved      : Unsigned_16;
      FS_Base       : Unsigned_64;
   end record
     with Convention => C;

   for Voluntary_Context use record
      RBX           at 0 range 0 .. 63;
      RBP           at 8 range 0 .. 63;
      R12           at 16 range 0 .. 63;
      R13           at 24 range 0 .. 63;
      R14           at 32 range 0 .. 63;
      R15           at 40 range 0 .. 63;
      Stack_Pointer at 48 range 0 .. 63;
      Instruction   at 56 range 0 .. 63;
      MXCSR         at 64 range 0 .. 31;
      X87_Control   at 68 range 0 .. 15;
      Reserved      at 70 range 0 .. 15;
      FS_Base       at 72 range 0 .. 63;
   end record;
   for Voluntary_Context'Size use 80 * 8;
   for Voluntary_Context'Alignment use 16;

   procedure Switch
     (Outgoing : access Voluntary_Context;
      Incoming : access Voluntary_Context)
   with Import,
        Convention    => C,
        External_Name => "flyology_context_switch";

   procedure Start
   with Import,
        Convention    => C,
        External_Name => "flyology_context_start";
end Flyology.Architecture_Context;
