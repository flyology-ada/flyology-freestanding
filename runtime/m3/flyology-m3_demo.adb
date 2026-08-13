--  SPDX-License-Identifier: MIT OR Apache-2.0

with Ada.Task_Identification;
with Flyology.M3_Runtime;
with System.Multiprocessors;

package body Flyology.M3_Demo is
   use type Ada.Task_Identification.Task_Id;
   use type System.Multiprocessors.CPU_Range;

   type Done_Array is array (Positive range 1 .. 4) of Boolean
     with Atomic_Components;
   type Identity_Array is array (Positive range 1 .. 4) of
     Ada.Task_Identification.Task_Id with Atomic_Components;
   type Core_Array is array (Positive range 1 .. 4) of Natural
     with Atomic_Components;

   Auto_Done   : Done_Array := [others => False];
   Pinned_Done : Boolean := False with Atomic;
   Auto_Id     : Identity_Array :=
     [others => Ada.Task_Identification.Null_Task_Id];
   Pinned_Id   : Ada.Task_Identification.Task_Id :=
     Ada.Task_Identification.Null_Task_Id with Atomic;
   Auto_Core   : Core_Array := [others => Natural'Last];

   task type Auto_Worker_Type (Index : Positive);
   task type Pinned_Worker_Type with CPU => 1;

   task body Auto_Worker_Type is
      Self : constant Ada.Task_Identification.Task_Id :=
        Ada.Task_Identification.Current_Task;
   begin
      if Self = Ada.Task_Identification.Null_Task_Id
        or else not Ada.Task_Identification.Is_Callable (Self)
        or else Ada.Task_Identification.Is_Terminated (Self)
      then
         raise Program_Error;
      end if;
      Auto_Id (Index) := Self;
      Auto_Core (Index) := Flyology.M3_Runtime.Current_Core_Number;
      Flyology.M3_Runtime.Demo_Parallel_Barrier;
      Auto_Done (Index) := True;
   end Auto_Worker_Type;

   task body Pinned_Worker_Type is
      Self : constant Ada.Task_Identification.Task_Id :=
        Ada.Task_Identification.Current_Task;
   begin
      if Self = Ada.Task_Identification.Null_Task_Id
        or else not Ada.Task_Identification.Is_Callable (Self)
        or else Ada.Task_Identification.Is_Terminated (Self)
        or else Flyology.M3_Runtime.Current_Core_Number /= 0
      then
         raise Program_Error;
      end if;
      Pinned_Id := Self;
      Pinned_Done := True;
   end Pinned_Worker_Type;

   procedure Report_Pass
   with Import, Convention => C,
        External_Name => "flyology_m3_report_ordinary_pass";

   procedure Report_Parallel_Pass
   with Import, Convention => C,
        External_Name => "flyology_m3_report_parallel_pass";

   procedure Report_Failure
   with Import, Convention => C,
        External_Name => "flyology_m2_report_failure";

   procedure Run is
      Environment : constant Ada.Task_Identification.Task_Id :=
        Ada.Task_Identification.Current_Task;
      Auto_Object_Id : Identity_Array :=
        [others => Ada.Task_Identification.Null_Task_Id];
      Pinned_Object_Id : Ada.Task_Identification.Task_Id :=
        Ada.Task_Identification.Null_Task_Id;
   begin
      declare
         Auto_1 : Auto_Worker_Type (1);
         Auto_2 : Auto_Worker_Type (2);
         Auto_3 : Auto_Worker_Type (3);
         Auto_4 : Auto_Worker_Type (4);
         Pinned : Pinned_Worker_Type;
      begin
         Auto_Object_Id (1) := Auto_1'Identity;
         Auto_Object_Id (2) := Auto_2'Identity;
         Auto_Object_Id (3) := Auto_3'Identity;
         Auto_Object_Id (4) := Auto_4'Identity;
         Pinned_Object_Id := Pinned'Identity;
      end;

      if Environment = Ada.Task_Identification.Null_Task_Id
        or else not Pinned_Done
        or else Pinned_Id /= Pinned_Object_Id
        or else Pinned_Id = Environment
        or else not Ada.Task_Identification.Is_Terminated (Pinned_Id)
        or else Ada.Task_Identification.Is_Callable (Pinned_Id)
      then
         Report_Failure;
      end if;

      for Index in Auto_Id'Range loop
         if not Auto_Done (Index)
           or else Auto_Id (Index) /= Auto_Object_Id (Index)
           or else Auto_Id (Index) = Pinned_Id
           or else Auto_Id (Index) = Environment
           or else not Ada.Task_Identification.Is_Terminated (Auto_Id (Index))
           or else Ada.Task_Identification.Is_Callable (Auto_Id (Index))
         then
            Report_Failure;
         end if;
         for Other in Auto_Id'Range loop
            if Index /= Other and then Auto_Id (Index) = Auto_Id (Other) then
               Report_Failure;
            end if;
         end loop;
      end loop;

      if System.Multiprocessors.Number_Of_CPUs = 4 then
         for Index in Auto_Core'Range loop
            if Auto_Core (Index) /= Index - 1 then
               Report_Failure;
            end if;
         end loop;
         Report_Parallel_Pass;
      else
         for Index in Auto_Core'Range loop
            if Auto_Core (Index) /= 0 then
               Report_Failure;
            end if;
         end loop;
      end if;
      Report_Pass;
   end Run;
end Flyology.M3_Demo;
