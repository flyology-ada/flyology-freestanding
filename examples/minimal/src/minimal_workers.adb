--  SPDX-License-Identifier: MIT OR Apache-2.0

with Flyology_Freestanding.Console;
with System.Multiprocessors;
with System.Multiprocessors.Dispatching_Domains;

package body Minimal_Workers is
   package Domains renames System.Multiprocessors.Dispatching_Domains;
   use type System.Multiprocessors.CPU_Range;

   Worker_Count : constant Positive := 8;

   task type Printer_Type is
      entry Write
        (Assigned_CPU : Positive;
         Worker_Index : Positive);
   end Printer_Type;

   task type Worker_Type
     (Assigned_CPU : System.Multiprocessors.CPU_Range;
      Worker_Index : Positive;
      Printer      : not null access Printer_Type)
     with CPU => Assigned_CPU;

   task body Printer_Type is
      Line : String := "CORE 1 WORKER 1";
   begin
      for Call in 1 .. Worker_Count loop
         accept Write
           (Assigned_CPU : Positive;
            Worker_Index : Positive)
         do
            case Assigned_CPU is
               when 1 => Line (6) := '1';
               when 2 => Line (6) := '2';
               when 3 => Line (6) := '3';
               when 4 => Line (6) := '4';
               when others => raise Program_Error;
            end case;
            case Worker_Index is
               when 1 => Line (15) := '1';
               when 2 => Line (15) := '2';
               when others => raise Program_Error;
            end case;
            Flyology_Freestanding.Console.Put_Line (Line);
         end Write;
      end loop;
   end Printer_Type;

   task body Worker_Type is
      Observed_CPU : constant System.Multiprocessors.CPU_Range :=
        Domains.Get_CPU;
   begin
      if Observed_CPU /= Assigned_CPU then
         raise Program_Error;
      end if;
      Printer.Write (Positive (Observed_CPU), Worker_Index);
   end Worker_Type;

   procedure Run is
      Printer : aliased Printer_Type;
   begin
      declare
         Core_1_Worker : Worker_Type (1, 1, Printer'Access);
         Core_2_Worker : Worker_Type (2, 1, Printer'Access);
         Core_3_Worker : Worker_Type (3, 1, Printer'Access);
         Core_4_Worker : Worker_Type (4, 1, Printer'Access);
      begin
         null;
      end;

      declare
         Core_1_Worker : Worker_Type (1, 2, Printer'Access);
         Core_2_Worker : Worker_Type (2, 2, Printer'Access);
         Core_3_Worker : Worker_Type (3, 2, Printer'Access);
         Core_4_Worker : Worker_Type (4, 2, Printer'Access);
      begin
         null;
      end;
   end Run;
end Minimal_Workers;
