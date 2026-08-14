--  SPDX-License-Identifier: MIT OR Apache-2.0

package Flyology.Termination_Model
  with Pure,
       SPARK_Mode => On
is
   Task_Capacity : constant Positive := 16;
   subtype Slot is Natural range 0 .. Task_Capacity - 1;

   type Dependent_Phase is
     (Not_Dependent, Active, Waiting, Terminated, Selected);
   type Snapshot is array (Slot) of Dependent_Phase;

   function Can_Select (Before : Snapshot) return Boolean
   is ((for some Position in Slot => Before (Position) = Waiting)
       and then
         (for all Position in Slot =>
            Before (Position) in Not_Dependent | Waiting | Terminated));

   function Select_Termination (Before : Snapshot) return Snapshot
   with Post =>
     (if Can_Select (Before)
      then
        (for all Position in Slot =>
           Select_Termination'Result (Position) =
             (if Before (Position) = Waiting
              then Selected
              else Before (Position)))
      else Select_Termination'Result = Before);
end Flyology.Termination_Model;
