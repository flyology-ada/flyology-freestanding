--  SPDX-License-Identifier: MIT OR Apache-2.0

package Flyology_Freestanding.Console is
   --  Write one complete line to the architecture diagnostic console.  Calls
   --  from different cores are serialized; no heap allocation is performed.
   procedure Put_Line (Item : String);
end Flyology_Freestanding.Console;
