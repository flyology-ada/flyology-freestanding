with System;

package System.Storage_Elements is
   type Storage_Count is range -(2 ** 63) .. 2 ** 63 - 1;
   type Integer_Address is mod 2 ** 64;

   function To_Integer (Value : System.Address) return Integer_Address
   is (Integer_Address (Value));
end System.Storage_Elements;
