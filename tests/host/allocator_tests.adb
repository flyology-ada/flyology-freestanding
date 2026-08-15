--  SPDX-License-Identifier: MIT OR Apache-2.0

with Ada.Text_IO;
with Flyology.Allocator;

procedure Allocator_Tests is
   package Allocator renames Flyology.Allocator;
   use type Allocator.Byte_Count;
   use type Allocator.Operation_Status;

   Thread_Count : constant := 8;
   Reservations : constant := 128;
   subtype Thread_Index is Positive range 1 .. Thread_Count;
   subtype Reservation_Index is Positive range 1 .. Reservations;

   type Allocation is record
      Start : Allocator.Byte_Offset := 0;
      Size  : Allocator.Allocation_Size := 0;
      Used  : Boolean := False;
   end record;
   type Reservation_Row is array (Reservation_Index) of Allocation;
   type Reservation_Table is array (Thread_Index) of Reservation_Row;
   Concurrent_Allocations : Reservation_Table;

   procedure Fail (Message : String) with No_Return;

   procedure Fail (Message : String) is
   begin
      Ada.Text_IO.Put_Line
        (Ada.Text_IO.Standard_Error, "allocator test failed: " & Message);
      raise Program_Error;
   end Fail;

   protected Shared_Allocator is
      procedure Reserve
        (Count  : Allocator.Byte_Count;
         Status : out Allocator.Operation_Status;
         Start  : out Allocator.Byte_Offset;
         Size   : out Allocator.Allocation_Size);
      procedure Release
        (Start  : Allocator.Byte_Offset;
         Status : out Allocator.Operation_Status;
         Size   : out Allocator.Allocation_Size);
      function Live return Natural;
      function Bytes return Allocator.Allocation_Size;
   private
      State : Allocator.Allocator_State := Allocator.Empty_State;
   end Shared_Allocator;

   protected body Shared_Allocator is
      procedure Reserve
        (Count  : Allocator.Byte_Count;
         Status : out Allocator.Operation_Status;
         Start  : out Allocator.Byte_Offset;
         Size   : out Allocator.Allocation_Size)
      is
      begin
         Allocator.Reserve (State, Count, Status, Start, Size);
      end Reserve;

      procedure Release
        (Start  : Allocator.Byte_Offset;
         Status : out Allocator.Operation_Status;
         Size   : out Allocator.Allocation_Size)
      is
      begin
         Allocator.Release (State, Start, Status, Size);
      end Release;

      function Live return Natural is
        (Allocator.Live_Allocations (State));

      function Bytes return Allocator.Allocation_Size is
        (Allocator.Live_Bytes (State));
   end Shared_Allocator;

   protected Wave is
      procedure Claim (Index : out Thread_Index);
      procedure Arrive;
      entry Wait_Until_All_Arrived;
      entry Wait_For_Release;
      procedure Release_All;
      procedure Record_Failure;
      function Failed return Boolean;
   private
      Next_Index : Natural range 1 .. Thread_Count + 1 := 1;
      Arrived    : Natural range 0 .. Thread_Count := 0;
      Released   : Boolean := False;
      Has_Failed : Boolean := False;
   end Wave;

   protected body Wave is
      procedure Claim (Index : out Thread_Index) is
      begin
         if Next_Index > Thread_Count then
            Has_Failed := True;
            Index := Thread_Index'First;
         else
            Index := Thread_Index (Next_Index);
            Next_Index := Next_Index + 1;
         end if;
      end Claim;

      procedure Arrive is
      begin
         if Arrived = Thread_Count then
            Has_Failed := True;
         else
            Arrived := Arrived + 1;
         end if;
      end Arrive;

      entry Wait_Until_All_Arrived when Arrived = Thread_Count is
      begin
         null;
      end Wait_Until_All_Arrived;

      entry Wait_For_Release when Released is
      begin
         null;
      end Wait_For_Release;

      procedure Release_All is
      begin
         Released := True;
      end Release_All;

      procedure Record_Failure is
      begin
         Has_Failed := True;
      end Record_Failure;

      function Failed return Boolean is (Has_Failed);
   end Wave;

   task type Worker;

   task body Worker is
      Thread  : Thread_Index;
      Status  : Allocator.Operation_Status;
      Start   : Allocator.Byte_Offset;
      Size    : Allocator.Allocation_Size;
      Arrived : Boolean := False;
   begin
      Wave.Claim (Thread);
      for Index in Reservation_Index loop
         declare
            Request : constant Allocator.Byte_Count :=
              Allocator.Byte_Count
                (((Thread - 1) * 7 + (Index - 1) * 11) mod 31);
         begin
            Shared_Allocator.Reserve (Request, Status, Start, Size);
            if Status /= Allocator.Success then
               Wave.Record_Failure;
            else
               Concurrent_Allocations (Thread) (Index) :=
                 (Start => Start, Size => Size, Used => True);
            end if;
         end;
      end loop;
      Wave.Arrive;
      Arrived := True;
      Wave.Wait_For_Release;
      for Index in Reservation_Index loop
         if Concurrent_Allocations (Thread) (Index).Used then
            Shared_Allocator.Release
              (Concurrent_Allocations (Thread) (Index).Start,
               Status, Size);
            if Status /= Allocator.Success
              or else Size /= Concurrent_Allocations (Thread) (Index).Size
            then
               Wave.Record_Failure;
            end if;
         end if;
      end loop;
   exception
      when others =>
         Wave.Record_Failure;
         if not Arrived then
            Wave.Arrive;
         end if;
   end Worker;

   procedure Expect_Reserve
     (Count          : Allocator.Byte_Count;
      Expected_Start : Allocator.Byte_Offset;
      Expected_Size  : Allocator.Allocation_Size)
   is
      Status : Allocator.Operation_Status;
      Start  : Allocator.Byte_Offset;
      Size   : Allocator.Allocation_Size;
   begin
      Shared_Allocator.Reserve (Count, Status, Start, Size);
      if Status /= Allocator.Success
        or else Start /= Expected_Start
        or else Size /= Expected_Size
      then
         Fail ("allocation geometry");
      end if;
   end Expect_Reserve;

   procedure Expect_Release
     (Start         : Allocator.Byte_Offset;
      Expected_Size : Allocator.Allocation_Size)
   is
      Status : Allocator.Operation_Status;
      Size   : Allocator.Allocation_Size;
   begin
      Shared_Allocator.Release (Start, Status, Size);
      if Status /= Allocator.Success or else Size /= Expected_Size then
         Fail ("release rejected");
      end if;
   end Expect_Release;

