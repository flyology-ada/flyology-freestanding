--  SPDX-License-Identifier: MIT OR Apache-2.0

with System;

package Flyology.Allocator_ABI is
   type C_Size is mod 2 ** 64
   with Convention => C, Size => 64;

   function Malloc (Count : C_Size) return System.Address
   with Export, Convention => C, External_Name => "malloc";

   function GNAT_Malloc (Count : C_Size) return System.Address
   with Export, Convention => C, External_Name => "__gnat_malloc";

   procedure Free (Object : System.Address)
   with Export, Convention => C, External_Name => "free";

   procedure GNAT_Free (Object : System.Address)
   with Export, Convention => C, External_Name => "__gnat_free";
end Flyology.Allocator_ABI;
