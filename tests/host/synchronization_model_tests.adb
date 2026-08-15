--  SPDX-License-Identifier: MIT OR Apache-2.0

with Ada.Text_IO;
with Flyology_Freestanding.Abort_Closure_Model;
with Flyology_Freestanding.Allocator_Model;
with Flyology_Freestanding.Ceiling_Model;
with Flyology_Freestanding.Clock_Model;
with Flyology_Freestanding.Dispatcher_Model;
with Flyology_Freestanding.Exceptional_Completion_Model;
with Flyology_Freestanding.Priority_Queue_Model;
with Flyology_Freestanding.Task_Primitives;
with Flyology_Freestanding.Termination_Model;
with Flyology_Freestanding.Timer_Model;
with Flyology_Freestanding.Wait_Arbitration_Model;
with Flyology_Freestanding.Wait_Queue_Model;

procedure Synchronization_Model_Tests is
   package Abort_Closure renames Flyology_Freestanding.Abort_Closure_Model;
   package Allocator renames Flyology_Freestanding.Allocator_Model;
   package Ceiling renames Flyology_Freestanding.Ceiling_Model;
   package Clock renames Flyology_Freestanding.Clock_Model;
   package Dispatcher renames Flyology_Freestanding.Dispatcher_Model;
   package Completions renames Flyology_Freestanding.Exceptional_Completion_Model;
   package Priority renames Flyology_Freestanding.Priority_Queue_Model;
   package Primitives renames Flyology_Freestanding.Task_Primitives;
   package Termination renames Flyology_Freestanding.Termination_Model;
   package Timers renames Flyology_Freestanding.Timer_Model;
   package Waits renames Flyology_Freestanding.Wait_Arbitration_Model;
   package Wait_Queue renames Flyology_Freestanding.Wait_Queue_Model;

   use type Ceiling.Enter_Status;
   use type Allocator.Byte_Count;
   use type Allocator.Reservation;
   use type Ceiling.Leave_Status;
   use type Dispatcher.Generation;
   use type Dispatcher.Priority;
   use type Dispatcher.Task_Incarnation;
   use type Dispatcher.Task_Ref;
   use type Dispatcher.Task_State;
   use type Completions.Complete_Status;
   use type Completions.Completion_Phase;
   use type Completions.Consume_Status;
   use type Completions.Delivery_Action;
   use type Priority.Requeue_Status;
   use type Priority.Enqueue_Status;
   use type Termination.Dependent_Phase;
   use type Termination.Snapshot;
   use type Timers.Register_Status;
   use type Timers.Cancel_Status;
   use type Timers.Timer_Table;
   use type Wait_Queue.Enqueue_Status;
   use type Wait_Queue.Remove_Status;
   use type Wait_Queue.Wait_Queue;
   use type Waits.Arm_Status;
   use type Waits.Commit_Status;
   use type Waits.Resolve_Status;
   use type Waits.Resolution;
   use type Waits.Resume_Status;
   use type Waits.Wait_State;
   use type Clock.Nanoseconds;
   use type Clock.Tick;

   type Hash_Word is mod 2 ** 64;
   Hash  : Hash_Word := 16#CBF29CE484222325#;
   Edges : Natural := 0;

   procedure Count (Value : Integer) is
   begin
      Hash := (Hash xor Hash_Word (Value + 32_768)) * 16#100000001B3#;
      Edges := Edges + 1;
   end Count;

   function Reference
     (Slot        : Positive;
      Incarnation : Positive := 1) return Dispatcher.Task_Ref
   is ((Slot        => Dispatcher.Task_Slot (Slot),
        Incarnation => Dispatcher.Task_Incarnation (Incarnation)));

   function Candidate_Reference (Choice : Natural) return Dispatcher.Task_Ref
   is (case Choice is
          when 0      => Dispatcher.No_Task,
          when 1      => Reference (1),
          when 2      => Reference (1, 2),
          when others => Reference (2));

   procedure Check_Wait_Enumeration is
      Before : Waits.Wait_State;
   begin
      for Phase in Waits.Wait_Phase loop
         for Kind in Waits.Wait_Kind loop
            for Outcome in Waits.Resolution loop
               for Generation in Dispatcher.Generation range 0 .. 2 loop
                  Before :=
                    (Reference  => Reference (1),
                     Kind       => Kind,
                     Phase      => Phase,
                     Generation => Generation,
                     Outcome    => Outcome);
                  if Waits.Valid (Before) then
                     for Task_State in Dispatcher.Task_State loop
                        for New_Kind in Waits.Wait_Kind loop
                           declare
                              Result : constant Waits.Arm_Result :=
                                Waits.Arm (Before, Task_State, New_Kind);
                           begin
                              pragma Assert (Waits.Valid (Result.State));
                              pragma Assert
                                (Result.Status = Waits.Armed_Now
                                 or else Result.State = Before);
                              Count
                                (1_000 + Waits.Wait_Phase'Pos (Phase) * 100
                                 + Waits.Wait_Kind'Pos (New_Kind) * 10
                                 + Dispatcher.Task_State'Pos (Task_State));
                           end;
                        end loop;

                        declare
                           Result : constant Waits.Commit_Result :=
                             Waits.Commit_Block (Before, Task_State);
                        begin
                           pragma Assert (Waits.Valid (Result.State));
                           pragma Assert
                             (Result.Status /= Waits.Not_Armed
                              or else Result.State = Before);
                           Count
                             (2_000 + Waits.Wait_Phase'Pos (Phase) * 100
                              + Dispatcher.Task_State'Pos (Task_State));
                        end;

                        for Choice in 0 .. 3 loop
                           for Expected in Dispatcher.Generation range 0 .. 3
                           loop
                              for Resolution in Waits.Resolution loop
                                 declare
                                    Result : constant Waits.Resolve_Result :=
                                      Waits.Resolve
                                        (Before, Task_State,
                                         Candidate_Reference (Choice),
                                         Expected, Resolution);
                                 begin
                                    pragma Assert
                                      (Waits.Valid (Result.State));
                                    pragma Assert
                                      (Result.Status in
                                         Waits.Won_Before_Block |
                                         Waits.Made_Ready
                                       or else Result.State = Before);
                                    Count
                                      (3_000 + Choice * 100
                                       + Integer (Expected) * 10
                                       + Waits.Resolution'Pos (Resolution));
                                 end;
                              end loop;
                           end loop;
                        end loop;

                        declare
                           Result : constant Waits.Resume_Result :=
                             Waits.Resume (Before, Task_State);
                        begin
                           pragma Assert (Waits.Valid (Result.State));
                           pragma Assert
                             (Result.Status = Waits.Consumed
                              or else Result.State = Before);
                           Count
                             (4_000 + Waits.Wait_Phase'Pos (Phase) * 10
                              + Dispatcher.Task_State'Pos (Task_State));
                        end;
                     end loop;
                  end if;
               end loop;
            end loop;
         end loop;
      end loop;
   end Check_Wait_Enumeration;

   procedure Check_Allocator is
      use type Allocator.Occupancy_Map;
      type Count_Array is array (Natural range <>) of Allocator.Byte_Count;
      type Cursor_Array is array (Natural range <>) of Allocator.Byte_Offset;
      Counts : constant Count_Array :=
        [0, 1, 15, 16, 17, 65_520, 65_521, 65_536, 65_537,
         Allocator.Byte_Count'Last];
      Cursors : constant Cursor_Array := [0, 1, 16, 65_520, 65_536];
   begin
      for Cursor_Index in Cursors'Range loop
         for Count_Index in Counts'Range loop
            declare
               Result : constant Allocator.Reservation :=
                 Allocator.Reserve
                   (Cursors (Cursor_Index), Counts (Count_Index));
               Expected_Size : constant Allocator.Byte_Count :=
                 Allocator.Rounded_Size (Counts (Count_Index));
            begin
               pragma Assert
                 (Result.Accepted = Allocator.Can_Reserve
                    (Cursors (Cursor_Index), Counts (Count_Index)));
               if Allocator.Can_Reserve
                 (Cursors (Cursor_Index), Counts (Count_Index))
               then
                  pragma Assert
                    (Result.Start = Cursors (Cursor_Index)
                     and then Result.Size = Expected_Size
                     and then Result.Next = Result.Start + Expected_Size);
               else
                  pragma Assert
                    (Result.Start = Cursors (Cursor_Index)
                     and then Result.Size = 0
                     and then Result.Next = Cursors (Cursor_Index));
               end if;
               Count (900 + Cursor_Index * 20 + Count_Index);
               Count (Boolean'Pos (Result.Accepted));
               Count (Integer (Result.Start));
               Count (Integer (Result.Size));
               Count (Integer (Result.Next));
            end;
         end loop;
      end loop;
      pragma Assert
        (Allocator.Reserve (0, 0) =
           (Accepted => True, Start => 0, Size => 16, Next => 16));
      pragma Assert
        (Allocator.Reserve (0, Allocator.Capacity) =
           (Accepted => True, Start => 0, Size => Allocator.Capacity,
            Next => Allocator.Capacity));
      pragma Assert
        (Allocator.Reserve (1, 1) =
           (Accepted => False, Start => 1, Size => 0, Next => 1));
      pragma Assert
        (Allocator.Reserve (65_520, 17) =
           (Accepted => False, Start => 65_520, Size => 0, Next => 65_520));

      --  Exhaust every occupancy pattern in the first half of the bounded
      --  state model.  The unused upper half makes end-of-map fits visible,
      --  while every pattern still checks exact first-fit choice and that a
      --  matching release restores the complete prior map.
      for Bits in Natural range 0 .. 255 loop
         declare
            Used : Allocator.Occupancy_Map := [others => False];
         begin
            for Unit in Allocator.Model_Unit_Index range 0 .. 7 loop
               Used (Unit) := (Bits / (2 ** Unit)) mod 2 = 1;
            end loop;
            for Needed in Allocator.Model_Unit_Count range 1 .. 4 loop
               declare
                  Fit : constant Allocator.Fit_Result :=
                    Allocator.Find_First_Fit (Used, Needed);
               begin
                  pragma Assert
                    (if Fit.Accepted
                     then Allocator.Range_Is_Free
                       (Used, Fit.Start, Needed));
                  Count (10_000 + Bits * 10 + Needed);
                  Count (Boolean'Pos (Fit.Accepted));
                  Count (Fit.Start);
                  if Fit.Accepted then
                     declare
                        Marked : constant Allocator.Occupancy_Map :=
                          Allocator.Mark_Allocated
                            (Used, Fit.Start, Needed);
                        Restored : constant Allocator.Occupancy_Map :=
                          Allocator.Release_Range
                            (Marked, Fit.Start, Needed);
                     begin
                        pragma Assert (Restored = Used);
                        Count
                          (20_000 + Fit.Start * 10 + Needed);
                     end;
                  else
                     Count (20_999);
                  end if;
               end;
            end loop;
         end;
      end loop;
   end Check_Allocator;

   procedure Check_Winner_Orders is
      Idle : constant Waits.Wait_State :=
        (Reference => Reference (1), Kind => Waits.No_Wait,
         Phase => Waits.Idle, Generation => 0, Outcome => Waits.Pending);
   begin
      for First in Waits.Resolution range
        Waits.Object_Wake .. Waits.Abort_Wake
      loop
         for Second in Waits.Resolution range
           Waits.Object_Wake .. Waits.Abort_Wake
         loop
            declare
               Armed : constant Waits.Arm_Result :=
                 Waits.Arm (Idle, Dispatcher.Running, Waits.Timed_Object_Wait);
               Won_Early : constant Waits.Resolve_Result :=
                 Waits.Resolve
                   (Armed.State, Dispatcher.Running, Reference (1), 1, First);
               Duplicate : constant Waits.Resolve_Result :=
                 Waits.Resolve
                   (Won_Early.State, Dispatcher.Running,
                    Reference (1), 1, Second);
               Commit_Early : constant Waits.Commit_Result :=
                 Waits.Commit_Block (Won_Early.State, Dispatcher.Running);
               Committed : constant Waits.Commit_Result :=
                 Waits.Commit_Block (Armed.State, Dispatcher.Running);
               Won_Late : constant Waits.Resolve_Result :=
                 Waits.Resolve
                   (Committed.State, Dispatcher.Blocked,
                    Reference (1), 1, First);
               Duplicate_Late : constant Waits.Resolve_Result :=
                 Waits.Resolve
                   (Won_Late.State, Dispatcher.Ready,
                    Reference (1), 1, Second);
            begin
               pragma Assert (Armed.Status = Waits.Armed_Now);
               pragma Assert (Won_Early.Status = Waits.Won_Before_Block);
               pragma Assert (Won_Early.State.Outcome = First);
               pragma Assert (Duplicate.Status = Waits.Duplicate);
               pragma Assert (Duplicate.State = Won_Early.State);
               pragma Assert (Commit_Early.Status = Waits.Already_Satisfied);
               pragma Assert (Commit_Early.Outcome = First);
               pragma Assert (Committed.Status = Waits.Blocked_Now);
               pragma Assert (Won_Late.Status = Waits.Made_Ready);
               pragma Assert (Won_Late.State.Outcome = First);
               pragma Assert (Duplicate_Late.Status = Waits.Duplicate);
               pragma Assert (Duplicate_Late.State = Won_Late.State);
               Count
                 (5_000 + Waits.Resolution'Pos (First) * 10
                  + Waits.Resolution'Pos (Second));
            end;
         end loop;
      end loop;
   end Check_Winner_Orders;

   procedure Check_Exact_Queues_And_Timers is
      Queue : Wait_Queue.Wait_Queue;
      Table : Timers.Timer_Table := Timers.Empty_Table;
   begin
      for Index in 1 .. Wait_Queue.Capacity loop
         declare
            Token : constant Primitives.Wait_Token :=
              (Task_Reference => Reference (Index), Generation => 1);
            Put : constant Wait_Queue.Enqueue_Result :=
              Wait_Queue.Enqueue (Queue, Token);
            Arm : constant Timers.Register_Result :=
              Timers.Register
                (Table, Token, Timers.Tick (Wait_Queue.Capacity - Index));
         begin
            pragma Assert (Put.Status = Wait_Queue.Enqueued);
            pragma Assert (Arm.Status = Timers.Registered);
            Queue := Put.Queue;
            Table := Arm.Table;
            Count (6_000 + Index);
         end;
      end loop;
      pragma Assert
        (Wait_Queue.Enqueue
           (Queue, (Reference (1), 2)).Status =
             Wait_Queue.Duplicate_Task);
      pragma Assert
        (Timers.Register
           (Table, (Reference (1), 2), 0).Status =
             Timers.Duplicate_Task);
      Count (6_100);

      --  Cancellation/removal must target the complete token, reject stale
      --  generations without mutation, and preserve the relative order of
      --  every surviving queue member.
      declare
         Stale_Token : constant Primitives.Wait_Token :=
           (Reference (3), 2);
         Exact_Token : constant Primitives.Wait_Token :=
           (Reference (3), 1);
         Stale_Remove : constant Wait_Queue.Remove_Result :=
           Wait_Queue.Remove_Exact (Queue, Stale_Token);
         Stale_Cancel : constant Timers.Cancel_Result :=
           Timers.Cancel (Table, Stale_Token);
         Removed : constant Wait_Queue.Remove_Result :=
           Wait_Queue.Remove_Exact (Queue, Exact_Token);
         Cancelled : constant Timers.Cancel_Result :=
           Timers.Cancel (Table, Exact_Token);
      begin
         pragma Assert (Stale_Remove.Status = Wait_Queue.Stale);
         pragma Assert (Stale_Remove.Queue = Queue);
         pragma Assert (Stale_Cancel.Status = Timers.Stale);
         pragma Assert (Stale_Cancel.Table = Table);
         pragma Assert (Removed.Status = Wait_Queue.Removed);
         pragma Assert (Cancelled.Status = Timers.Cancelled);
         pragma Assert (not Wait_Queue.Contains (Removed.Queue, Exact_Token));
         pragma Assert (not Timers.Contains (Cancelled.Table, Exact_Token));
         Queue := Removed.Queue;
         Table := Cancelled.Table;
         Count (6_101);
      end;

      for Index in 1 .. Wait_Queue.Capacity - 1 loop
         declare
            Head : constant Wait_Queue.Head_Result :=
              Wait_Queue.Take_Head (Queue);
            Due : constant Timers.Expiry_Result :=
              Timers.Take_Due
                (Table,
                 Timers.Tick
                   (if Index <= Wait_Queue.Capacity - 3
                    then Index - 1
                    else Index));
         begin
            pragma Assert (Head.Found);
            pragma Assert
              (Head.Token.Task_Reference =
                 Reference (if Index < 3 then Index else Index + 1));
            pragma Assert (Due.Found);
            pragma Assert
              (Due.Token.Task_Reference =
                 Reference
                   (if Index <= Wait_Queue.Capacity - 3
                    then Wait_Queue.Capacity - Index + 1
                    else Wait_Queue.Capacity - Index));
            Queue := Head.Queue;
            Table := Due.Table;
            Count (6_200 + Index);
         end;
      end loop;
      pragma Assert (Queue.Length = 0);
      pragma Assert (not Timers.Earliest (Table).Found);
   end Check_Exact_Queues_And_Timers;

   procedure Check_Priority_And_Ceilings is
      Queue : Priority.Ready_Queue;
      State : Ceiling.Ceiling_State;
   begin
      for Index in 1 .. Priority.Capacity loop
         declare
            Put : constant Priority.Enqueue_Result :=
              Priority.Enqueue
                (Queue,
                 (Reference => Reference (Index),
                  Priority => Dispatcher.Priority (Index mod 4),
                  Sequence => Priority.Arrival_Sequence (Index),
                  Position => Priority.At_Tail));
         begin
            pragma Assert (Put.Status = Priority.Enqueued);
            Queue := Put.Queue;
            Count (7_000 + Index);
         end;
      end loop;
      declare
         Changed : constant Priority.Requeue_Result :=
           Priority.Requeue_Priority
             (Queue,
              Reference (1),
              9,
              Priority.Arrival_Sequence (Priority.Capacity + 1));
         Choice : Priority.Selection;
      begin
         pragma Assert (Changed.Status = Priority.Requeued);
         Queue := Changed.Queue;
         Choice := Priority.Select_Next (Queue);
         pragma Assert (Choice.Found);
         pragma Assert (Choice.Item.Reference = Reference (1));
         Queue := Choice.Remainder;
         Count (7_100);
      end;
      while Queue.Length > 0 loop
         declare
            Choice : constant Priority.Selection :=
              Priority.Select_Next (Queue);
         begin
            pragma Assert (Choice.Found);
            Queue := Choice.Remainder;
            Count (7_200 + Integer (Queue.Length));
         end;
      end loop;

      State :=
        (Base => 2, Active => 2,
         Previous => [others => Dispatcher.Priority'First], Depth => 0);
      for Value in Dispatcher.Priority range 2 .. 9 loop
         declare
            Entered : constant Ceiling.Enter_Result :=
              Ceiling.Enter (State, Value);
         begin
            pragma Assert (Entered.Status = Ceiling.Entered);
            State := Entered.State;
            Count (7_300 + Integer (Value));
         end;
      end loop;
      pragma Assert
        (Ceiling.Enter (State, 10).Status = Ceiling.Stack_Full);
      pragma Assert
        (Ceiling.Enter (State, 1).Status = Ceiling.Ceiling_Violation);
      while State.Depth > 0 loop
         declare
            Left : constant Ceiling.Leave_Result := Ceiling.Leave (State);
         begin
            pragma Assert (Left.Status = Ceiling.Left);
            State := Left.State;
            Count (7_400 + Integer (State.Depth));
         end;
      end loop;
      pragma Assert (State.Active = State.Base);
   end Check_Priority_And_Ceilings;

   procedure Check_Clock is
      type Frequency_Array is array (Positive range <>) of Clock.Frequency;
      type Nanosecond_Array is array (Positive range <>) of Clock.Nanoseconds;
      Rates : constant Frequency_Array :=
        [Clock.Frequency'First, Clock.Frequency (1_000_000_000),
         Clock.Frequency'Last];
      Intervals : constant Nanosecond_Array :=
        [Clock.Nanoseconds'First, Clock.Nanoseconds (1),
         Clock.Nanoseconds (999_999_999),
         Clock.Nanoseconds (1_000_000_000)];
   begin
      for Rate of Rates loop
         for Interval of Intervals loop
            pragma Assert (Clock.Conversion_Fits (Interval, Rate));
            declare
               Converted : constant Clock.Tick :=
                 Clock.To_Ticks_Ceiling (Interval, Rate);
            begin
               pragma Assert ((Interval = 0) = (Converted = 0));
               Count
                 (8_000 + Integer (Long_Long_Integer (Rate) mod 997)
                  + Integer (Long_Long_Integer (Interval) mod 991));
            end;
         end loop;
      end loop;
      pragma Assert
        (Clock.Add_Delay (Clock.Tick'Last - 1, 1) = Clock.Tick'Last);
      pragma Assert (not Clock.Deadline_Fits (Clock.Tick'Last, 1));
      Count (8_900);
   end Check_Clock;

   procedure Check_Exceptional_Completions is
   begin
      for Phase in Completions.Completion_Phase loop
         for Kind in Completions.Completion_Kind loop
            declare
               Result : constant Completions.Complete_Result :=
                 Completions.Complete (Phase, Kind);
            begin
               pragma Assert
                 ((Phase in Completions.Queued | Completions.Accepted) =
                    (Result.Status = Completions.Completed));
               pragma Assert
                 (if Result.Status = Completions.Completed
                  then Result.Phase in
                    Completions.Completed_Normal |
                    Completions.Completed_Exceptional
                  else Result.Phase = Phase);
               Count
                 (9_000 + Completions.Completion_Phase'Pos (Phase) * 10 +
                    Completions.Completion_Kind'Pos (Kind));
            end;
         end loop;
         declare
            Result : constant Completions.Consume_Result :=
              Completions.Consume (Phase);
         begin
            pragma Assert
              ((Phase in Completions.Completed_Normal |
                 Completions.Completed_Exceptional) =
                 (Result.Status = Completions.Consumed));
            pragma Assert
              (if Result.Status = Completions.Consumed
               then Result.Phase = Completions.Free
               else Result.Phase = Phase);
            Count (9_100 + Completions.Completion_Phase'Pos (Phase));
         end;
         for Has_Identity in Boolean loop
            pragma Assert
              (Completions.Stored_Is_Valid (Phase, Has_Identity) =
                 (Has_Identity =
                    (Phase = Completions.Completed_Exceptional)));
            Count
              (9_200 + Completions.Completion_Phase'Pos (Phase) * 2 +
                 Boolean'Pos (Has_Identity));
            for Abort_Deliverable in Boolean loop
               declare
                  Action : constant Completions.Delivery_Action :=
                    Completions.Select_Delivery
                      (Has_Identity, Abort_Deliverable);
               begin
                  pragma Assert
                    (Action =
                       (if Abort_Deliverable
                        then Completions.Deliver_Abort
                        elsif Has_Identity
                        then Completions.Raise_Transferred_Exception
                        else Completions.Return_Normally));
                  Count
                    (9_300 + Boolean'Pos (Has_Identity) * 2 +
                       Boolean'Pos (Abort_Deliverable));
               end;
            end loop;
         end loop;
      end loop;
   end Check_Exceptional_Completions;

   procedure Check_Collective_Termination is
   begin
      for First in Termination.Dependent_Phase loop
         for Second in Termination.Dependent_Phase loop
            for Third in Termination.Dependent_Phase loop
               for Fourth in Termination.Dependent_Phase loop
                  declare
                     Before : constant Termination.Snapshot :=
                       [0 => First, 1 => Second, 2 => Third, 3 => Fourth,
                        others => Termination.Not_Dependent];
                     After : constant Termination.Snapshot :=
                       Termination.Select_Termination (Before);
                  begin
                     if Termination.Can_Select (Before) then
                        for Position in Termination.Slot loop
                           pragma Assert
                             (After (Position) =
                                (if Before (Position) = Termination.Waiting
                                 then Termination.Selected
                                 else Before (Position)));
                        end loop;
                     else
                        pragma Assert (After = Before);
                     end if;
                     Count (9_300 + Termination.Dependent_Phase'Pos (First));
                     Count (Termination.Dependent_Phase'Pos (Second));
                     Count (Termination.Dependent_Phase'Pos (Third));
                     Count (Termination.Dependent_Phase'Pos (Fourth));
                     Count (Boolean'Pos (Termination.Can_Select (Before)));
                     for Position in Termination.Slot loop
                        Count
                          (Termination.Dependent_Phase'Pos (After (Position)));
                     end loop;
                  end;
               end loop;
            end loop;
         end loop;
      end loop;
   end Check_Collective_Termination;

   procedure Check_Abort_Closure is
      subtype Small_Slot is Abort_Closure.Task_Slot range 0 .. 3;
   begin
      for First_Owner in Abort_Closure.Owner_Slot range 0 .. 4 loop
         for Second_Owner in Abort_Closure.Owner_Slot range 0 .. 4 loop
            for Third_Owner in Abort_Closure.Owner_Slot range 0 .. 4 loop
               for Fourth_Owner in Abort_Closure.Owner_Slot range 0 .. 4 loop
                  declare
                     Owners : Abort_Closure.Owner_Map :=
                       [others => Abort_Closure.No_Owner];
                  begin
                     Owners (0) :=
                       (if First_Owner = 4 then Abort_Closure.No_Owner
                        else First_Owner);
                     Owners (1) :=
                       (if Second_Owner = 4 then Abort_Closure.No_Owner
                        else Second_Owner);
                     Owners (2) :=
                       (if Third_Owner = 4 then Abort_Closure.No_Owner
                        else Third_Owner);
                     Owners (3) :=
                       (if Fourth_Owner = 4 then Abort_Closure.No_Owner
                        else Fourth_Owner);
                     for Named_Bits in Natural range 0 .. 15 loop
                        declare
                           Named  : Abort_Closure.Selection :=
                             [others => False];
                           Result : Abort_Closure.Selection;
                        begin
                           for Slot in Small_Slot loop
                              Named (Slot) :=
                                (Named_Bits / (2 ** Slot)) mod 2 = 1;
                           end loop;
                           Result := Abort_Closure.Close (Owners, Named);
                           for Slot in Abort_Closure.Task_Slot loop
                              pragma Assert
                                (Result (Slot) =
                                   Abort_Closure.Should_Abort
                                     (Owners, Named, Slot));
                              Count (Boolean'Pos (Result (Slot)));
                           end loop;
                           Count (Named_Bits);
                        end;
                     end loop;
                  end;
               end loop;
            end loop;
         end loop;
      end loop;
   end Check_Abort_Closure;

begin
   Check_Allocator;
   Check_Wait_Enumeration;
   Check_Winner_Orders;
   Check_Exact_Queues_And_Timers;
   Check_Priority_And_Ceilings;
   Check_Clock;
   Check_Exceptional_Completions;
   Check_Collective_Termination;
   Check_Abort_Closure;
   Ada.Text_IO.Put_Line
     ("FLYOLOGY:RTS:MODEL:PASS:EDGES" & Natural'Image (Edges) &
        ":HASH" & Hash_Word'Image (Hash));
end Synchronization_Model_Tests;
