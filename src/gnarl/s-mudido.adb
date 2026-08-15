--  SPDX-License-Identifier: MIT OR Apache-2.0

with Ada.Task_Identification.Flyology;
with Flyology_Freestanding.RTS;

package body System.Multiprocessors.Dispatching_Domains is
   package Identity_Bridge renames Ada.Task_Identification.Flyology;
   package Runtime renames Flyology_Freestanding.RTS;

   type Domain_Handle_Array is array (Natural range 1 .. 3) of
     aliased System.Tasking.Dispatching_Domain;
   Domain_Handles : Domain_Handle_Array;

   function Membership
     (Identifier : Natural) return Runtime.Domain_CPU_Set;
   function First_Of (Set : Runtime.Domain_CPU_Set) return CPU;
   function Last_Of (Set : Runtime.Domain_CPU_Set) return CPU_Range;

   procedure Freeze_Dispatching_Domains
   with Export, Convention => Ada,
        External_Name => "__gnat_freeze_dispatching_domains";

   procedure Freeze_Dispatching_Domains is
   begin
      Runtime.Freeze_Domains;
   end Freeze_Dispatching_Domains;

   function Membership (Identifier : Natural) return Runtime.Domain_CPU_Set is
   begin
      if Identifier > 3 then
         raise Dispatching_Domain_Error;
      end if;
      return Runtime.Domain_CPUs (Identifier);
   end Membership;

   function First_Of (Set : Runtime.Domain_CPU_Set) return CPU is
   begin
      for Candidate in Runtime.Domain_CPU loop
         if Set (Candidate) then
            return CPU (Candidate);
         end if;
      end loop;
      raise Dispatching_Domain_Error;
   end First_Of;

   function Last_Of (Set : Runtime.Domain_CPU_Set) return CPU_Range is
   begin
      for Candidate in reverse Runtime.Domain_CPU loop
         if Set (Candidate) then
            return CPU_Range (Candidate);
         end if;
      end loop;
      raise Dispatching_Domain_Error;
   end Last_Of;

   function Create
     (First : CPU;
      Last  : CPU_Range) return Dispatching_Domain
   is
      Set : Runtime.Domain_CPU_Set := [others => False];
   begin
      if Last < First or else Last > Number_Of_CPUs then
         raise Dispatching_Domain_Error;
      end if;
      for Candidate in First .. Last loop
         Set (Runtime.Domain_CPU (Candidate)) := True;
      end loop;
      return Result : Dispatching_Domain (First, Last) do
         declare
            Created : Boolean;
         begin
            Runtime.Create_Domain (Set, Result.Identifier, Created);
            if not Created then
               raise Dispatching_Domain_Error;
            end if;
            Result.Handle := Domain_Handles (Result.Identifier)'Access;
            Runtime.Register_Domain_Alias
              (Result.Identifier, Result.Handle.all'Address);
         end;
      end return;
   end Create;

   function Get_First_CPU (Domain : Dispatching_Domain) return CPU is
     (First_Of (Membership (Domain.Identifier)));

   function Get_Last_CPU (Domain : Dispatching_Domain) return CPU_Range is
     (Last_Of (Membership (Domain.Identifier)));

   function Create (Set : CPU_Set) return Dispatching_Domain is
      Fixed : Runtime.Domain_CPU_Set := [others => False];
      Any   : Boolean := False;
      First : CPU := CPU'First;
      Last  : CPU_Range := Not_A_Specific_CPU;
   begin
      for Candidate in Set'Range loop
         if Set (Candidate) then
            if Candidate > Number_Of_CPUs
              or else Candidate > CPU (Runtime.Domain_CPU'Last)
            then
               raise Dispatching_Domain_Error;
            end if;
            Fixed (Runtime.Domain_CPU (Candidate)) := True;
            if not Any then
               First := Candidate;
            end if;
            Last := Candidate;
            Any := True;
         end if;
      end loop;
      if not Any then
         raise Dispatching_Domain_Error;
      end if;
      return Result : Dispatching_Domain (First, Last) do
         declare
            Created : Boolean;
         begin
            Runtime.Create_Domain (Fixed, Result.Identifier, Created);
            if not Created then
               raise Dispatching_Domain_Error;
            end if;
            Result.Handle := Domain_Handles (Result.Identifier)'Access;
            Runtime.Register_Domain_Alias
              (Result.Identifier, Result.Handle.all'Address);
         end;
      end return;
   end Create;

   function Get_CPU_Set (Domain : Dispatching_Domain) return CPU_Set is
      Fixed : constant Runtime.Domain_CPU_Set :=
        Membership (Domain.Identifier);
      Result : CPU_Set (CPU'First .. Number_Of_CPUs) := [others => False];
   begin
      for Candidate in Result'Range loop
         if Candidate <= CPU (Runtime.Domain_CPU'Last) then
            Result (Candidate) := Fixed (Runtime.Domain_CPU (Candidate));
         end if;
      end loop;
      return Result;
   end Get_CPU_Set;

   function Get_Dispatching_Domain
     (T : Ada.Task_Identification.Task_Id :=
        Ada.Task_Identification.Current_Task) return Dispatching_Domain
   is
      Identifier : constant Natural := Runtime.Task_Domain
        (Identity_Bridge.Runtime_Identity (T));
      Set : constant Runtime.Domain_CPU_Set := Membership (Identifier);
      First : constant CPU := First_Of (Set);
      Last  : constant CPU_Range := Last_Of (Set);
   begin
      return Result : Dispatching_Domain (First, Last) do
         Result.Handle :=
           (if Identifier = 0
            then System_Domain_Handle'Access
            else Domain_Handles (Identifier)'Access);
         Result.Identifier := Identifier;
      end return;
   end Get_Dispatching_Domain;

   procedure Assign_Task
     (Domain : in out Dispatching_Domain;
      CPU    : CPU_Range := Not_A_Specific_CPU;
      T      : Ada.Task_Identification.Task_Id :=
        Ada.Task_Identification.Current_Task)
   is
      pragma Unreferenced (Domain, CPU, T);
   begin
      raise Dispatching_Domain_Error;
   end Assign_Task;

   procedure Set_CPU
     (CPU : CPU_Range;
      T   : Ada.Task_Identification.Task_Id :=
        Ada.Task_Identification.Current_Task)
   is
      pragma Unreferenced (CPU, T);
   begin
      raise Dispatching_Domain_Error;
   end Set_CPU;

   function Get_CPU
     (T : Ada.Task_Identification.Task_Id :=
        Ada.Task_Identification.Current_Task) return CPU_Range
   is
     (CPU_Range
        (Runtime.Assigned_CPU (Identity_Bridge.Runtime_Identity (T))));

   procedure Delay_Until_And_Set_CPU
     (Delay_Until_Time : Ada.Real_Time.Time;
      CPU              : CPU_Range)
   is
      pragma Unreferenced (Delay_Until_Time, CPU);
   begin
      raise Dispatching_Domain_Error;
   end Delay_Until_And_Set_CPU;
begin
   Runtime.Register_Domain_Alias
     (0, System_Domain_Handle'Address);
end System.Multiprocessors.Dispatching_Domains;
