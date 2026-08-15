--  SPDX-License-Identifier: MIT OR Apache-2.0

with Ada.Real_Time;
with Ada.Task_Identification;
with System.Tasking;

package System.Multiprocessors.Dispatching_Domains is
   Dispatching_Domain_Error : exception;

   type Dispatching_Domain (<>) is limited private;

   System_Dispatching_Domain : constant Dispatching_Domain;

   function Create
     (First : CPU;
      Last  : CPU_Range) return Dispatching_Domain;

   function Get_First_CPU (Domain : Dispatching_Domain) return CPU;
   function Get_Last_CPU (Domain : Dispatching_Domain) return CPU_Range;

   type CPU_Set is array (CPU range <>) of Boolean;

   function Create (Set : CPU_Set) return Dispatching_Domain;
   function Get_CPU_Set (Domain : Dispatching_Domain) return CPU_Set;

   function Get_Dispatching_Domain
     (T : Ada.Task_Identification.Task_Id :=
        Ada.Task_Identification.Current_Task) return Dispatching_Domain;

   procedure Assign_Task
     (Domain : in out Dispatching_Domain;
      CPU    : CPU_Range := Not_A_Specific_CPU;
      T      : Ada.Task_Identification.Task_Id :=
        Ada.Task_Identification.Current_Task);

   procedure Set_CPU
     (CPU : CPU_Range;
      T   : Ada.Task_Identification.Task_Id :=
        Ada.Task_Identification.Current_Task);

   function Get_CPU
     (T : Ada.Task_Identification.Task_Id :=
        Ada.Task_Identification.Current_Task) return CPU_Range;

   procedure Delay_Until_And_Set_CPU
     (Delay_Until_Time : Ada.Real_Time.Time;
      CPU              : CPU_Range);

private
   type Dispatching_Domain (First, Last : CPU_Range) is limited record
      Handle     : System.Tasking.Dispatching_Domain_Access := null;
      Identifier : Natural := 0;
   end record;
   for Dispatching_Domain use record
      Handle     at 0  range 0 .. 63;
      First      at 8  range 0 .. 31;
      Last       at 12 range 0 .. 31;
      Identifier at 16 range 0 .. 31;
   end record;
   for Dispatching_Domain'Size use 192;
   for Dispatching_Domain'Alignment use 8;

   System_Domain_Handle : aliased System.Tasking.Dispatching_Domain;

   System_Dispatching_Domain : constant Dispatching_Domain :=
     (First      => CPU'First,
      Last       => CPU_Range'Last,
      Handle     => System_Domain_Handle'Access,
      Identifier => 0);
end System.Multiprocessors.Dispatching_Domains;
