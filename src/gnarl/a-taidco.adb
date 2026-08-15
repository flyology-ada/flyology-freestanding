--  SPDX-License-Identifier: MIT OR Apache-2.0

package body Ada.Task_Identification.Conversions is
   function To_System (Item : Task_Id) return System.Tasking.Task_Id is
     (System.Tasking.Task_Id (Item));
end Ada.Task_Identification.Conversions;
