--  SPDX-License-Identifier: MIT OR Apache-2.0

with Flyology.RTS;

package body Flyology.Scheduling is
   package Domains renames System.Multiprocessors.Dispatching_Domains;
   package Runtime renames Flyology.RTS;
   use type System.Multiprocessors.CPU_Range;
   use type Runtime.Scheduling_Policy;

   function Runtime_Policy (Policy : Policy_Kind) return
     Runtime.Scheduling_Policy
   is
     (case Policy is
         when FIFO_Within_Priorities => Runtime.FIFO_Within_Priorities,
         when Round_Robin_Within_Priorities =>
           Runtime.Round_Robin_Within_Priorities);

   function Quantum_Of
     (Configuration : Policy_Configuration)
      return Runtime.Scheduling_Quantum_Microseconds
   is (Runtime.Scheduling_Quantum_Microseconds (Configuration.Quantum));

   procedure Validate (Configuration : Policy_Configuration) is
   begin
      if (Configuration.Policy = FIFO_Within_Priorities
          and then Configuration.Quantum /= 0)
        or else
          (Configuration.Policy = Round_Robin_Within_Priorities
           and then Configuration.Quantum = 0)
      then
         raise Scheduling_Error;
      end if;
   end Validate;

   procedure Set_Global_Policy (Configuration : Policy_Configuration) is
   begin
      Validate (Configuration);
      Runtime.Set_Global_Scheduling_Policy
        (Runtime_Policy (Configuration.Policy), Quantum_Of (Configuration));
   end Set_Global_Policy;

   procedure Set_Domain_Policy
     (Domain        : Domains.Dispatching_Domain;
      Configuration : Policy_Configuration)
   is
      Membership : constant Domains.CPU_Set := Domains.Get_CPU_Set (Domain);
      Set        : Runtime.Domain_CPU_Set := [others => False];
   begin
      Validate (Configuration);
      for CPU in Membership'Range loop
         if CPU <= System.Multiprocessors.CPU (Runtime.Domain_CPU'Last)
           and then Membership (CPU)
         then
            Set (Runtime.Domain_CPU (CPU)) := True;
         end if;
      end loop;
      Runtime.Set_Domain_Scheduling_Policy
        (Set, Runtime_Policy (Configuration.Policy),
         Quantum_Of (Configuration));
   end Set_Domain_Policy;

   procedure Set_CPU_Policy
     (CPU           : System.Multiprocessors.CPU;
      Configuration : Policy_Configuration)
   is
   begin
      Validate (Configuration);
      if CPU > System.Multiprocessors.Number_Of_CPUs
        or else CPU > System.Multiprocessors.CPU (Runtime.Domain_CPU'Last)
      then
         raise Scheduling_Error;
      end if;
      Runtime.Set_CPU_Scheduling_Policy
        (Runtime.Domain_CPU (CPU), Runtime_Policy (Configuration.Policy),
         Quantum_Of (Configuration));
   end Set_CPU_Policy;

   function Policy_Of
     (CPU : System.Multiprocessors.CPU) return Policy_Configuration
   is
      Policy : Runtime.Scheduling_Policy;
      Quantum : Runtime.Scheduling_Quantum_Microseconds;
   begin
      if CPU > System.Multiprocessors.Number_Of_CPUs
        or else CPU > System.Multiprocessors.CPU (Runtime.Domain_CPU'Last)
      then
         raise Scheduling_Error;
      end if;
      Runtime.Get_CPU_Scheduling_Configuration
        (Runtime.Domain_CPU (CPU), Policy, Quantum);
      if Policy = Runtime.FIFO_Within_Priorities then
         if Quantum /= 0 then
            raise Program_Error;
         end if;
         return FIFO;
      end if;
      if Quantum = 0 then
         raise Program_Error;
      end if;
      return Round_Robin (Quantum_Microseconds (Quantum));
   end Policy_Of;
end Flyology.Scheduling;
