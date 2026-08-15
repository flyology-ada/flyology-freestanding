--  SPDX-License-Identifier: MIT OR Apache-2.0

package body Flyology_Freestanding.Timer_Model
  with SPARK_Mode
is
   function Register
     (Table    : Timer_Table;
      Token    : Primitives.Wait_Token;
      Deadline : Tick) return Register_Result
   is
      Result : Register_Result :=
        (Table => Table, Status => Invalid, Slot => Timer_Slot'First);
   begin
      if Token.Task_Reference = Dispatcher.No_Task
        or else Token.Generation = Dispatcher.Generation'First
      then
         return Result;
      end if;
      for Slot in Timer_Slot loop
         if Table (Slot).Active
           and then Table (Slot).Token.Task_Reference = Token.Task_Reference
         then
            Result.Status := Duplicate_Task;
            return Result;
         end if;
         pragma Loop_Invariant
           (for all Seen in Timer_Slot =>
              (if Seen <= Slot and then Table (Seen).Active
               then Table (Seen).Token.Task_Reference /=
                 Token.Task_Reference));
      end loop;
      pragma Assert (not Contains_Task (Table, Token.Task_Reference));
      for Slot in Timer_Slot loop
         if not Table (Slot).Active then
            Result.Table (Slot) :=
              (Active => True, Token => Token, Deadline => Deadline);
            Result.Status := Registered;
            Result.Slot := Slot;
            pragma Assert (Valid (Result.Table));
            return Result;
         end if;
      end loop;
      Result.Status := Full;
      return Result;
   end Register;

   function Cancel
     (Table : Timer_Table;
      Token : Primitives.Wait_Token) return Cancel_Result
   is
      Result : Cancel_Result := (Table => Table, Status => Not_Found);
      Same_Task : Boolean := False;
   begin
      for Slot in Timer_Slot loop
         if Table (Slot).Active
           and then Table (Slot).Token.Task_Reference = Token.Task_Reference
         then
            Same_Task := True;
            if Table (Slot).Token = Token then
               Result.Table (Slot) := (others => <>);
               Result.Status := Cancelled;
               return Result;
            end if;
         end if;
      end loop;
      if Same_Task then
         Result.Status := Stale;
      end if;
      return Result;
   end Cancel;

   function Take_Due
     (Table : Timer_Table;
      Now   : Tick) return Expiry_Result
   is
      Result : Expiry_Result :=
        (Table => Table, Found => False,
         Token => (Task_Reference => Dispatcher.No_Task,
                   Generation => Dispatcher.Generation'First));
      Chosen : Timer_Slot := Timer_Slot'First;
   begin
      for Slot in Timer_Slot loop
         if Table (Slot).Active and then Table (Slot).Deadline <= Now
           and then
             (not Result.Found
              or else Table (Slot).Deadline < Table (Chosen).Deadline
              or else
                (Table (Slot).Deadline = Table (Chosen).Deadline
                 and then Slot < Chosen))
         then
            Result.Found := True;
            Chosen := Slot;
         end if;
         pragma Loop_Invariant
           (not Result.Found or else Table (Chosen).Active);
         pragma Loop_Invariant
           (not Result.Found or else Table (Chosen).Deadline <= Now);
      end loop;
      if Result.Found then
         Result.Token := Result.Table (Chosen).Token;
         Result.Table (Chosen) := (others => <>);
      end if;
      return Result;
   end Take_Due;

   function Earliest (Table : Timer_Table) return Deadline_Result is
      Result : Deadline_Result;
   begin
      for Slot in Timer_Slot loop
         if Table (Slot).Active
           and then
             (not Result.Found
              or else Table (Slot).Deadline < Result.Deadline)
         then
            Result := (Found => True, Deadline => Table (Slot).Deadline);
         end if;
         pragma Loop_Invariant
           (not Result.Found
            or else
              (for some Seen in Timer_Slot =>
                 Seen <= Slot and then Table (Seen).Active
                 and then Table (Seen).Deadline = Result.Deadline));
         pragma Loop_Invariant
           (for all Seen in Timer_Slot =>
              (if Seen <= Slot and then Table (Seen).Active
               then Result.Found
                 and then Result.Deadline <= Table (Seen).Deadline));
      end loop;
      return Result;
   end Earliest;
end Flyology_Freestanding.Timer_Model;
