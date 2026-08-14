--  SPDX-License-Identifier: MIT OR Apache-2.0

package body Flyology.Termination_Model
  with SPARK_Mode => On
is
   function Select_Termination (Before : Snapshot) return Snapshot is
      Result : Snapshot := Before;
   begin
      if Can_Select (Before) then
         for Position in Slot loop
            if Before (Position) = Waiting then
               Result (Position) := Selected;
            end if;
            pragma Loop_Invariant
              (for all Prior in Slot'First .. Position =>
                 Result (Prior) =
                   (if Before (Prior) = Waiting
                    then Selected
                    else Before (Prior)));
            pragma Loop_Invariant
              (for all Later in Position + 1 .. Slot'Last =>
                 Result (Later) = Before (Later));
         end loop;
      end if;
      return Result;
   end Select_Termination;
end Flyology.Termination_Model;
