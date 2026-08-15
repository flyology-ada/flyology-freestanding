--  SPDX-License-Identifier: MIT OR Apache-2.0

with Ada.Task_Identification;
with System;

package Ada.Dynamic_Priorities is
   procedure Set_Priority
     (Priority : System.Any_Priority;
      T        : Ada.Task_Identification.Task_Id :=
        Ada.Task_Identification.Current_Task);

   function Get_Priority
     (T : Ada.Task_Identification.Task_Id :=
        Ada.Task_Identification.Current_Task) return System.Any_Priority;
end Ada.Dynamic_Priorities;
