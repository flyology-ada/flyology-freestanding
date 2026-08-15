--  SPDX-License-Identifier: MIT OR Apache-2.0

with Flyology.RTS;

package body Ada.Task_Identification is
   function Current_Task return Task_Id is
     (Task_Id (Flyology.RTS.Current_Task));

   function Is_Terminated (T : Task_Id) return Boolean is
     (Flyology.RTS.Is_Terminated (System.Tasking.Task_Id (T)));

   function Is_Callable (T : Task_Id) return Boolean is
     (Flyology.RTS.Is_Callable (System.Tasking.Task_Id (T)));
end Ada.Task_Identification;
