--  SPDX-License-Identifier: MIT OR Apache-2.0

package Flyology.Interrupt_Frames
  with Pure
is
   type Unsigned_8 is mod 2 ** 8 with Size => 8;
   type Unsigned_64 is mod 2 ** 64 with Size => 64;

   XSAVE_Capacity : constant := 4_096;
   type XSAVE_Area is array (Natural range 0 .. XSAVE_Capacity - 1)
     of Unsigned_8
     with Convention         => C,
          Component_Size     => 8,
          Alignment          => 64;

   type GPR_Array is array (Natural range 0 .. 14) of Unsigned_64
     with Convention => C;
   type Reserved_Array is array (Natural range 0 .. 4) of Unsigned_64
     with Convention => C;

   type Interrupt_Frame is record
      GPR              : GPR_Array;
      FS_Base          : Unsigned_64;
      Instruction      : Unsigned_64;
      Code_Segment     : Unsigned_64;
      Flags            : Unsigned_64;
      Stack_Pointer    : Unsigned_64;
      Stack_Segment    : Unsigned_64;
      Vector           : Unsigned_64;
      Error_Code       : Unsigned_64;
      XSAVE_Address    : Unsigned_64;
      XSAVE_Bytes      : Unsigned_64;
      XSAVE_Features   : Unsigned_64;
      Fault_Address    : Unsigned_64;
      Reserved         : Reserved_Array;
   end record
     with Convention => C,
          Alignment  => 64;

   for Interrupt_Frame use record
      GPR              at 0 range 0 .. 15 * 64 - 1;
      FS_Base          at 120 range 0 .. 63;
      Instruction      at 128 range 0 .. 63;
      Code_Segment     at 136 range 0 .. 63;
      Flags            at 144 range 0 .. 63;
      Stack_Pointer    at 152 range 0 .. 63;
      Stack_Segment    at 160 range 0 .. 63;
      Vector           at 168 range 0 .. 63;
      Error_Code       at 176 range 0 .. 63;
      XSAVE_Address    at 184 range 0 .. 63;
      XSAVE_Bytes      at 192 range 0 .. 63;
      XSAVE_Features   at 200 range 0 .. 63;
      Fault_Address    at 208 range 0 .. 63;
      Reserved         at 216 range 0 .. 5 * 64 - 1;
   end record;
   for Interrupt_Frame'Size use 256 * 8;
end Flyology.Interrupt_Frames;
