--  SPDX-License-Identifier: MIT OR Apache-2.0

package body Flyology_Freestanding.Abort_Closure_Model
  with SPARK_Mode => On
is
   function Depends_On
     (Owners   : Owner_Map;
      Child    : Task_Slot;
      Ancestor : Task_Slot) return Boolean
   is
      Current : Task_Slot := Child;
      Owner   : Owner_Slot;
   begin
      for Hop in 1 .. Task_Capacity loop
         Owner := Owners (Current);
         if Owner = No_Owner then
            return False;
         elsif Owner = Owner_Slot (Ancestor) then
            return True;
         else
            Current := Task_Slot (Owner);
         end if;
         pragma Loop_Variant (Decreases => Task_Capacity - Hop);
      end loop;
      return False;
   end Depends_On;

   function Close
     (Owners : Owner_Map;
      Named  : Selection) return Selection
   is
      Result : Selection := [others => False];
   begin
      for Subject in Task_Slot loop
         Result (Subject) := Should_Abort (Owners, Named, Subject);
         pragma Loop_Invariant
           (for all Processed in Task_Slot'First .. Subject =>
              Result (Processed) =
                Should_Abort (Owners, Named, Processed));
         pragma Loop_Invariant
           (for all Pending in Subject + 1 .. Task_Slot'Last =>
              not Result (Pending));
      end loop;
      return Result;
   end Close;
end Flyology_Freestanding.Abort_Closure_Model;
