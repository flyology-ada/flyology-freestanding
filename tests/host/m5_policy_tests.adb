--  SPDX-License-Identifier: MIT OR Apache-2.0

with Ada.Text_IO;
with Flyology.Clock_Model;
with Flyology.Dispatcher_Model;
with Flyology.Preemption_Model;

procedure M5_Policy_Tests is
   package Clock renames Flyology.Clock_Model;
   package Dispatcher renames Flyology.Dispatcher_Model;
   package Preemption renames Flyology.Preemption_Model;

   use type Clock.Tick;
   use type Dispatcher.Priority;
   use type Preemption.Policy_Kind;
   use type Preemption.Preemption_Cause;

   type Hash_Word is mod 2 ** 64;
   Hash  : Hash_Word := 16#CBF29CE484222325#;
   Edges : Natural := 0;

   procedure Count (Value : Integer) is
   begin
      Hash := (Hash xor Hash_Word (Value + 32_768)) * 16#100000001B3#;
      Edges := Edges + 1;
   end Count;

   procedure Check_Configuration is
      Slices : constant array (Positive range <>) of
        Preemption.Binder_Time_Slice := [0, 1, 10_000, Integer'Last];
      Rates : constant array (Positive range <>) of Clock.Frequency :=
        [1, 1_000_000_000, Clock.Frequency'Last];
   begin
      for Policy in Preemption.Policy_Kind loop
         for Slice_Index in Slices'Range loop
            for Rate_Index in Rates'Range loop
               declare
                  Slice : constant Preemption.Binder_Time_Slice :=
                    Slices (Slice_Index);
                  Rate : constant Clock.Frequency := Rates (Rate_Index);
                  Valid : constant Boolean :=
                    Preemption.Configuration_Is_Valid (Policy, Slice, Rate);
               begin
                  pragma Assert
                    (Valid =
                       (if Policy = Preemption.FIFO_Within_Priorities
                        then Slice = 0
                        else Slice > 0
                          and then Clock.Conversion_Fits
                            (Preemption.Slice_Nanoseconds (Slice), Rate)));
                  Count
                    (10_000 * Preemption.Policy_Kind'Pos (Policy)
                     + 100 * Slice_Index
                     + 10 * Rate_Index
                     + Boolean'Pos (Valid));
                  if Policy = Preemption.Round_Robin_Within_Priorities
                    and then Valid
                  then
                     pragma Assert
                       (Preemption.Quantum_Ticks (Slice, Rate) > 0);
                     Count (Integer (Preemption.Quantum_Ticks (Slice, Rate) mod 997));
                  end if;
               end;
            end loop;
         end loop;
      end loop;
   end Check_Configuration;

   procedure Check_Budgets is
   begin
      for Policy in Preemption.Policy_Kind loop
         for Quantum in Clock.Tick range 1 .. 3 loop
            for Now in Clock.Tick range 0 .. 3 loop
               declare
                  Started : constant Preemption.Budget_State :=
                    Preemption.Start_Budget (Policy, Now, Quantum);
               begin
                  pragma Assert (Preemption.Valid (Started));
                  for Later in Clock.Tick range Now .. 6 loop
                     declare
                        Accounted : constant Preemption.Budget_State :=
                          Preemption.Account (Started, Later);
                        Resumed : constant Preemption.Budget_State :=
                          Preemption.Resume_Retained (Accounted, Later + 1);
                     begin
                        pragma Assert (Preemption.Valid (Accounted));
                        pragma Assert (Preemption.Valid (Resumed));
                        pragma Assert (Resumed.Remaining = Accounted.Remaining);
                        Count
                          (20_000 * Preemption.Policy_Kind'Pos (Policy)
                           + 1_000 * Integer (Quantum)
                           + 100 * Integer (Now)
                           + 10 * Integer (Later)
                           + Integer (Accounted.Remaining));
                     end;
                  end loop;
               end;
            end loop;
         end loop;
      end loop;
   end Check_Budgets;

   procedure Check_Decisions is
   begin
      for Policy in Preemption.Policy_Kind loop
         for Current in Dispatcher.Priority range 0 .. 2 loop
            for Is_Ready in Boolean loop
               for Highest in Dispatcher.Priority range 0 .. 2 loop
                  for Remaining in Clock.Tick range 0 .. 2 loop
                     for Inherited in Boolean loop
                        for Protected_Action in Boolean loop
                           declare
                              Budget : constant Preemption.Budget_State :=
                                (Armed =>
                                   Policy =
                                     Preemption.Round_Robin_Within_Priorities,
                                 Remaining =>
                                   (if Policy =
                                        Preemption.Round_Robin_Within_Priorities
                                    then Remaining
                                    else 0),
                                 Last_Accounted => 0);
                              Decision : constant Preemption.Preemption_Cause :=
                                Preemption.Decide
                                  (Policy, Current, Is_Ready, Highest, Budget,
                                   Inherited, Protected_Action);
                           begin
                              pragma Assert
                                (Decision =
                                   (if Is_Ready and then Highest > Current
                                    then Preemption.Higher_Priority_Ready
                                    elsif Policy =
                                        Preemption.Round_Robin_Within_Priorities
                                      and then Remaining = 0
                                      and then not Inherited
                                      and then not Protected_Action
                                    then Preemption.Budget_Exhausted
                                    else Preemption.Continue_Running));
                              Count
                                (30_000 * Preemption.Policy_Kind'Pos (Policy)
                                 + 3_000 * Integer (Current)
                                 + 1_000 * Boolean'Pos (Is_Ready)
                                 + 300 * Integer (Highest)
                                 + 100 * Integer (Remaining)
                                 + 10 * Boolean'Pos (Inherited)
                                 + 3 * Boolean'Pos (Protected_Action)
                                 + Preemption.Preemption_Cause'Pos (Decision));
                           end;
                        end loop;
                     end loop;
                  end loop;
               end loop;
            end loop;
         end loop;
      end loop;
   end Check_Decisions;

begin
   Check_Configuration;
   Check_Budgets;
   Check_Decisions;
   Ada.Text_IO.Put_Line
     ("FLYOLOGY:M5:POLICY_MODEL:PASS:EDGES" & Natural'Image (Edges) &
        ":HASH" & Hash_Word'Image (Hash));
end M5_Policy_Tests;
