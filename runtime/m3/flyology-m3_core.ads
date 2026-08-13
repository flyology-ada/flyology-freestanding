--  SPDX-License-Identifier: MIT OR Apache-2.0

with System;

package Flyology.M3_Core is
   procedure Initialize (CPU_Count : System.Address);

   procedure Prepare_Environment (Core : System.Address)
   with Export,
        Convention    => C,
        External_Name => "flyology_m3_prepare_environment";

   procedure Prepare_AP (Core : System.Address)
   with Export,
        Convention    => C,
        External_Name => "flyology_m3_prepare_ap";

   procedure Dispatcher_Start (Core : System.Address)
   with Export,
        Convention    => C,
        External_Name => "flyology_dispatcher_start";

   procedure Environment_Complete
   with Export,
        Convention    => C,
        External_Name => "flyology_m3_environment_complete";
end Flyology.M3_Core;
