--  SPDX-License-Identifier: MIT OR Apache-2.0

package Flyology.Interrupt_Frames
  with Pure
is
   type Unsigned_64 is mod 2 ** 64 with Size => 64;

   type GPR_Array is array (Natural range 0 .. 30) of Unsigned_64
     with Convention => C;
   type SIMD_Register is array (Natural range 0 .. 1) of Unsigned_64
     with Convention => C;
   type SIMD_Array is array (Natural range 0 .. 31) of SIMD_Register
     with Convention => C;

   type Interrupt_Frame is record
      X                 : GPR_Array;
      Interrupted_SP    : Unsigned_64;
      Exception_Address : Unsigned_64;
      Saved_Status      : Unsigned_64;
      Syndrome          : Unsigned_64;
      Fault_Address     : Unsigned_64;
      Thread_Pointer    : Unsigned_64;
      Vector            : Unsigned_64;
      FPCR              : Unsigned_64;
      FPSR              : Unsigned_64;
      SIMD              : SIMD_Array;
   end record
     with Convention => C,
          Alignment  => 16;

   for Interrupt_Frame use record
      X                 at 0 range 0 .. 31 * 64 - 1;
      Interrupted_SP    at 248 range 0 .. 63;
      Exception_Address at 256 range 0 .. 63;
      Saved_Status      at 264 range 0 .. 63;
      Syndrome          at 272 range 0 .. 63;
      Fault_Address     at 280 range 0 .. 63;
      Thread_Pointer    at 288 range 0 .. 63;
      Vector            at 296 range 0 .. 63;
      FPCR              at 304 range 0 .. 63;
      FPSR              at 312 range 0 .. 63;
      SIMD              at 320 range 0 .. 32 * 128 - 1;
   end record;
   for Interrupt_Frame'Size use 832 * 8;
end Flyology.Interrupt_Frames;
