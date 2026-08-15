--  SPDX-License-Identifier: MIT OR Apache-2.0

package body Flyology.Domain_Model
  with SPARK_Mode => On
is
   function Initial (CPUs : CPU_Count) return Domain_State is
      Result : Domain_State := (CPUs => CPUs, others => <>);
   begin
      Result.Domains (0).Used := True;
      Result.Domains (0).Policy := FIFO_Within_Priorities;
      case CPUs is
         when 1 =>
            Result.Domains (0).Cores := [True, False, False, False];
            Result.Owners :=
              [(True, 0), (False, 0), (False, 0), (False, 0)];
         when 2 =>
            Result.Domains (0).Cores := [True, True, False, False];
            Result.Owners :=
              [(True, 0), (True, 0), (False, 0), (False, 0)];
         when 3 =>
            Result.Domains (0).Cores := [True, True, True, False];
            Result.Owners :=
              [(True, 0), (True, 0), (True, 0), (False, 0)];
         when 4 =>
            Result.Domains (0).Cores := [True, True, True, True];
            Result.Owners :=
              [(True, 0), (True, 0), (True, 0), (True, 0)];
      end case;
      Result.Tasks (0) :=
        (Present => True, Domain => 0, Core => 0, Requested_CPU => 1);
      return Result;
   end Initial;

   function Try_Create
     (Before : Domain_State;
      Cores  : Core_Set;
      Policy : Policy_Kind) return Create_Result
   is
      Result : Create_Result := (State => Before, others => <>);
      Any    : Boolean := False;
   begin
      if Can_Create (Before, Cores) then
         Result.Domain := Domain_Id (Before.Domain_Count);
         Result.State := Create_Valid_State (Before, Cores, Policy);
         Result.Status := Created;
         return Result;
      end if;

      if Before.Domain_Count = Max_Domains then
         Result.Status := Domain_Capacity;
         return Result;
      end if;
      for Core in Core_Id loop
         if Cores (Core) then
            Any := True;
            if Core >= Before.CPUs then
               Result.Status := Inactive_Core;
               return Result;
            elsif Before.Owners (Core).Domain /= 0 then
               Result.Status := Core_Not_In_System;
               return Result;
            end if;
            for Slot in Task_Id loop
               if Before.Tasks (Slot).Present
                 and then Before.Tasks (Slot).Core = Core
               then
                  Result.Status := Core_Has_Task;
                  return Result;
               end if;
            end loop;
         end if;
      end loop;
      if not Any then
         Result.Status := Empty_Set;
         return Result;
      end if;

      Result.Status := Would_Empty_System;
      return Result;
   end Try_Create;

   function Create_Valid_State
     (Before : Domain_State;
      Cores  : Core_Set;
      Policy : Policy_Kind) return Domain_State
   is
      Result     : Domain_State := Before;
      New_Domain : constant Domain_Id := Domain_Id (Before.Domain_Count);
   begin
      Result.Domains (New_Domain) :=
        (Used => True, Cores => Cores, Policy => Policy);
      Result.Domains (0).Cores :=
        [for Core in Core_Id =>
           Before.Domains (0).Cores (Core) and then not Cores (Core)];
      Result.Owners :=
        [for Core in Core_Id =>
           (if Cores (Core)
            then
              (Assigned => Before.Owners (Core).Assigned,
               Domain   => New_Domain)
            else Before.Owners (Core))];
      Result.Domain_Count := Before.Domain_Count + 1;
      pragma Assert
        (Is_Exact_Creation
           (Before, Result, Cores, Policy, New_Domain));
      pragma Assert (Domain_Table_Valid (Result));
      pragma Assert (Ownership_Valid (Result));
      pragma Assert (Task_Table_Valid (Result));
      pragma Assert (Environment_Valid (Result));
      return Result;
   end Create_Valid_State;

   function Place
     (Before        : Domain_State;
      Domain        : Domain_Id;
      Requested_CPU : Ada_CPU;
      Cursor        : Core_Id) return Placement_Result
   is
      Requested_Core : Core_Id;
   begin
      if not Before.Domains (Domain).Used then
         return (Accepted => False, Core => Cursor, Next_Cursor => Cursor);
      elsif Requested_CPU not in
        Unspecified_CPU | Not_A_Specific_CPU
      then
         case Requested_CPU is
            when 1 => Requested_Core := 0;
            when 2 => Requested_Core := 1;
            when 3 => Requested_Core := 2;
            when 4 => Requested_Core := 3;
            when others =>
               return
                 (Accepted => False, Core => Cursor, Next_Cursor => Cursor);
         end case;
         if Requested_CPU > Ada_CPU (Before.CPUs)
           or else Before.Owners (Requested_Core).Domain /=
             Domain
         then
            return
              (Accepted => False, Core => Cursor, Next_Cursor => Cursor);
         end if;
         return
           (Accepted    => True,
            Core        => Requested_Core,
            Next_Cursor => Cursor);
      end if;

      for Offset in Core_Id loop
         declare
            Candidate : constant Core_Id :=
              Core_Id ((Integer (Cursor) + Offset) mod Max_Cores);
         begin
            if Before.Owners (Candidate).Assigned
              and then Before.Owners (Candidate).Domain = Domain
            then
               return
                 (Accepted    => True,
                  Core        => Candidate,
                  Next_Cursor =>
                    Core_Id ((Integer (Candidate) + 1) mod Max_Cores));
            end if;
         end;
      end loop;
      return (Accepted => False, Core => Cursor, Next_Cursor => Cursor);
   end Place;

   function Try_Admit
     (Before        : Domain_State;
      Slot          : Task_Id;
      Parent_Domain : Domain_Id;
      Explicit      : Boolean;
      Domain        : Domain_Id;
      Requested_CPU : Ada_CPU;
      Chosen_Core   : Core_Id) return Admit_Result
   is
      Result   : Admit_Result := (State => Before, others => <>);
      Selected : constant Domain_Id :=
        (if Explicit then Domain else Parent_Domain);
   begin
      if Before.Tasks (Slot).Present then
         Result.Status := Task_Already_Present;
      elsif not Before.Domains (Parent_Domain).Used then
         Result.Status := Unknown_Parent;
      elsif not Before.Domains (Selected).Used then
         Result.Status := Unknown_Domain;
      elsif Chosen_Core >= Before.CPUs
        or else not Before.Owners (Chosen_Core).Assigned
        or else Before.Owners (Chosen_Core).Domain /= Selected
      then
         Result.Status := Core_Outside_Domain;
      elsif Requested_CPU not in Unspecified_CPU | Not_A_Specific_CPU
        and then Requested_CPU /= Ada_CPU (Chosen_Core + 1)
      then
         Result.Status := Specific_CPU_Mismatch;
      else
         Result.State.Tasks (Slot) :=
           (Present => True, Domain => Selected, Core => Chosen_Core,
            Requested_CPU => Requested_CPU);
         Result.Status := Admitted;
      end if;
      return Result;
   end Try_Admit;
end Flyology.Domain_Model;
