--  SPDX-License-Identifier: MIT OR Apache-2.0

package Flyology.Architecture_Context is
   type Unsigned_64 is mod 2 ** 64 with Size => 64;

   type Preserved_Array is array (Natural range 0 .. 11) of Unsigned_64
     with Convention => C;
   type SIMD_Array is array (Natural range 0 .. 7) of Unsigned_64
     with Convention => C;

   type Voluntary_Context is record
      X19_To_X30    : Preserved_Array;
      Stack_Pointer : Unsigned_64;
      Reserved      : Unsigned_64;
      D8_To_D15     : SIMD_Array;
      FPCR          : Unsigned_64;
      FPSR          : Unsigned_64;
   end record
     with Convention => C;

   for Voluntary_Context use record
      X19_To_X30    at 0 range 0 .. 12 * 64 - 1;
      Stack_Pointer at 96 range 0 .. 63;
      Reserved      at 104 range 0 .. 63;
      D8_To_D15     at 112 range 0 .. 8 * 64 - 1;
      FPCR          at 176 range 0 .. 63;
      FPSR          at 184 range 0 .. 63;
   end record;
   for Voluntary_Context'Size use 192 * 8;
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
