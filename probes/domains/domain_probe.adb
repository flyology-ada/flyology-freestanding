--  SPDX-License-Identifier: MIT OR Apache-2.0

with System.Multiprocessors.Dispatching_Domains;

procedure Domain_Probe is
   package Domains renames System.Multiprocessors.Dispatching_Domains;

   Worker_Domain : Domains.Dispatching_Domain := Domains.Create (2, 3);
   Worker_Set    : constant Domains.CPU_Set :=
     Domains.Get_CPU_Set (Worker_Domain);
   Observed      : Boolean with Volatile;

   task Domain_Worker
     with Dispatching_Domain => Worker_Domain;

   task Domain_CPU_Worker
     with Dispatching_Domain => Worker_Domain,
          CPU                => 2;

   task body Domain_Worker is
   begin
      null;
   end Domain_Worker;

   task body Domain_CPU_Worker is
   begin
      null;
   end Domain_CPU_Worker;
begin
   Observed := Worker_Set (2);
end Domain_Probe;
