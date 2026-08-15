--  SPDX-License-Identifier: MIT OR Apache-2.0

package body Flyology_Freestanding.Validation
  with SPARK_Mode => On
is
   function To_Core
     (CPU   : Ada_CPU;
      Count : CPU_Count) return Core_Id
   is
      pragma Unreferenced (Count);
   begin
      return Core_Id (CPU - 1);
   end To_Core;

   function To_CPU
     (Core  : Core_Id;
      Count : CPU_Count) return Ada_CPU
   is
      pragma Unreferenced (Count);
   begin
      return Ada_CPU (Core + 1);
   end To_CPU;

   function Extent_Last
     (Base   : Address_Value;
      Length : Address_Value;
      Limit  : Address_Value) return Address_Value
   is
      pragma Unreferenced (Limit);
   begin
      return Base + Length - 1;
   end Extent_Last;

   function To_HHDM
     (Base   : Address_Value;
      Length : Address_Value;
      Offset : Address_Value) return Address_Value
   is
      pragma Unreferenced (Length);
   begin
      return Base + Offset;
   end To_HHDM;

end Flyology_Freestanding.Validation;