begin
   Expect_Reserve (0, 0, 16);
   Expect_Reserve (31, 16, 32);
   Expect_Reserve (1, 48, 16);
   if Shared_Allocator.Live /= 3 or else Shared_Allocator.Bytes /= 64 then
      Fail ("initial allocation accounting");
   end if;
   Expect_Release (16, 32);
   Expect_Reserve (32, 16, 32);

   declare
      Status : Allocator.Operation_Status;
      Size   : Allocator.Allocation_Size;
   begin
      Shared_Allocator.Release (17, Status, Size);
      if Status /= Allocator.Invalid or else Shared_Allocator.Live /= 3 then
         Fail ("interior offset accepted");
      end if;
   end;
   Expect_Release (16, 32);
   declare
      Status : Allocator.Operation_Status;
      Size   : Allocator.Allocation_Size;
   begin
      Shared_Allocator.Release (16, Status, Size);
      if Status /= Allocator.Invalid then
         Fail ("double release accepted");
      end if;
   end;
   Expect_Release (0, 16);
   Expect_Release (48, 16);
   if Shared_Allocator.Live /= 0 or else Shared_Allocator.Bytes /= 0 then
      Fail ("complete release accounting");
   end if;

   Expect_Reserve (Allocator.Capacity, 0, Allocator.Capacity);
   declare
      Status : Allocator.Operation_Status;
      Start  : Allocator.Byte_Offset;
      Size   : Allocator.Allocation_Size;
   begin
      Shared_Allocator.Reserve (1, Status, Start, Size);
      if Status /= Allocator.Exhausted then
         Fail ("full pool accepted another allocation");
      end if;
      Shared_Allocator.Reserve
        (Allocator.Byte_Count'Last, Status, Start, Size);
      if Status /= Allocator.Exhausted
        or else Shared_Allocator.Live /= 1
        or else Shared_Allocator.Bytes /= Allocator.Capacity
      then
         Fail ("oversized rejection changed state");
      end if;
   end;
   Expect_Release (0, Allocator.Capacity);

   declare
      Workers : array (Thread_Index) of Worker;
      pragma Unreferenced (Workers);
   begin
      Wave.Wait_Until_All_Arrived;
      if Wave.Failed
        or else Shared_Allocator.Live /= Thread_Count * Reservations
      then
         Fail ("concurrent reservation wave");
      end if;
      for Thread in Thread_Index loop
         for Index in Reservation_Index loop
            declare
               Current : constant Allocation :=
                 Concurrent_Allocations (Thread) (Index);
            begin
               if not Current.Used
                 or else Allocator.Byte_Count (Current.Start) mod
                   Allocator.Alignment /= 0
               then
                  Fail ("invalid concurrent allocation");
               end if;
               for Other_Thread in Thread .. Thread_Index'Last loop
                  for Other_Index in Reservation_Index loop
                     if Other_Thread > Thread or else Other_Index > Index then
                        declare
                           Other : constant Allocation :=
                             Concurrent_Allocations
                               (Other_Thread) (Other_Index);
                        begin
                           if Allocator.Byte_Count (Current.Start) <
                                Allocator.Byte_Count (Other.Start) +
                                  Allocator.Byte_Count (Other.Size)
                             and then Allocator.Byte_Count (Other.Start) <
                               Allocator.Byte_Count (Current.Start) +
                                 Allocator.Byte_Count (Current.Size)
                           then
                              Fail ("overlapping concurrent allocations");
                           end if;
                        end;
                     end if;
                  end loop;
               end loop;
            end;
         end loop;
      end loop;
      Wave.Release_All;
   end;
   if Wave.Failed
     or else Shared_Allocator.Live /= 0
     or else Shared_Allocator.Bytes /= 0
   then
      Fail ("concurrent reclamation leak");
   end if;

   Expect_Reserve (Allocator.Capacity, 0, Allocator.Capacity);
   Expect_Release (0, Allocator.Capacity);
   Ada.Text_IO.Put_Line ("FLYOLOGY:RTS:ALLOCATOR:PASS");
end Allocator_Tests;
