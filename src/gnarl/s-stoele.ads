--  SPDX-License-Identifier: MIT OR Apache-2.0

package System.Storage_Elements is
   pragma Pure;

   type Storage_Offset is range
     -(2 ** (System.Address'Size - 1)) ..
     2 ** (System.Address'Size - 1) - 1;
   subtype Storage_Count is Storage_Offset range 0 .. Storage_Offset'Last;

   type Integer_Address is mod 2 ** System.Address'Size;

   function To_Integer (Value : System.Address) return Integer_Address
   is (Integer_Address (Value));

   function "-"
     (Left  : System.Address;
      Right : Storage_Offset) return System.Address
   is (Left - System.Address (Right));
end System.Storage_Elements;
