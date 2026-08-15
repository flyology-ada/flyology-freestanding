--  SPDX-License-Identifier: MIT OR Apache-2.0

package System.Parameters is
   pragma Pure;

   type Size_Type is range -(2 ** 63) .. 2 ** 63 - 1;
   for Size_Type'Size use 64;
   Unspecified_Size : constant Size_Type := -1;
   Runtime_Default_Sec_Stack_Size : constant Size_Type := 1_024;
end System.Parameters;
