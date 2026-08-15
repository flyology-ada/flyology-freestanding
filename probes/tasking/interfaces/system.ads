package System is
   type Address is mod 2 ** 64;
   for Address'Size use 64;
   Null_Address : constant Address := 0;
end System;
