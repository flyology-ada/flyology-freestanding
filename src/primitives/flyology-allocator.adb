--  SPDX-License-Identifier: MIT OR Apache-2.0

package body Flyology.Allocator
with SPARK_Mode
is
   function Empty_State return Allocator_State is
     (Used    => [others => False],
      Lengths => [others => 0],
      Live    => 0,
      Bytes   => 0);

   function Live_Allocations (State : Allocator_State) return Natural is
     (State.Live);

   function Live_Bytes (State : Allocator_State) return Allocation_Size is
     (State.Bytes);

   procedure Reserve
     (State  : in out Allocator_State;
      Count  : Byte_Count;
      Status : out Operation_Status;
      Start  : out Byte_Offset;
      Size   : out Allocation_Size)
   is
      Rounded : constant Byte_Count := Rounded_Size (Count);
      Needed  : Unit_Length;
      Run     : Unit_Length := 0;
      First   : Unit_Index := Unit_Index'First;
      Found   : Boolean := False;
   begin
      Status := Exhausted;
      Start := 0;
      Size := 0;
      if Rounded = 0 then
         return;
      end if;

      Needed := Unit_Length (Rounded / Alignment);
      pragma Assert (Needed > 0);
      for Unit in Unit_Index loop
         if not State.Used (Unit) then
            if State.Lengths (Unit) /= 0 then
               Status := Invalid;
               return;
            end if;
            if Run = 0 then
               First := Unit;
            end if;
            if Run = Needed - 1 then
               Found := True;
               exit;
            else
               Run := Run + 1;
            end if;
         else
            Run := 0;
         end if;
         pragma Loop_Invariant (Run < Needed);
      end loop;

      if not Found then
         return;
      end if;
      if Natural (Needed) > Units - Natural (First)
        or else State.Live = Units
        or else State.Bytes > Capacity - Natural (Rounded)
      then
         Status := Invalid;
         return;
      end if;
      pragma Assert (Natural (First) + Natural (Needed) <= Units);

      for Offset in Natural range 0 .. Natural (Needed) - 1 loop
         declare
            Unit : constant Unit_Index :=
              Unit_Index (Natural (First) + Offset);
         begin
            if State.Used (Unit) or else State.Lengths (Unit) /= 0 then
               Status := Invalid;
               return;
            end if;
         end;
         pragma Loop_Invariant
           (Natural (First) + Offset < Units);
      end loop;

      for Offset in Natural range 0 .. Natural (Needed) - 1 loop
         State.Used (Unit_Index (Natural (First) + Offset)) := True;
         pragma Loop_Invariant
           (Natural (First) + Offset < Units);
      end loop;
      State.Lengths (First) := Needed;
      State.Live := State.Live + 1;
      State.Bytes := State.Bytes + Natural (Rounded);
      Status := Success;
      Start := Byte_Offset (Natural (First) * Alignment);
      Size := Natural (Rounded);
   end Reserve;

   procedure Release
     (State  : in out Allocator_State;
      Start  : Byte_Offset;
      Status : out Operation_Status;
      Size   : out Allocation_Size)
   is
      First  : constant Unit_Index :=
        Unit_Index (Natural (Start) / Alignment);
      Length : constant Unit_Length := State.Lengths (First);
   begin
      Status := Invalid;
      Size := 0;
      if Byte_Count (Start) mod Alignment /= 0
        or else Length = 0
        or else Natural (Length) > Units - Natural (First)
        or else State.Live = 0
        or else State.Bytes < Natural (Length) * Alignment
      then
         return;
      end if;

      for Offset in Natural range 0 .. Natural (Length) - 1 loop
         declare
            Unit : constant Unit_Index :=
              Unit_Index (Natural (First) + Offset);
         begin
            if not State.Used (Unit)
              or else (Offset /= 0 and then State.Lengths (Unit) /= 0)
            then
               return;
            end if;
         end;
         pragma Loop_Invariant
           (Natural (First) + Offset < Units);
      end loop;

      State.Lengths (First) := 0;
      for Offset in Natural range 0 .. Natural (Length) - 1 loop
         State.Used (Unit_Index (Natural (First) + Offset)) := False;
         pragma Loop_Invariant
           (Natural (First) + Offset < Units);
      end loop;
      State.Live := State.Live - 1;
      State.Bytes := State.Bytes - Natural (Length) * Alignment;
      Status := Success;
      Size := Natural (Length) * Alignment;
   end Release;
end Flyology.Allocator;
