package System.Multiprocessors is
   type CPU_Range is range 0 .. 255;
   Not_A_Specific_CPU : constant CPU_Range := 0;
   function Number_Of_CPUs return CPU_Range;
end System.Multiprocessors;
