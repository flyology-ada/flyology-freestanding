--  SPDX-License-Identifier: MIT OR Apache-2.0

with Ada.Task_Identification;
with System;
with System.Multiprocessors;
with System.Multiprocessors.Dispatching_Domains;

package body Flyology.Conformance.Domains is
   package Domains renames System.Multiprocessors.Dispatching_Domains;
   package Tasks renames Ada.Task_Identification;

   use type System.Multiprocessors.CPU_Range;

   Spin_Limit : constant := 50_000_000;
   Threshold  : constant := 10_000;

   procedure Report_Failure
   with Import, Convention => C,
        External_Name => "flyology_conformance_report_failure";

   procedure Report_Layout_Pass
   with Import, Convention => C,
        External_Name => "flyology_conformance_report_layout_pass";

   procedure Report_Query_Pass
   with Import, Convention => C,
        External_Name => "flyology_conformance_report_query_pass";

   procedure Report_Inheritance_Pass
   with Import, Convention => C,
        External_Name => "flyology_conformance_report_inheritance_pass";

   procedure Report_Heterogeneous_Pass
   with Import, Convention => C,
        External_Name => "flyology_conformance_report_heterogeneous_pass";

   procedure Report_All_Core_Pass
   with Import, Convention => C,
        External_Name => "flyology_conformance_report_all_core_pass";

   procedure Report_All_Core_Start_Failure
   with Import, Convention => C,
        External_Name => "flyology_conformance_report_all_core_start_failure";

   procedure Report_All_Core_Done_Failure
   with Import, Convention => C,
        External_Name => "flyology_conformance_report_all_core_done_failure";

   procedure Check_Full_Context (Completion_Flag : System.Address)
   with Import, Convention => C,
        External_Name => "flyology_conformance_preemption_canary";

   function Build_Secondary return Domains.Dispatching_Domain is
   begin
      if System.Multiprocessors.Number_Of_CPUs = 4 then
         return Domains.Create (3, 4);
      end if;
      return Domains.Get_Dispatching_Domain;
   end Build_Secondary;

   Secondary_Domain : constant Domains.Dispatching_Domain := Build_Secondary;

   Query_OK : Boolean := False with Atomic;
   Inherited_OK : Boolean := False with Atomic;
   System_Override_OK : Boolean := False with Atomic;

   FIFO_First_Started  : Boolean := False with Atomic;
   FIFO_Second_Started : Boolean := False with Atomic;
   FIFO_First_Done     : Boolean := False with Atomic;
   FIFO_Second_Done    : Boolean := False with Atomic;
   FIFO_Release        : aliased Boolean := False with Atomic;

   RR_First_Count  : Natural := 0 with Atomic;
   RR_Second_Count : Natural := 0 with Atomic;
   RR_First_Done   : Boolean := False with Atomic;
   RR_Second_Done  : Boolean := False with Atomic;

   type Core_Flags is array (Positive range 1 .. 4) of Boolean
     with Atomic_Components;
   All_Started : Core_Flags := [others => False];
   All_Done    : Core_Flags := [others => False];
   All_Release : Core_Flags := [others => False];

   function Has_Only
     (Domain : Domains.Dispatching_Domain;
      First  : System.Multiprocessors.CPU;
      Last   : System.Multiprocessors.CPU) return Boolean
   is
      Set : constant Domains.CPU_Set := Domains.Get_CPU_Set (Domain);
   begin
      if Domains.Get_First_CPU (Domain) /= First
        or else Domains.Get_Last_CPU (Domain) /= Last
      then
         return False;
      end if;
      for CPU in Set'Range loop
         if Set (CPU) /= (CPU in First .. Last) then
            return False;
         end if;
      end loop;
      return True;
   end Has_Only;

   task type Query_Task
     (Assigned_CPU : System.Multiprocessors.CPU_Range)
     with Dispatching_Domain => Secondary_Domain,
          CPU                => Assigned_CPU,
          Priority           => 5;

   task type Inherited_Child_Task with Priority => 5;

   task type System_Override_Child_Task
     with Dispatching_Domain => Domains.System_Dispatching_Domain,
          CPU                => 1,
          Priority           => 5;

   task type Secondary_Parent_Task
     (Assigned_CPU : System.Multiprocessors.CPU_Range)
     with Dispatching_Domain => Secondary_Domain,
          CPU                => Assigned_CPU,
          Priority           => 5;

   task type FIFO_First_Task with CPU => 1, Priority => 5;
   task type FIFO_Second_Task with CPU => 1, Priority => 5;
   task type FIFO_Observer_Task with CPU => 1, Priority => 10;

   task type RR_First_Task
     with Dispatching_Domain => Secondary_Domain,
          CPU                => 3,
          Priority           => 5;
   task type RR_Second_Task
     with Dispatching_Domain => Secondary_Domain,
          CPU                => 3,
          Priority           => 5;

   task type System_Load_Task
     (Assigned_CPU : System.Multiprocessors.CPU_Range)
     with CPU => Assigned_CPU, Priority => 5;
   task type System_Coordinator_Task
     (Assigned_CPU : System.Multiprocessors.CPU_Range)
     with CPU => Assigned_CPU, Priority => 10;
   task type Secondary_Load_Task
     (Assigned_CPU : System.Multiprocessors.CPU_Range)
     with Dispatching_Domain => Secondary_Domain,
          CPU                => Assigned_CPU,
          Priority           => 5;
   task type Secondary_Coordinator_Task
     (Assigned_CPU : System.Multiprocessors.CPU_Range)
     with Dispatching_Domain => Secondary_Domain,
          CPU                => Assigned_CPU,
          Priority           => 10;

   task body Query_Task is
      Domain : constant Domains.Dispatching_Domain :=
        Domains.Get_Dispatching_Domain (Tasks.Current_Task);
      Expected : constant System.Multiprocessors.CPU :=
        (if System.Multiprocessors.Number_Of_CPUs = 4 then 3 else 1);
   begin
      Query_OK := Domains.Get_CPU = Assigned_CPU
        and then Has_Only
          (Domain, Expected,
           (if System.Multiprocessors.Number_Of_CPUs = 4 then 4 else 1));
   end Query_Task;

   task body Inherited_Child_Task is
      Domain : constant Domains.Dispatching_Domain :=
        Domains.Get_Dispatching_Domain;
      CPU    : constant System.Multiprocessors.CPU_Range := Domains.Get_CPU;
   begin
      Inherited_OK := CPU in 3 .. 4 and then Has_Only (Domain, 3, 4);
   end Inherited_Child_Task;

   task body System_Override_Child_Task is
      Domain : constant Domains.Dispatching_Domain :=
        Domains.Get_Dispatching_Domain;
   begin
      System_Override_OK :=
        Domains.Get_CPU = 1 and then Has_Only (Domain, 1, 2);
   end System_Override_Child_Task;

   task body Secondary_Parent_Task is
      Child           : Inherited_Child_Task;
      System_Override : System_Override_Child_Task;
   begin
      null;
   end Secondary_Parent_Task;

   task body FIFO_First_Task is
   begin
      FIFO_First_Started := True;
      Check_Full_Context (FIFO_Release'Address);
      FIFO_First_Done := True;
   end FIFO_First_Task;

   task body FIFO_Second_Task is
   begin
      FIFO_Second_Started := True;
      FIFO_Second_Done := True;
   end FIFO_Second_Task;

   task body FIFO_Observer_Task is
   begin
      for Attempt in 1 .. 1_000 loop
         exit when FIFO_First_Started;
         delay 0.001;
      end loop;
      if not FIFO_First_Started then
         Report_Failure;
      end if;
      delay 0.010;
      if FIFO_Second_Started then
         Report_Failure;
      end if;
      FIFO_Release := True;
   end FIFO_Observer_Task;

   task body RR_First_Task is
   begin
      for Iteration in 1 .. Spin_Limit loop
         RR_First_Count := Iteration;
         exit when RR_First_Count >= Threshold
           and then RR_Second_Count >= Threshold;
      end loop;
      if RR_First_Count < Threshold or else RR_Second_Count < Threshold then
         Report_Failure;
      end if;
      RR_First_Done := True;
   end RR_First_Task;

   task body RR_Second_Task is
   begin
      for Iteration in 1 .. Spin_Limit loop
         RR_Second_Count := Iteration;
         exit when RR_First_Count >= Threshold
           and then RR_Second_Count >= Threshold;
      end loop;
      if RR_First_Count < Threshold or else RR_Second_Count < Threshold then
         Report_Failure;
      end if;
      RR_Second_Done := True;
   end RR_Second_Task;

   procedure Run_Load (Assigned_CPU : Positive) is
   begin
      All_Started (Assigned_CPU) := True;
      Check_Full_Context (All_Release (Assigned_CPU)'Address);
      All_Done (Assigned_CPU) := True;
   end Run_Load;

   procedure Run_Coordinator (Assigned_CPU : Positive) is
   begin
      for Attempt in 1 .. 1_000 loop
         exit when All_Started (Assigned_CPU);
         delay 0.001;
      end loop;
      if not All_Started (Assigned_CPU) then
         Report_All_Core_Start_Failure;
         Report_Failure;
      end if;
      delay 0.005;
      All_Release (Assigned_CPU) := True;
   end Run_Coordinator;

   task body System_Load_Task is
   begin
      Run_Load (Positive (Assigned_CPU));
   end System_Load_Task;

   task body System_Coordinator_Task is
   begin
      Run_Coordinator (Positive (Assigned_CPU));
   end System_Coordinator_Task;

   task body Secondary_Load_Task is
   begin
      Run_Load (Positive (Assigned_CPU));
   end Secondary_Load_Task;

   task body Secondary_Coordinator_Task is
   begin
      Run_Coordinator (Positive (Assigned_CPU));
   end Secondary_Coordinator_Task;

   procedure Check_Layout is
      System_Domain : constant Domains.Dispatching_Domain :=
        Domains.Get_Dispatching_Domain;
   begin
      if System.Multiprocessors.Number_Of_CPUs = 4 then
         if not Has_Only (System_Domain, 1, 2)
           or else not Has_Only (Secondary_Domain, 3, 4)
         then
            Report_Failure;
         end if;
      elsif not Has_Only (System_Domain, 1, 1)
        or else not Has_Only (Secondary_Domain, 1, 1)
      then
         Report_Failure;
      end if;
      Report_Layout_Pass;
   end Check_Layout;

   procedure Check_Query is
      Assigned : constant System.Multiprocessors.CPU_Range :=
        (if System.Multiprocessors.Number_Of_CPUs = 4 then 3 else 1);
      Worker : Query_Task (Assigned);
   begin
      null;
   end Check_Query;

   procedure Check_Inheritance is
      Parent : Secondary_Parent_Task (3);
   begin
      null;
   end Check_Inheritance;

   procedure Check_Heterogeneous_Policies is
      procedure Execute is
         FIFO_First  : FIFO_First_Task;
         FIFO_Second : FIFO_Second_Task;
         FIFO_Watcher : FIFO_Observer_Task;
         RR_First    : RR_First_Task;
         RR_Second   : RR_Second_Task;
      begin
         null;
      end Execute;
   begin
      FIFO_First_Started := False;
      FIFO_Second_Started := False;
      FIFO_First_Done := False;
      FIFO_Second_Done := False;
      FIFO_Release := False;
      RR_First_Count := 0;
      RR_Second_Count := 0;
      RR_First_Done := False;
      RR_Second_Done := False;
      Execute;
      if not FIFO_First_Done or else not FIFO_Second_Done
        or else not RR_First_Done or else not RR_Second_Done
      then
         Report_Failure;
      end if;
      Report_Heterogeneous_Pass;
   end Check_Heterogeneous_Policies;

   procedure Check_All_Core_Preemption is
      procedure Execute is
         Load_1 : System_Load_Task (1);
         Load_2 : System_Load_Task (2);
         Load_3 : Secondary_Load_Task (3);
         Load_4 : Secondary_Load_Task (4);
         Coordinator_1 : System_Coordinator_Task (1);
         Coordinator_2 : System_Coordinator_Task (2);
         Coordinator_3 : Secondary_Coordinator_Task (3);
         Coordinator_4 : Secondary_Coordinator_Task (4);
      begin
         null;
      end Execute;
   begin
      All_Started := [others => False];
      All_Done := [others => False];
      All_Release := [others => False];
      Execute;
      if (for some Done of All_Done => not Done) then
         Report_All_Core_Done_Failure;
         Report_Failure;
      end if;
      Report_All_Core_Pass;
   end Check_All_Core_Preemption;

   procedure Run is
   begin
      Check_Layout;
      Query_OK := False;
      Check_Query;
      if not Query_OK then
         Report_Failure;
      end if;
      Report_Query_Pass;
      if System.Multiprocessors.Number_Of_CPUs = 4 then
         Inherited_OK := False;
         System_Override_OK := False;
         Check_Inheritance;
         if not Inherited_OK or else not System_Override_OK then
            Report_Failure;
         end if;
         Report_Inheritance_Pass;
         Check_Heterogeneous_Policies;
         Check_All_Core_Preemption;
      end if;
   end Run;
end Flyology.Conformance.Domains;
