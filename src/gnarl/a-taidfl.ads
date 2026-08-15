--  SPDX-License-Identifier: MIT OR Apache-2.0

with System.Tasking;

package Ada.Task_Identification.Flyology is
   function Runtime_Identity (T : Task_Id) return System.Tasking.Task_Id;
end Ada.Task_Identification.Flyology;
