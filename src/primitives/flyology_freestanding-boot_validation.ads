--  SPDX-License-Identifier: MIT OR Apache-2.0

package Flyology_Freestanding.Boot_Validation
  with Pure,
       SPARK_Mode => On
is
   type C_Int is range -(2 ** 31) .. 2 ** 31 - 1
     with Convention => C,
          Size       => 32;

   type U64 is mod 2 ** 64
     with Convention => C,
          Size       => 64;

   Invalid : constant C_Int := 0;
   Valid   : constant C_Int := 1;

   function Memory_Entry_Model
     (Base        : U64;
      Length      : U64;
      Memory_Type : U64;
      HHDM_Offset : U64) return Boolean
   is (Memory_Type <= 8
       and then Length > 0
       and then Length - 1 <= U64'Last - Base
       and then HHDM_Offset <= U64'Last - Base
       and then Length - 1 <= U64'Last - (Base + HHDM_Offset));

   function Memory_Entries_Disjoint_Model
     (Left_Base    : U64;
      Left_Length  : U64;
      Right_Base   : U64;
      Right_Length : U64) return Boolean
   is (Left_Length > 0
       and then Right_Length > 0
       and then Left_Length - 1 <= U64'Last - Left_Base
       and then Right_Length - 1 <= U64'Last - Right_Base
       and then
         (Left_Base + Left_Length - 1 < Right_Base
          or else Right_Base + Right_Length - 1 < Left_Base));

   function Topology_Identities_Distinct_Model
     (Left_Processor  : U64;
      Left_Hardware   : U64;
      Right_Processor : U64;
      Right_Hardware  : U64) return Boolean
   is (Left_Processor /= Right_Processor
       and then Left_Hardware /= Right_Hardware);

   function Executable_Translation_Model
     (Symbol_Virtual      : U64;
      Executable_Virtual  : U64;
      Executable_Physical : U64) return Boolean
   is (Symbol_Virtual >= Executable_Virtual
       and then Symbol_Virtual - Executable_Virtual
         <= U64'Last - Executable_Physical
       and then Executable_Physical
         + (Symbol_Virtual - Executable_Virtual) <= 2 ** 48 - 1
       and then
         (Executable_Physical + (Symbol_Virtual - Executable_Virtual))
           mod 4_096 = 0);

   function Memory_Entry_Is_Valid
     (Base        : U64;
      Length      : U64;
      Memory_Type : U64;
      HHDM_Offset : U64) return C_Int
   with Export,
        Convention    => C,
        External_Name => "flyology_freestanding_memory_entry_is_valid",
        Post           =>
          Memory_Entry_Is_Valid'Result in Invalid | Valid
          and then (Memory_Entry_Is_Valid'Result = Valid)
            = Memory_Entry_Model
              (Base, Length, Memory_Type, HHDM_Offset);

   function Memory_Entries_Are_Disjoint
     (Left_Base    : U64;
      Left_Length  : U64;
      Right_Base   : U64;
      Right_Length : U64) return C_Int
   with Export,
        Convention    => C,
        External_Name => "flyology_freestanding_memory_entries_are_disjoint",
        Post           =>
          Memory_Entries_Are_Disjoint'Result in Invalid | Valid
          and then (Memory_Entries_Are_Disjoint'Result = Valid)
            = Memory_Entries_Disjoint_Model
              (Left_Base, Left_Length, Right_Base, Right_Length);

   function Topology_Identities_Are_Distinct
     (Left_Processor  : U64;
      Left_Hardware   : U64;
      Right_Processor : U64;
      Right_Hardware  : U64) return C_Int
   with Export,
        Convention    => C,
        External_Name => "flyology_freestanding_topology_identities_are_distinct",
        Post           =>
          Topology_Identities_Are_Distinct'Result in Invalid | Valid
          and then (Topology_Identities_Are_Distinct'Result = Valid)
            = Topology_Identities_Distinct_Model
              (Left_Processor, Left_Hardware,
               Right_Processor, Right_Hardware);

   function Executable_Translation_Is_Valid
     (Symbol_Virtual   : U64;
      Executable_Virtual : U64;
      Executable_Physical : U64) return C_Int
   with Export,
        Convention    => C,
        External_Name => "flyology_freestanding_executable_translation_is_valid",
        Post           =>
          Executable_Translation_Is_Valid'Result in Invalid | Valid
          and then (Executable_Translation_Is_Valid'Result = Valid)
            = Executable_Translation_Model
              (Symbol_Virtual, Executable_Virtual, Executable_Physical);
end Flyology_Freestanding.Boot_Validation;
