--  SPDX-License-Identifier: MIT OR Apache-2.0

with System;

package body Flyology_Freestanding.Console is
   procedure Put_Nul_Terminated (Address : System.Address)
   with Import, Convention => C, External_Name => "flyology_freestanding_console_puts";

   procedure Put_Line (Item : String) is
      Text : aliased constant String :=
        Item & Character'Val (13) & Character'Val (10) & Character'Val (0);
   begin
      Put_Nul_Terminated (Text'Address);
   end Put_Line;
end Flyology_Freestanding.Console;
