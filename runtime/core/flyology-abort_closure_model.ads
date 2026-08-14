--  SPDX-License-Identifier: MIT OR Apache-2.0

package Flyology.Abort_Closure_Model
  with Pure,
       SPARK_Mode => On
is
   Task_Capacity : constant Positive := 16;
   subtype Task_Slot is Natural range 0 .. Task_Capacity - 1;
   subtype Owner_Slot is Natural range 0 .. Task_Capacity;
   No_Owner : constant Owner_Slot := Task_Capacity;

   type Owner_Map is array (Task_Slot) of Owner_Slot;
   type Selection is array (Task_Slot) of Boolean;

   function Depends_On
     (Owners   : Owner_Map;
      Child    : Task_Slot;
      Ancestor : Task_Slot) return Boolean;

   function Should_Abort
     (Owners : Owner_Map;
      Named  : Selection;
      Subject : Task_Slot) return Boolean
   is (Named (Subject)
       or else
         (for some Ancestor in Task_Slot =>
            Named (Ancestor)
              and then Depends_On (Owners, Subject, Ancestor)));

   function Close
     (Owners : Owner_Map;
      Named  : Selection) return Selection
   with Post =>
     (for all Subject in Task_Slot =>
        Close'Result (Subject) = Should_Abort (Owners, Named, Subject));
end Flyology.Abort_Closure_Model;
