--  SPDX-License-Identifier: MIT OR Apache-2.0

with Flyology.M3_Runtime;
with Ada.Task_Identification.Conversions;

package body Ada.Dynamic_Priorities is
   procedure Set_Priority
     (Priority : System.Any_Priority;
      T        : Ada.Task_Identification.Task_Id :=
        Ada.Task_Identification.Current_Task)
   is
   begin
      Flyology.M3_Runtime.Set_Priority
        (Integer (Priority),
         Ada.Task_Identification.Conversions.To_System (T));
   end Set_Priority;

   function Get_Priority
     (T : Ada.Task_Identification.Task_Id :=
        Ada.Task_Identification.Current_Task) return System.Any_Priority
   is
     (System.Any_Priority
        (Flyology.M3_Runtime.Get_Priority
           (Ada.Task_Identification.Conversions.To_System (T))));
end Ada.Dynamic_Priorities;
