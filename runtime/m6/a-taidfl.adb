--  SPDX-License-Identifier: MIT OR Apache-2.0

package body Ada.Task_Identification.Flyology is
   function Runtime_Identity (T : Task_Id) return System.Tasking.Task_Id is
     (System.Tasking.Task_Id (T));
end Ada.Task_Identification.Flyology;
