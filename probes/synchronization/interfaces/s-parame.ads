package System.Parameters is
   type Size_Type is range -(2 ** 63) .. 2 ** 63 - 1;
   for Size_Type'Size use 64;
   Unspecified_Size : constant Size_Type := -1;
end System.Parameters;
