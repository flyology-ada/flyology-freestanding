--  SPDX-License-Identifier: MIT OR Apache-2.0

with Ada.Text_IO;
with Flyology.Clock_Model;
with Flyology.Dispatcher_Model;
with Flyology.Preemption_Model;
with Flyology.Priority_Queue_Model;

procedure Preemption_Policy_Tests is
   package Clock renames Flyology.Clock_Model;
   package Dispatcher renames Flyology.Dispatcher_Model;
   package Preemption renames Flyology.Preemption_Model;
   package Ready_Queues renames Flyology.Priority_Queue_Model;

   use type Clock.Tick;
   use type Dispatcher.Priority;
   use type Dispatcher.Task_Slot;
   use type Preemption.Policy_Kind;
   use type Preemption.Preemption_Cause;
   use type Ready_Queues.Enqueue_Status;
   use type Ready_Queues.Requeue_Status;

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

   procedure Check_Ready_Queue_Positions is
      Queue : Ready_Queues.Ready_Queue;
      Expected_Order : constant array (Positive range <>) of
        Dispatcher.Task_Slot := [5, 4, 3, 1, 2];

      procedure Put
        (Slot     : Positive;
         Priority : Dispatcher.Priority;
         Position : Ready_Queues.Queue_Position)
      is
         Result : constant Ready_Queues.Enqueue_Result :=
           Ready_Queues.Enqueue
             (Queue,
              (Reference =>
                 (Slot        => Dispatcher.Task_Slot (Slot),
                  Incarnation => 1),
               Priority  => Priority,
               Sequence  => Ready_Queues.Arrival_Sequence (Slot),
               Position  => Position));
      begin
         pragma Assert (Result.Status = Ready_Queues.Enqueued);
         Queue := Result.Queue;
         Count
           (40_000 + 100 * Slot + 10 * Integer (Priority)
            + Ready_Queues.Queue_Position'Pos (Position));
      end Put;
   begin
      Put (1, 4, Ready_Queues.At_Tail);
      Put (2, 4, Ready_Queues.At_Tail);
      Put (3, 4, Ready_Queues.At_Head);
      Put (4, 4, Ready_Queues.At_Head);
      Put (5, 5, Ready_Queues.At_Tail);

      for Expected of Expected_Order loop
         declare
            Choice : constant Ready_Queues.Selection :=
              Ready_Queues.Select_Next (Queue);
         begin
            pragma Assert (Choice.Found);
            pragma Assert (Choice.Item.Reference.Slot = Expected);
            Queue := Choice.Remainder;
            Count (41_000 + Integer (Expected));
         end;
      end loop;
      pragma Assert (Queue.Length = 0);

      Put (1, 4, Ready_Queues.At_Tail);
      Put (2, 4, Ready_Queues.At_Tail);
      declare
         Requeued : constant Ready_Queues.Requeue_Result :=
           Ready_Queues.Requeue_Priority
             (Queue,
              (Slot => 1, Incarnation => 1),
              New_Priority => 4,
              New_Sequence => 6);
         First : Ready_Queues.Selection;
         Second : Ready_Queues.Selection;
      begin
         pragma Assert (Requeued.Status = Ready_Queues.Requeued);
         Queue := Requeued.Queue;
         First := Ready_Queues.Select_Next (Queue);
         pragma Assert (First.Found and then First.Item.Reference.Slot = 2);
         Second := Ready_Queues.Select_Next (First.Remainder);
         pragma Assert (Second.Found and then Second.Item.Reference.Slot = 1);
         pragma Assert (Second.Remainder.Length = 0);
         Count (42_002);
         Count (42_001);
      end;
   end Check_Ready_Queue_Positions;

begin
   Check_Configuration;
   Check_Budgets;
   Check_Decisions;
   Check_Ready_Queue_Positions;
   Ada.Text_IO.Put_Line
     ("FLYOLOGY:PREEMPTION:POLICY_MODEL:PASS:EDGES" & Natural'Image (Edges) &
        ":HASH" & Hash_Word'Image (Hash));
end Preemption_Policy_Tests;
