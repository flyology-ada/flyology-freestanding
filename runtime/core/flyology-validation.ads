--  SPDX-License-Identifier: MIT OR Apache-2.0

package Flyology.Validation
  with Pure,
       SPARK_Mode => On
is
   Max_Cores : constant := 256;

   type Core_Id is range 0 .. Max_Cores - 1;
   type CPU_Count is range 1 .. Max_Cores;
   type Ada_CPU is range 0 .. Max_Cores;

   Not_A_Specific_CPU : constant Ada_CPU := 0;

   function Is_Specific_CPU
     (CPU   : Ada_CPU;
      Count : CPU_Count) return Boolean
   is (CPU /= Not_A_Specific_CPU and then CPU <= Ada_CPU (Count));

   function To_Core
     (CPU   : Ada_CPU;
      Count : CPU_Count) return Core_Id
   with Pre  => Is_Specific_CPU (CPU, Count),
        Post => Ada_CPU (To_Core'Result + 1) = CPU
          and then Ada_CPU (To_Core'Result + 1) <= Ada_CPU (Count);

   function To_CPU
     (Core  : Core_Id;
      Count : CPU_Count) return Ada_CPU
   with Pre  => Ada_CPU (Core + 1) <= Ada_CPU (Count),
        Post => To_CPU'Result /= Not_A_Specific_CPU
          and then To_CPU'Result <= Ada_CPU (Count)
          and then Core_Id (To_CPU'Result - 1) = Core;

   type Address_Value is mod 2 ** 64;
   Page_Size : constant Address_Value := 4_096;

   subtype Limine_Memory_Type is Natural range 0 .. 8;

   function Is_Page_Aligned (Value : Address_Value) return Boolean
   is (Value mod Page_Size = 0);

   function Extent_Fits
     (Base   : Address_Value;
      Length : Address_Value;
      Limit  : Address_Value) return Boolean
   is (Length > 0
       and then Base <= Limit
       and then Length - 1 <= Limit - Base);

   function Extent_Last
     (Base   : Address_Value;
      Length : Address_Value;
      Limit  : Address_Value) return Address_Value
   with Pre  => Extent_Fits (Base, Length, Limit),
        Post => Extent_Last'Result = Base + Length - 1
          and then Extent_Last'Result <= Limit;

   function Valid_Memory_Entry
     (Base        : Address_Value;
      Length      : Address_Value) return Boolean
   is (Extent_Fits (Base, Length, Address_Value'Last));

   function HHDM_Extent_Fits
     (Base   : Address_Value;
      Length : Address_Value;
      Offset : Address_Value) return Boolean
   is (Valid_Memory_Entry (Base, Length)
       and then Offset <= Address_Value'Last - Base
       and then Length - 1 <= Address_Value'Last - (Base + Offset));

   function To_HHDM
     (Base   : Address_Value;
      Length : Address_Value;
      Offset : Address_Value) return Address_Value
   with Pre  => HHDM_Extent_Fits (Base, Length, Offset),
        Post => To_HHDM'Result = Base + Offset
          and then Extent_Fits
            (To_HHDM'Result, Length, Address_Value'Last);

   type Hardware_Id is mod 2 ** 64;
   type Hardware_Id_Array is array (Core_Id range <>) of Hardware_Id;

   function Unique_Hardware_Ids (Ids : Hardware_Id_Array) return Boolean
   is (for all Left in Ids'Range =>
         (for all Right in Ids'Range =>
            (if Left /= Right then Ids (Left) /= Ids (Right))));

   function Contains
     (Ids : Hardware_Id_Array;
      Id  : Hardware_Id) return Boolean
   is (for some Index in Ids'Range => Ids (Index) = Id);

   function Valid_Topology
     (Ids       : Hardware_Id_Array;
      BSP       : Hardware_Id;
      Core_Count : CPU_Count) return Boolean
   is (Ids'Length = Natural (Core_Count)
       and then Ids'First = Core_Id'First
       and then Ids'Last = Core_Id (Core_Count - 1)
       and then Unique_Hardware_Ids (Ids)
       and then Contains (Ids, BSP));

   type Task_State is (Dormant, Ready, Running, Blocked, Terminated);

   function Legal_Transition
     (From : Task_State;
      To   : Task_State) return Boolean
   is (case From is
          when Dormant    => To = Ready,
          when Ready      => To = Running or else To = Terminated,
          when Running    => To in Ready | Blocked | Terminated,
          when Blocked    => To in Ready | Terminated,
          when Terminated => False);

   function Checked_Transition
     (From : Task_State;
      To   : Task_State) return Task_State
   with Pre  => Legal_Transition (From, To),
        Post => Checked_Transition'Result = To;

   subtype Wake_Generation is Address_Value;

   function Can_Advance (Generation : Wake_Generation) return Boolean
   is (Generation < Wake_Generation'Last);

   function Next_Generation
     (Generation : Wake_Generation) return Wake_Generation
   with Pre  => Can_Advance (Generation),
        Post => Next_Generation'Result = Generation + 1
          and then Next_Generation'Result > Generation;
end Flyology.Validation;
