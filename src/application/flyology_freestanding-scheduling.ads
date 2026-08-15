--  SPDX-License-Identifier: MIT OR Apache-2.0

with System.Multiprocessors;
with System.Multiprocessors.Dispatching_Domains;

package Flyology_Freestanding.Scheduling is
   Scheduling_Error : exception;

   type Policy_Kind is
     (FIFO_Within_Priorities,
      Round_Robin_Within_Priorities);

   subtype Quantum_Microseconds is Positive range 1 .. Integer'Last;
   Default_Round_Robin_Quantum : constant Quantum_Microseconds := 10_000;

   type Policy_Configuration is record
      Policy  : Policy_Kind := FIFO_Within_Priorities;
      Quantum : Natural range 0 .. Integer'Last := 0;
   end record;

   FIFO : constant Policy_Configuration :=
     (Policy => FIFO_Within_Priorities, Quantum => 0);

   function Round_Robin
     (Quantum : Quantum_Microseconds := Default_Round_Robin_Quantum)
      return Policy_Configuration
   is ((Policy => Round_Robin_Within_Priorities,
        Quantum => Natural (Quantum)));

   procedure Set_Global_Policy (Configuration : Policy_Configuration);

   procedure Set_Domain_Policy
     (Domain        :
        System.Multiprocessors.Dispatching_Domains.Dispatching_Domain;
      Configuration : Policy_Configuration);

   procedure Set_CPU_Policy
     (CPU           : System.Multiprocessors.CPU;
      Configuration : Policy_Configuration);

   function Policy_Of
     (CPU : System.Multiprocessors.CPU) return Policy_Configuration;
end Flyology_Freestanding.Scheduling;
