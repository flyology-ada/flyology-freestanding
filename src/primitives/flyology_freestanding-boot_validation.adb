--  SPDX-License-Identifier: MIT OR Apache-2.0

package body Flyology_Freestanding.Boot_Validation
  with SPARK_Mode => On
is
   function Memory_Entry_Is_Valid
     (Base        : U64;
      Length      : U64;
      Memory_Type : U64;
      HHDM_Offset : U64) return C_Int
   is
   begin
      if Memory_Entry_Model (Base, Length, Memory_Type, HHDM_Offset) then
         return Valid;
      end if;
      return Invalid;
   end Memory_Entry_Is_Valid;

   function Memory_Entries_Are_Disjoint
     (Left_Base    : U64;
      Left_Length  : U64;
      Right_Base   : U64;
      Right_Length : U64) return C_Int
   is
   begin
      if Memory_Entries_Disjoint_Model
        (Left_Base, Left_Length, Right_Base, Right_Length)
      then
         return Valid;
      end if;

      return Invalid;
   end Memory_Entries_Are_Disjoint;

   function Topology_Identities_Are_Distinct
     (Left_Processor  : U64;
      Left_Hardware   : U64;
      Right_Processor : U64;
      Right_Hardware  : U64) return C_Int
   is
   begin
      if Topology_Identities_Distinct_Model
        (Left_Processor, Left_Hardware, Right_Processor, Right_Hardware)
      then
         return Valid;
      end if;

      return Invalid;
   end Topology_Identities_Are_Distinct;

   function Executable_Translation_Is_Valid
     (Symbol_Virtual      : U64;
      Executable_Virtual  : U64;
      Executable_Physical : U64) return C_Int
   is
   begin
      if Executable_Translation_Model
        (Symbol_Virtual, Executable_Virtual, Executable_Physical)
      then
         return Valid;
      end if;
      return Invalid;
   end Executable_Translation_Is_Valid;
end Flyology_Freestanding.Boot_Validation;
