--  SPDX-License-Identifier: MIT OR Apache-2.0

with Flyology_Freestanding.Allocator;
with System.Storage_Elements;

package body Flyology_Freestanding.Allocator_ABI is
   package Allocator renames Flyology_Freestanding.Allocator;
   package Storage renames System.Storage_Elements;
   use type Allocator.Operation_Status;
   use type System.Address;
   use type Storage.Integer_Address;

   type Byte is mod 2 ** 8 with Size => 8;
   type Allocation_Pool is
     array (Natural range 0 .. Allocator.Capacity - 1) of Byte
   with Component_Size => 8;

   Pool : Allocation_Pool
   with Alignment => Allocator.Alignment;
   Metadata : Allocator.Allocator_State;

   procedure Enter_Runtime
   with Import, Convention => C, External_Name => "flyology_freestanding_rts_lock_acquire";

   procedure Leave_Runtime
   with Import, Convention => C, External_Name => "flyology_freestanding_rts_lock_release";

   procedure Reserve
     (Count  : C_Size;
      Status : out Allocator.Operation_Status;
      Result : out System.Address)
   is
      Start : Allocator.Byte_Offset;
      Size  : Allocator.Allocation_Size;
   begin
      Result := System.Null_Address;
      Enter_Runtime;
      begin
         Allocator.Reserve
           (Metadata, Allocator.Byte_Count (Count), Status, Start, Size);
         if Status = Allocator.Success then
            Result := Pool (Natural (Start))'Address;
         end if;
         Leave_Runtime;
      exception
         when others =>
            Leave_Runtime;
            raise;
      end;
   end Reserve;

   procedure Release
     (Object : System.Address;
      Status : out Allocator.Operation_Status)
   is
      Address_Value : Storage.Integer_Address;
      Base          : constant Storage.Integer_Address :=
        Storage.To_Integer (Pool'Address);
      Offset        : Storage.Integer_Address;
      Size          : Allocator.Allocation_Size;
      Start         : Allocator.Byte_Offset;
   begin
      if Object = System.Null_Address then
         Status := Allocator.Success;
         return;
      end if;
      Address_Value := Storage.To_Integer (Object);
      if Address_Value < Base then
         Status := Allocator.Invalid;
         return;
      end if;
      Offset := Address_Value - Base;
      if Offset >= Storage.Integer_Address (Allocator.Capacity)
        or else Offset mod Allocator.Alignment /= 0
      then
         Status := Allocator.Invalid;
         return;
      end if;
      Start := Allocator.Byte_Offset (Offset);

      Enter_Runtime;
      begin
         Allocator.Release (Metadata, Start, Status, Size);
         Leave_Runtime;
      exception
         when others =>
            Leave_Runtime;
            raise;
      end;
   end Release;

   function Malloc (Count : C_Size) return System.Address is
      Status : Allocator.Operation_Status;
      Result : System.Address;
   begin
      Reserve (Count, Status, Result);
      if Status = Allocator.Invalid then
         raise Program_Error;
      end if;
      return Result;
   end Malloc;

   function GNAT_Malloc (Count : C_Size) return System.Address is
      Status : Allocator.Operation_Status;
      Result : System.Address;
   begin
      Reserve (Count, Status, Result);
      if Status = Allocator.Exhausted then
         raise Storage_Error;
      elsif Status /= Allocator.Success then
         raise Program_Error;
      end if;
      return Result;
   end GNAT_Malloc;

   procedure Free (Object : System.Address) is
      Status : Allocator.Operation_Status;
   begin
      Release (Object, Status);
      if Status /= Allocator.Success then
         raise Program_Error;
      end if;
   end Free;

   procedure GNAT_Free (Object : System.Address) is
   begin
      Free (Object);
   end GNAT_Free;
end Flyology_Freestanding.Allocator_ABI;
