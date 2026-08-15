--  SPDX-License-Identifier: MIT OR Apache-2.0

with System;

package Flyology.Interrupt_Checkpoint_Runtime is
   procedure Initialize;

   procedure Core_Entry
   with Export,
        Convention    => C,
        External_Name => "flyology_interrupts_core_entry";

   procedure Task_Start (Core_Value : System.Address)
   with Export,
        Convention    => C,
        External_Name => "flyology_task_start";
end Flyology.Interrupt_Checkpoint_Runtime;
