--  SPDX-License-Identifier: MIT OR Apache-2.0

with Ada.Text_IO;
with Flyology.Domain_Model;

procedure M6_Domain_Tests is
   package Domains renames Flyology.Domain_Model;

   use type Domains.Admit_Status;
   use type Domains.Ada_CPU;
   use type Domains.Create_Status;
   use type Domains.Domain_State;
   use type Domains.Domain_Array;
   use type Domains.Core_Owner_Array;
   use type Domains.Policy_Kind;

   type Hash_Word is mod 2 ** 64;
   Hash  : Hash_Word := 16#CBF29CE484222325#;
   Edges : Natural := 0;

   procedure Count (Value : Integer) is
   begin
      Hash := (Hash xor Hash_Word (Value + 65_536)) * 16#100000001B3#;
      Edges := Edges + 1;
   end Count;

   function Only (Core : Domains.Core_Id) return Domains.Core_Set is
      Result : Domains.Core_Set := [others => False];
   begin
      Result (Core) := True;
      return Result;
   end Only;

   procedure Check_Initial is
   begin
      for CPUs in Domains.CPU_Count loop
         declare
            State : constant Domains.Domain_State := Domains.Initial (CPUs);
         begin
            pragma Assert (Domains.Valid (State));
            pragma Assert (State.Domain_Count = 1);
            pragma Assert
              (State.Domains (0).Policy = Domains.FIFO_Within_Priorities);
            pragma Assert
              (State.Tasks (0).Present
               and then State.Tasks (0).Domain = 0
               and then State.Tasks (0).Core = 0
               and then State.Tasks (0).Requested_CPU = 1);
            for Core in Domains.Core_Id loop
               pragma Assert
                 (State.Owners (Core).Assigned = (Core < CPUs));
               pragma Assert
                 (State.Domains (0).Cores (Core) = (Core < CPUs));
               Count
                 (1_000 * CPUs + 10 * Core
                  + Boolean'Pos (State.Owners (Core).Assigned));
            end loop;
         end;
      end loop;
   end Check_Initial;

   procedure Check_Create is
      Empty      : constant Domains.Core_Set := [others => False];
      Inactive   : constant Domains.Core_Set := Only (2);
      Busy       : constant Domains.Core_Set := Only (0);
      Secondary  : constant Domains.Core_Set := [False, False, True, True];
      State_2    : constant Domains.Domain_State := Domains.Initial (2);
      State_4    : constant Domains.Domain_State := Domains.Initial (4);
      Attempt    : Domains.Create_Result;
      Split      : Domains.Domain_State;
      Capacity   : Domains.Domain_State := State_4;
   begin
      Attempt := Domains.Try_Create
        (State_2, Empty, Domains.Round_Robin_Within_Priorities);
      pragma Assert
        (Attempt.Status = Domains.Empty_Set and then Attempt.State = State_2);
      Count (2_000 + Domains.Create_Status'Pos (Attempt.Status));

      Attempt := Domains.Try_Create
        (State_2, Inactive, Domains.Round_Robin_Within_Priorities);
      pragma Assert
        (Attempt.Status = Domains.Inactive_Core
         and then Attempt.State = State_2);
      Count (2_010 + Domains.Create_Status'Pos (Attempt.Status));

      Attempt := Domains.Try_Create
        (State_2, Busy, Domains.Round_Robin_Within_Priorities);
      pragma Assert
        (Attempt.Status = Domains.Core_Has_Task
         and then Attempt.State = State_2);
      Count (2_020 + Domains.Create_Status'Pos (Attempt.Status));

      Attempt := Domains.Try_Create
        (State_4, Secondary, Domains.Round_Robin_Within_Priorities);
      pragma Assert (Attempt.Status = Domains.Created and then Attempt.Domain = 1);
      Split := Attempt.State;
      pragma Assert (Domains.Valid (Split));
      pragma Assert
        (Split.Domains (1).Policy = Domains.Round_Robin_Within_Priorities);
      pragma Assert
        (Split.Owners (0).Domain = 0
         and then Split.Owners (1).Domain = 0
         and then Split.Owners (2).Domain = 1
         and then Split.Owners (3).Domain = 1);
      Count (2_030 + Integer (Attempt.Domain));

      Attempt := Domains.Try_Create
        (Split, Secondary, Domains.FIFO_Within_Priorities);
      pragma Assert
        (Attempt.Status = Domains.Core_Not_In_System
         and then Attempt.State = Split);
      Count (2_040 + Domains.Create_Status'Pos (Attempt.Status));

      for Core in Domains.Core_Id range 1 .. 3 loop
         Attempt := Domains.Try_Create
           (Capacity, Only (Core), Domains.Round_Robin_Within_Priorities);
         pragma Assert (Attempt.Status = Domains.Created);
         Capacity := Attempt.State;
         Count (2_100 + 10 * Core + Integer (Attempt.Domain));
      end loop;
      pragma Assert (Capacity.Domain_Count = Domains.Max_Domains);
      Attempt := Domains.Try_Create
        (Capacity, Empty, Domains.FIFO_Within_Priorities);
      pragma Assert
        (Attempt.Status = Domains.Domain_Capacity
         and then Attempt.State = Capacity);
      Count (2_200 + Domains.Create_Status'Pos (Attempt.Status));
   end Check_Create;

   procedure Check_Admission is
      Secondary : constant Domains.Core_Set := [False, False, True, True];
      Created   : constant Domains.Create_Result :=
        Domains.Try_Create
          (Domains.Initial (4), Secondary,
           Domains.Round_Robin_Within_Priorities);
      State     : Domains.Domain_State := Created.State;
      Before    : Domains.Domain_State;
      Attempt   : Domains.Admit_Result;

      procedure Require_Rejected
        (Status : Domains.Admit_Status;
         Slot   : Domains.Task_Id;
         Parent : Domains.Domain_Id;
         Explicit : Boolean;
         Domain : Domains.Domain_Id;
         CPU    : Domains.Ada_CPU;
         Core   : Domains.Core_Id)
      is
      begin
         Before := State;
         Attempt := Domains.Try_Admit
           (State, Slot, Parent, Explicit, Domain, CPU, Core);
         pragma Assert (Attempt.Status = Status);
         pragma Assert (Attempt.State = Before);
         Count
           (3_500 + 100 * Domains.Admit_Status'Pos (Status)
            + 10 * Integer (Slot) + Integer (Core));
      end Require_Rejected;
   begin
      pragma Assert (Created.Status = Domains.Created);

      Attempt := Domains.Try_Admit
        (State, 1, 0, True, 1, 3, 2);
      pragma Assert (Attempt.Status = Domains.Admitted);
      State := Attempt.State;
      pragma Assert
        (State.Tasks (1).Domain = 1 and then State.Tasks (1).Core = 2);
      Count (3_001);

      Attempt := Domains.Try_Admit
        (State, 2, 1, False, 0, 0, 3);
      pragma Assert (Attempt.Status = Domains.Admitted);
      State := Attempt.State;
      pragma Assert
        (State.Tasks (2).Domain = 1 and then State.Tasks (2).Core = 3);
      Count (3_102);

      Attempt := Domains.Try_Admit
        (State, 3, 0, False, 1, 2, 1);
      pragma Assert (Attempt.Status = Domains.Admitted);
      State := Attempt.State;
      pragma Assert
        (State.Tasks (3).Domain = 0 and then State.Tasks (3).Core = 1);
      Count (3_203);

      Require_Rejected
        (Domains.Task_Already_Present, 1, 0, True, 1, 3, 2);
      Require_Rejected
        (Domains.Unknown_Parent, 4, 2, False, 0, 0, 0);
      Require_Rejected
        (Domains.Unknown_Domain, 4, 0, True, 2, 0, 0);
      Require_Rejected
        (Domains.Core_Outside_Domain, 4, 0, True, 1, 0, 1);
      Require_Rejected
        (Domains.Specific_CPU_Mismatch, 4, 0, True, 1, 4, 2);

      pragma Assert
        (State.Domains = Created.State.Domains
         and then State.Owners = Created.State.Owners);
   end Check_Admission;

   procedure Check_Placement is
      Secondary : constant Domains.Core_Set := [False, False, True, True];
      Created   : constant Domains.Create_Result :=
        Domains.Try_Create
          (Domains.Initial (4), Secondary,
           Domains.Round_Robin_Within_Priorities);
      State     : constant Domains.Domain_State := Created.State;
      Result    : Domains.Placement_Result;
      Cursor    : Domains.Core_Id := 0;
   begin
      pragma Assert (Created.Status = Domains.Created);

      Result := Domains.Place
        (State, 1, Domains.Unspecified_CPU, Cursor);
      pragma Assert
        (Result.Accepted and then Result.Core = 2
         and then Result.Next_Cursor = 3);
      Cursor := Result.Next_Cursor;
      Count (4_000 + 10 * Result.Core + Result.Next_Cursor);

      Result := Domains.Place
        (State, 1, Domains.Not_A_Specific_CPU, Cursor);
      pragma Assert
        (Result.Accepted and then Result.Core = 3
         and then Result.Next_Cursor = 0);
      Cursor := Result.Next_Cursor;
      Count (4_100 + 10 * Result.Core + Result.Next_Cursor);

      Result := Domains.Place
        (State, 1, Domains.Unspecified_CPU, Cursor);
      pragma Assert
        (Result.Accepted and then Result.Core = 2
         and then Result.Next_Cursor = 3);
      Count (4_200 + 10 * Result.Core + Result.Next_Cursor);

      Result := Domains.Place (State, 1, 3, Cursor);
      pragma Assert
        (Result.Accepted and then Result.Core = 2
         and then Result.Next_Cursor = Cursor);
      Count (4_300 + 10 * Result.Core + Result.Next_Cursor);

      Result := Domains.Place (State, 1, 1, Cursor);
      pragma Assert
        (not Result.Accepted and then Result.Core = Cursor
         and then Result.Next_Cursor = Cursor);
      Count (4_400 + Boolean'Pos (Result.Accepted));

      Result := Domains.Place
        (State, 2, Domains.Not_A_Specific_CPU, Cursor);
      pragma Assert
        (not Result.Accepted and then Result.Core = Cursor
         and then Result.Next_Cursor = Cursor);
      Count (4_500 + Boolean'Pos (Result.Accepted));
   end Check_Placement;

begin
   Check_Initial;
   Check_Create;
   Check_Admission;
   Check_Placement;
   Ada.Text_IO.Put_Line
     ("FLYOLOGY:M6:DOMAIN_MODEL:PASS:EDGES" & Natural'Image (Edges)
      & ":HASH" & Hash_Word'Image (Hash));
end M6_Domain_Tests;
