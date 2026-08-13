--  SPDX-License-Identifier: MIT OR Apache-2.0

with Flyology.Dispatcher_Model;

package Flyology.Activation_Model
  with SPARK_Mode
is
   package Dispatcher renames Flyology.Dispatcher_Model;
   use type Dispatcher.Task_Slot;
   use type Dispatcher.Task_Ref;
   use type Dispatcher.Task_State;

   Max_Tasks : constant := 16;
   subtype Task_Slot is Dispatcher.Task_Slot range 0 .. Max_Tasks - 1;
   subtype Task_Count is Natural range 0 .. Max_Tasks;
   subtype Core_Id is Natural range 0 .. 3;

   type Task_Record is record
      Reference  : Dispatcher.Task_Ref;
      State      : Dispatcher.Task_State;
      Home_Core  : Core_Id;
      Master     : Dispatcher.Task_Ref;
      Dependents : Task_Count;
   end record;

   Empty_Task : constant Task_Record :=
     (Reference  => Dispatcher.No_Task,
      State      => Dispatcher.Dormant,
      Home_Core  => 0,
      Master     => Dispatcher.No_Task,
      Dependents => 0);

   type Task_Table is array (Task_Slot) of Task_Record;
   type Chain_Storage is array (Task_Slot) of Dispatcher.Task_Ref;
   type Activation_Chain is record
      Storage : Chain_Storage;
      Length  : Task_Count;
   end record;

   Empty_Chain : constant Activation_Chain :=
     (Storage => [others => Dispatcher.No_Task], Length => 0);

   function Valid_Reference
     (Table : Task_Table;
      Item  : Dispatcher.Task_Ref) return Boolean;

   function Contains
     (Chain : Activation_Chain;
      Item  : Dispatcher.Task_Ref) return Boolean
   is (Item /= Dispatcher.No_Task
       and then
         (for some Index in Task_Slot =>
            Natural (Index) < Chain.Length
            and then Chain.Storage (Index) = Item));

   function Can_Create
     (Table  : Task_Table;
      Chain  : Activation_Chain;
      Slot   : Task_Slot;
      Master : Dispatcher.Task_Ref) return Boolean;

   procedure Create
     (Table     : in out Task_Table;
      Chain     : in out Activation_Chain;
      Slot      : Task_Slot;
      Home_Core : Core_Id;
      Master    : Dispatcher.Task_Ref;
      Created   : out Dispatcher.Task_Ref)
   with Pre => Can_Create (Table, Chain, Slot, Master),
        Post => Created = (Slot => Slot, Incarnation => 1)
          and then Table (Slot).Reference = Created
          and then Table (Slot).State = Dispatcher.Dormant
          and then Table (Slot).Home_Core = Home_Core
          and then Table (Slot).Master = Master
          and then Table (Slot).Dependents = 0
          and then Chain.Length = Chain'Old.Length + 1
          and then Chain.Storage (Task_Slot (Chain'Old.Length)) = Created
          and then Table (Task_Slot (Master.Slot)).Dependents =
            Table'Old (Task_Slot (Master.Slot)).Dependents + 1
          and then
            (for all Index in Task_Slot =>
               (if Index /= Slot
                  and then Index /= Task_Slot (Master.Slot)
                then Table (Index) = Table'Old (Index)));

   function Can_Activate
     (Table : Task_Table;
      Chain : Activation_Chain) return Boolean;

   procedure Try_Activate
     (Table : in out Task_Table;
      Chain : in out Activation_Chain;
      Activated : out Boolean)
   with Post => Activated = Can_Activate (Table'Old, Chain'Old)
          and then
            (if Activated
             then Chain = Empty_Chain
               and then
                 (for all Index in Task_Slot =>
                    Table (Index).Reference = Table'Old (Index).Reference
                    and then Table (Index).Home_Core =
                      Table'Old (Index).Home_Core
                    and then Table (Index).Master = Table'Old (Index).Master
                    and then Table (Index).Dependents =
                      Table'Old (Index).Dependents)
               and then
                 (for all Index in Task_Slot =>
                    (if Natural (Index) < Chain'Old.Length
                     then Table
                       (Task_Slot (Chain'Old.Storage (Index).Slot)).State =
                         Dispatcher.Ready))
               and then
                 (for all Index in Task_Slot =>
                    (if not Contains
                       (Chain'Old, Table'Old (Index).Reference)
                     then Table (Index).State = Table'Old (Index).State))
             else Table = Table'Old and then Chain = Chain'Old);

   function Can_Terminate
     (Table : Task_Table;
      Item  : Dispatcher.Task_Ref) return Boolean;

   procedure Complete
     (Table : in out Task_Table;
      Item  : Dispatcher.Task_Ref)
   with Pre => Can_Terminate (Table, Item),
        Post => Table (Task_Slot (Item.Slot)).Reference = Item
          and then Table (Task_Slot (Item.Slot)).State =
            Dispatcher.Terminated
          and then Table (Task_Slot (Item.Slot)).Home_Core =
            Table'Old (Task_Slot (Item.Slot)).Home_Core
          and then Table (Task_Slot (Item.Slot)).Master =
            Table'Old (Task_Slot (Item.Slot)).Master
          and then Table (Task_Slot (Item.Slot)).Dependents =
            Table'Old (Task_Slot (Item.Slot)).Dependents
          and then Table
            (Task_Slot (Table'Old (Task_Slot (Item.Slot)).Master.Slot)).Dependents =
              Table'Old
                (Task_Slot
                   (Table'Old (Task_Slot (Item.Slot)).Master.Slot)).Dependents - 1
          and then
            (for all Index in Task_Slot =>
               (if Index /= Task_Slot (Item.Slot)
                  and then Index /= Task_Slot
                    (Table'Old (Task_Slot (Item.Slot)).Master.Slot)
                then Table (Index) = Table'Old (Index)));
end Flyology.Activation_Model;
