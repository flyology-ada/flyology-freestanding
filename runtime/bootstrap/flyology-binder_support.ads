--  SPDX-License-Identifier: MIT OR Apache-2.0

with System;

package Flyology.Binder_Support is
   type No_Param_Procedure is access procedure;
   pragma Favor_Top_Level (No_Param_Procedure);

   Main_Priority : Integer := -1;
   pragma Export (C, Main_Priority, "__gl_main_priority");

   Time_Slice_Value : Integer := -1;
   pragma Export (C, Time_Slice_Value, "__gl_time_slice_val");

   WC_Encoding : Character := 'b';
   pragma Export (C, WC_Encoding, "__gl_wc_encoding");

   Locking_Policy : Character := ' ';
   pragma Export (C, Locking_Policy, "__gl_locking_policy");

   Queuing_Policy : Character := ' ';
   pragma Export (C, Queuing_Policy, "__gl_queuing_policy");

   Task_Dispatching_Policy : Character := ' ';
   pragma Export
     (C, Task_Dispatching_Policy, "__gl_task_dispatching_policy");

   Priority_Specific_Dispatching : System.Address := System.Null_Address;
   pragma Export
     (C, Priority_Specific_Dispatching,
      "__gl_priority_specific_dispatching");

   Num_Specific_Dispatching : Integer := 0;
   pragma Export
     (C, Num_Specific_Dispatching, "__gl_num_specific_dispatching");

   Main_CPU : Integer := -1;
   pragma Export (C, Main_CPU, "__gl_main_cpu");

   Interrupt_States : System.Address := System.Null_Address;
   pragma Export (C, Interrupt_States, "__gl_interrupt_states");

   Num_Interrupt_States : Integer := 0;
   pragma Export
     (C, Num_Interrupt_States, "__gl_num_interrupt_states");

   Unreserve_All_Interrupts : Integer := 0;
   pragma Export
     (C, Unreserve_All_Interrupts, "__gl_unreserve_all_interrupts");

   Detect_Blocking : Integer := 0;
   pragma Export (C, Detect_Blocking, "__gl_detect_blocking");

   Default_Stack_Size : Integer := -1;
   pragma Export (C, Default_Stack_Size, "__gl_default_stack_size");

   Finalize_Library_Objects : No_Param_Procedure := null;
   pragma Export
     (C, Finalize_Library_Objects, "__gnat_finalize_library_objects");

   procedure Runtime_Initialize (Install_Handler : Integer);
   pragma Export (C, Runtime_Initialize, "__gnat_runtime_initialize");

   procedure Runtime_Finalize;
   pragma Export (C, Runtime_Finalize, "__gnat_runtime_finalize");
end Flyology.Binder_Support;
