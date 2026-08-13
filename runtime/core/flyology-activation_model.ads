--  SPDX-License-Identifier: MIT OR Apache-2.0

with Flyology.Dispatcher_Model;

package Flyology.Activation_Model
  with SPARK_Mode
is
   package Dispatcher renames Flyology.Dispatcher_Model;
   use type Dispatcher.Task_Slot;

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
   with Pre => Can_Create (Table, Chain, Slot, Master);

   function Can_Activate
     (Table : Task_Table;
      Chain : Activation_Chain) return Boolean;

   procedure Try_Activate
     (Table : in out Task_Table;
      Chain : in out Activation_Chain;
      Activated : out Boolean)
   with Post => (if Activated then Chain = Empty_Chain);

   function Can_Terminate
     (Table : Task_Table;
      Item  : Dispatcher.Task_Ref) return Boolean;

   procedure Complete
     (Table : in out Task_Table;
      Item  : Dispatcher.Task_Ref)
   with Pre => Can_Terminate (Table, Item);
end Flyology.Activation_Model;
