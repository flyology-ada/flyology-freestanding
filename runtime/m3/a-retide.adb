--  SPDX-License-Identifier: MIT OR Apache-2.0

with Flyology.M3_Runtime;

package body Ada.Real_Time.Delays is
   procedure Delay_Until (Deadline : Ada.Real_Time.Time) is
   begin
      Flyology.M3_Runtime.Delay_Until
        (Long_Long_Integer (Deadline));
   end Delay_Until;
end Ada.Real_Time.Delays;
