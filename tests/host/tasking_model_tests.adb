--  SPDX-License-Identifier: MIT OR Apache-2.0

with Ada.Text_IO;
with Flyology.Activation_Model;
with Flyology.Dispatcher_Model;
with Flyology.Placement_Model;
with Flyology.Scheduler_Contract;

procedure Tasking_Model_Tests is
   package Activation renames Flyology.Activation_Model;
   package Dispatcher renames Flyology.Dispatcher_Model;
   package Placement renames Flyology.Placement_Model;
   package Scheduler renames Flyology.Scheduler_Contract;
   use type Activation.Activation_Chain;
   use type Activation.Task_Table;
   use type Dispatcher.Task_Ref;
   use type Dispatcher.Task_State;
   use type Dispatcher.Task_Slot;
   use type Placement.Ada_CPU;
   use type Placement.Core_Id;

   type Hash_Word is mod 2 ** 64;
   Hash  : Hash_Word := 16#CBF29CE484222325#;
   Edges : Natural := 0;

   procedure Count (Value : Integer) is
   begin
      Hash := (Hash xor Hash_Word (Value + 4_096)) * 16#100000001B3#;
      Edges := Edges + 1;
   end Count;

   function Reference (Slot : Natural) return Dispatcher.Task_Ref is
     (Slot        => Dispatcher.Task_Slot (Slot),
      Incarnation => Dispatcher.Task_Incarnation (Slot + 1));

   procedure Check_Placement is
   begin
      for Count_Value in Placement.Core_Count loop
         for Cursor in Placement.Core_Id loop
            for Requested in Placement.Ada_CPU loop
               declare
                  Result : constant Placement.Placement_Result :=
                    Placement.Place (Requested, Count_Value, Cursor);
                  Valid_Cursor : constant Boolean :=
                    Integer (Cursor) < Integer (Count_Value);
                  Expected : constant Boolean :=
                    Valid_Cursor
                    and then
                      (Requested in Placement.Unspecified_CPU |
                         Placement.Not_A_Specific_CPU
                       or else Requested in 1 .. Placement.Ada_CPU (Count_Value));
               begin
                  pragma Assert (Result.Accepted = Expected);
                  if Result.Accepted and then Requested > 0 then
                     pragma Assert
                       (Integer (Result.Core) = Integer (Requested) - 1);
                  elsif Result.Accepted then
                     pragma Assert (Result.Core = Cursor);
                  else
                     pragma Assert
                       (Result.Core = Cursor and Result.Next_Cursor = Cursor);
                  end if;
                  Count
                    (Integer (Requested) * 100 + Integer (Count_Value) * 10 +
                       Integer (Cursor));
               end;
            end loop;
         end loop;
      end loop;
   end Check_Placement;

   procedure Check_Transitions is
   begin
      for State in Dispatcher.Task_State loop
         for Transition in Dispatcher.Transition_Kind loop
            declare
               Result : constant Dispatcher.Transition_Attempt :=
                 Dispatcher.Try_Transition (State, Transition);
            begin
               pragma Assert
                 (Result.Accepted =
                    Dispatcher.Transition_Is_Legal (State, Transition));
               pragma Assert (Result.Accepted or else Result.State = State);
               Count
                 (Dispatcher.Task_State'Pos (State) * 10 +
                    Dispatcher.Transition_Kind'Pos (Transition));
            end;
         end loop;
      end loop;
   end Check_Transitions;

   procedure Check_Scheduler is
      Queue : Scheduler.Ready_Queue;
   begin
      for Index in 1 .. Scheduler.Queue_Capacity loop
         declare
            Item    : constant Dispatcher.Task_Ref := Reference (Index);
            Attempt : constant Scheduler.Enqueue_Attempt :=
              Scheduler.Try_Enqueue (Queue, Item);
         begin
            pragma Assert (Attempt.Accepted);
            Queue := Attempt.Queue;
            Count (Index);
         end;
      end loop;
      pragma Assert
        (not Scheduler.Try_Enqueue (Queue, Reference (1)).Accepted);
      Count (-1);
      for Index in 1 .. Scheduler.Queue_Capacity loop
         declare
            Choice : constant Scheduler.Selection :=
              Scheduler.Select_Next (Queue);
         begin
            pragma Assert (Choice.Selected = Reference (Index));
            Queue := Choice.Remainder;
            Count (-Index);
         end;
      end loop;
      pragma Assert (Queue.Length = 0);
   end Check_Scheduler;

   procedure Check_Activation is
      Table  : Activation.Task_Table := [others => Activation.Empty_Task];
      Chain  : Activation.Activation_Chain := Activation.Empty_Chain;
      Master : constant Dispatcher.Task_Ref := Reference (0);
      Created : Dispatcher.Task_Ref;
   begin
      Table (0) :=
        (Reference => Master, State => Dispatcher.Running, Home_Core => 0,
         Master => Dispatcher.No_Task, Dependents => 0);
      for Slot in Activation.Task_Slot range 1 .. Activation.Task_Slot'Last
      loop
         pragma Assert (Activation.Can_Create (Table, Chain, Slot, Master));
         Activation.Create
           (Table, Chain, Slot, Activation.Core_Id (Natural (Slot) mod 4),
            Master, Created);
         pragma Assert (Created.Slot = Slot);
         pragma Assert (Table (0).Dependents = Natural (Slot));
         Count (Natural (Slot) + 1_000);
      end loop;
      declare
         Activated : Boolean;
      begin
         Activation.Try_Activate (Table, Chain, Activated);
         pragma Assert (Activated and then Chain = Activation.Empty_Chain);
         Count (2_000);
      end;
      for Slot in Activation.Task_Slot range 1 .. Activation.Task_Slot'Last
      loop
         Table (Slot).State := Dispatcher.Running;
         declare
            Item : constant Dispatcher.Task_Ref := Table (Slot).Reference;
         begin
            Activation.Begin_Retirement (Table, Item);
            pragma Assert (Table (Slot).State = Dispatcher.Retiring);
            Activation.Finish_Retirement (Table, Item);
         end;
         pragma Assert (Table (Slot).State = Dispatcher.Terminated);
         pragma Assert
           (Table (0).Dependents =
              Natural (Activation.Task_Slot'Last) - Natural (Slot));
         Count (Natural (Slot) + 3_000);
      end loop;
      declare
         Before_Table : constant Activation.Task_Table := Table;
         Before_Chain : constant Activation.Activation_Chain := Chain;
         Activated    : Boolean;
      begin
         Activation.Try_Activate (Table, Chain, Activated);
         pragma Assert (not Activated);
         pragma Assert (Table = Before_Table and then Chain = Before_Chain);
         Count (4_000);
      end;
      declare
         Group : Activation.Group_State :=
           (Pending => 2, Any_Failed => False, Wake_Ready => False);
      begin
         Activation.Report_Activation
           (Group, Activation.Activation_Succeeded);
         pragma Assert
           (Group.Pending = 1
            and then not Group.Any_Failed
            and then not Group.Wake_Ready);
         Activation.Report_Activation
           (Group, Activation.Activation_Failed);
         pragma Assert
           (Group.Pending = 0
            and then Group.Any_Failed
            and then Group.Wake_Ready);
         Count (4_001);
      end;
      declare
         Cancel_Table : Activation.Task_Table :=
           [others => Activation.Empty_Task];
         Cancel_Chain : Activation.Activation_Chain :=
           Activation.Empty_Chain;
         Cancel_Master : constant Dispatcher.Task_Ref := Reference (0);
         Item : Dispatcher.Task_Ref;
      begin
         Cancel_Table (0) :=
           (Reference => Cancel_Master, State => Dispatcher.Running,
            Home_Core => 0, Master => Dispatcher.No_Task, Dependents => 0);
         Activation.Create
           (Cancel_Table, Cancel_Chain, 1, 1, Cancel_Master, Item);
         Cancel_Chain.Length := 2;
         Cancel_Chain.Storage (1) := Item;
         declare
            Before : constant Activation.Task_Table := Cancel_Table;
            Activated : Boolean;
         begin
            Activation.Try_Activate (Cancel_Table, Cancel_Chain, Activated);
            pragma Assert (not Activated and then Cancel_Table = Before);
         end;
         Cancel_Chain.Length := 1;
         pragma Assert (Activation.Can_Cancel_Dormant (Cancel_Table, Item));
         Activation.Cancel_Dormant (Cancel_Table, Item);
         pragma Assert
           (Cancel_Table (1).State = Dispatcher.Terminated
            and then Cancel_Table (0).Dependents = 0);
         Count (4_002);
      end;
   end Check_Activation;
begin
   Check_Placement;
   Check_Transitions;
   Check_Scheduler;
   Check_Activation;
   Ada.Text_IO.Put_Line
     ("FLYOLOGY:TASKING:MODEL:PASS:EDGES" & Natural'Image (Edges) &
        ":HASH" & Hash_Word'Image (Hash));
end Tasking_Model_Tests;
