--  SPDX-License-Identifier: MIT OR Apache-2.0

with System.Tasking;

package Ada.Task_Identification.Conversions is
   function To_System (Item : Task_Id) return System.Tasking.Task_Id;
end Ada.Task_Identification.Conversions;
