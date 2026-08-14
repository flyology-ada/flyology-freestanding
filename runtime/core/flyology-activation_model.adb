--  SPDX-License-Identifier: MIT OR Apache-2.0

package body Flyology.Activation_Model
  with SPARK_Mode
is
   use type Dispatcher.Task_Incarnation;

   function Valid_Reference
     (Table : Task_Table;
      Item  : Dispatcher.Task_Ref) return Boolean is
     (Item /= Dispatcher.No_Task
      and then Item.Slot <= Task_Slot'Last
      and then Table (Task_Slot (Item.Slot)).Reference = Item);

   function Can_Create
     (Table  : Task_Table;
      Chain  : Activation_Chain;
      Slot   : Task_Slot;
      Master : Dispatcher.Task_Ref) return Boolean is
     (Table (Slot).Reference = Dispatcher.No_Task
      and then Chain.Length < Max_Tasks
      and then Valid_Reference (Table, Master)
      and then Table (Task_Slot (Master.Slot)).Dependents < Max_Tasks);

   procedure Create
     (Table     : in out Task_Table;
      Chain     : in out Activation_Chain;
      Slot      : Task_Slot;
      Home_Core : Core_Id;
      Master    : Dispatcher.Task_Ref;
      Created   : out Dispatcher.Task_Ref)
   is
      Master_Slot : constant Task_Slot := Task_Slot (Master.Slot);
   begin
      Created := (Slot => Slot, Incarnation => 1);
      Table (Slot) :=
        (Reference  => Created,
         State      => Dispatcher.Dormant,
         Home_Core  => Home_Core,
         Master     => Master,
         Dependents => 0);
      Chain.Storage (Task_Slot (Chain.Length)) := Created;
      Chain.Length := Chain.Length + 1;
      Table (Master_Slot).Dependents :=
        Table (Master_Slot).Dependents + 1;
   end Create;

   function Can_Activate
     (Table : Task_Table;
      Chain : Activation_Chain) return Boolean is
     (Chain.Length > 0
      and then Valid_Reference (Table, Chain.Storage (Task_Slot'First))
      and then
        (for all Index in Task_Slot =>
           (if Natural (Index) < Chain.Length then
              Valid_Reference (Table, Chain.Storage (Index))
              and then Table
                (Task_Slot (Chain.Storage (Index).Slot)).State =
                  Dispatcher.Dormant
              and then Valid_Reference
                (Table,
                 Table (Task_Slot (Chain.Storage (Index).Slot)).Master)
              and then Table
                (Task_Slot (Chain.Storage (Index).Slot)).Master =
                  Table
                    (Task_Slot (Chain.Storage (Task_Slot'First).Slot)).Master
              and then
                (for all Prior in Task_Slot =>
                   (if Natural (Prior) < Natural (Index)
                    then Chain.Storage (Prior) /= Chain.Storage (Index))))));

   procedure Try_Activate
     (Table : in out Task_Table;
      Chain : in out Activation_Chain;
      Activated : out Boolean)
   is
      Before : constant Task_Table := Table;
   begin
      Activated := False;
      if not Can_Activate (Table, Chain) then
         return;
      end if;
      for Index in Task_Slot loop
         if Natural (Index) < Chain.Length then
            pragma Assert (Chain.Storage (Index) /= Dispatcher.No_Task);
            pragma Assert (Chain.Storage (Index).Slot <= Task_Slot'Last);
            pragma Assert
              (Table (Task_Slot (Chain.Storage (Index).Slot)).Reference =
               Chain.Storage (Index));
            Table (Task_Slot (Chain.Storage (Index).Slot)).State :=
              Dispatcher.Ready;
         end if;
         pragma Loop_Invariant
           (for all Slot in Task_Slot =>
              Table (Slot).Reference = Before (Slot).Reference
              and then Table (Slot).Home_Core = Before (Slot).Home_Core
              and then Table (Slot).Master = Before (Slot).Master
              and then Table (Slot).Dependents = Before (Slot).Dependents);
         pragma Loop_Invariant
           (for all Processed in Task_Slot =>
              (if Processed <= Index
                 and then Natural (Processed) < Chain.Length
               then Table
                 (Task_Slot (Chain.Storage (Processed).Slot)).State =
                   Dispatcher.Ready));
      end loop;
      Chain := Empty_Chain;
      Activated := True;
   end Try_Activate;

   function Can_Begin_Retirement
     (Table : Task_Table;
      Item  : Dispatcher.Task_Ref) return Boolean is
     (Valid_Reference (Table, Item)
      and then Table (Task_Slot (Item.Slot)).State = Dispatcher.Running);

   procedure Begin_Retirement
     (Table : in out Task_Table;
      Item  : Dispatcher.Task_Ref)
   is
   begin
      Table (Task_Slot (Item.Slot)).State := Dispatcher.Retiring;
   end Begin_Retirement;

   function Can_Finish_Retirement
     (Table : Task_Table;
      Item  : Dispatcher.Task_Ref) return Boolean is
     (Valid_Reference (Table, Item)
      and then Table (Task_Slot (Item.Slot)).State = Dispatcher.Retiring
      and then Valid_Reference
        (Table, Table (Task_Slot (Item.Slot)).Master)
      and then Table (Task_Slot (Item.Slot)).Master.Slot /= Item.Slot
      and then Table
        (Task_Slot (Table (Task_Slot (Item.Slot)).Master.Slot)).Dependents > 0);

   procedure Finish_Retirement
     (Table : in out Task_Table;
      Item  : Dispatcher.Task_Ref)
   is
      Item_Slot   : constant Task_Slot := Task_Slot (Item.Slot);
      Master_Slot : constant Task_Slot :=
        Task_Slot (Table (Item_Slot).Master.Slot);
   begin
      Table (Item_Slot).State := Dispatcher.Terminated;
      Table (Master_Slot).Dependents :=
        Table (Master_Slot).Dependents - 1;
   end Finish_Retirement;

   function Can_Cancel_Dormant
     (Table : Task_Table;
      Item  : Dispatcher.Task_Ref) return Boolean is
     (Valid_Reference (Table, Item)
      and then Table (Task_Slot (Item.Slot)).State = Dispatcher.Dormant
      and then Valid_Reference
        (Table, Table (Task_Slot (Item.Slot)).Master)
      and then Table (Task_Slot (Item.Slot)).Master.Slot /= Item.Slot
      and then Table
        (Task_Slot (Table (Task_Slot (Item.Slot)).Master.Slot)).Dependents > 0);

   procedure Cancel_Dormant
     (Table : in out Task_Table;
      Item  : Dispatcher.Task_Ref)
   is
      Item_Slot   : constant Task_Slot := Task_Slot (Item.Slot);
      Master_Slot : constant Task_Slot :=
        Task_Slot (Table (Item_Slot).Master.Slot);
   begin
      Table (Item_Slot).State := Dispatcher.Terminated;
      Table (Master_Slot).Dependents :=
        Table (Master_Slot).Dependents - 1;
   end Cancel_Dormant;

   procedure Report_Activation
     (Group   : in out Group_State;
      Outcome : Activation_Outcome)
   is
   begin
      Group.Pending := Group.Pending - 1;
      Group.Any_Failed := Group.Any_Failed or else Outcome = Activation_Failed;
      Group.Wake_Ready := Group.Pending = 0;
   end Report_Activation;
end Flyology.Activation_Model;
