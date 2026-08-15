--  SPDX-License-Identifier: MIT OR Apache-2.0

with System;

package Flyology.M2_Runtime is
   procedure Initialize;

   procedure Core_Entry
   with Export,
        Convention    => C,
        External_Name => "flyology_m2_core_entry";

   procedure Task_Start (Core_Value : System.Address)
   with Export,
        Convention    => C,
        External_Name => "flyology_task_start";
end Flyology.M2_Runtime;
