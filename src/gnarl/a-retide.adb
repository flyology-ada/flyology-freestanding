--  SPDX-License-Identifier: MIT OR Apache-2.0

with Flyology.RTS;

package body Ada.Real_Time.Delays is
   procedure Delay_Until (Deadline : Ada.Real_Time.Time) is
   begin
      Flyology.RTS.Delay_Until
        (Long_Long_Integer (Deadline));
   end Delay_Until;
end Ada.Real_Time.Delays;
