--  SPDX-License-Identifier: MIT OR Apache-2.0

with Flyology.RTS;

package body Ada.Calendar.Delays is
   procedure Delay_For (Interval : Duration) is
   begin
      Flyology.RTS.Delay_For (Interval);
   end Delay_For;
end Ada.Calendar.Delays;
