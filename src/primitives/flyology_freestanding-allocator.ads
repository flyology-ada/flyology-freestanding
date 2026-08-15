--  SPDX-License-Identifier: MIT OR Apache-2.0

package Flyology_Freestanding.Allocator
with SPARK_Mode
is
   Alignment : constant := 16;
   Capacity  : constant := 65_536;
   Units     : constant := Capacity / Alignment;

   type Byte_Count is mod 2 ** 64;
   subtype Byte_Offset is Byte_Count range 0 .. Capacity - Alignment;
   subtype Allocation_Size is Natural range 0 .. Capacity;

   type Operation_Status is (Success, Exhausted, Invalid);

   type Allocator_State is private;

   function Empty_State return Allocator_State;

   function Live_Allocations (State : Allocator_State) return Natural;
   function Live_Bytes (State : Allocator_State) return Allocation_Size;

   function Rounded_Size (Count : Byte_Count) return Byte_Count
   is (if Count = 0 then Alignment
       elsif Count > Capacity then 0
       else ((Count - 1) / Alignment + 1) * Alignment)
   with Post =>
     (if Rounded_Size'Result = 0
      then Count > Capacity
      else Rounded_Size'Result >= Count
        and then Rounded_Size'Result mod Alignment = 0
        and then Rounded_Size'Result <= Capacity);

   procedure Reserve
     (State  : in out Allocator_State;
      Count  : Byte_Count;
      Status : out Operation_Status;
      Start  : out Byte_Offset;
      Size   : out Allocation_Size)
   with Post =>
     (if Status = Success
      then Size = Natural (Rounded_Size (Count))
        and then Size > 0
        and then Byte_Count (Start) mod Alignment = 0
        and then Byte_Count (Start) + Byte_Count (Size) <= Capacity
        and then Live_Allocations (State) =
          Live_Allocations (State'Old) + 1
        and then Live_Bytes (State) = Live_Bytes (State'Old) + Size
      else State = State'Old and then Start = 0 and then Size = 0);

   procedure Release
     (State  : in out Allocator_State;
      Start  : Byte_Offset;
      Status : out Operation_Status;
      Size   : out Allocation_Size)
   with Post =>
     (if Status = Success
      then Size > 0
        and then Live_Allocations (State'Old) > 0
        and then Live_Allocations (State) =
          Live_Allocations (State'Old) - 1
        and then Live_Bytes (State'Old) >= Size
        and then Live_Bytes (State) = Live_Bytes (State'Old) - Size
      else State = State'Old and then Size = 0);

private
   subtype Unit_Index is Natural range 0 .. Units - 1;
   subtype Unit_Length is Natural range 0 .. Units;
   type Occupancy_Map is array (Unit_Index) of Boolean;
   type Length_Map is array (Unit_Index) of Unit_Length;

   type Allocator_State is record
      Used    : Occupancy_Map := [others => False];
      Lengths : Length_Map := [others => 0];
      Live    : Natural range 0 .. Units := 0;
      Bytes   : Allocation_Size := 0;
   end record;
end Flyology_Freestanding.Allocator;
