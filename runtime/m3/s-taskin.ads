--  SPDX-License-Identifier: MIT OR Apache-2.0

package System.Tasking is
   pragma Preelaborate;

   Max_Tasks : constant := 32;

   type Ada_Task_Control_Block is limited private;
   type Task_Id is access all Ada_Task_Control_Block;
   for Task_Id'Size use 64;

   type Task_Procedure_Access is access procedure (Argument : Address);
   type Boolean_Access is access all Boolean;

   Null_Task : constant Task_Id := null;
   Unspecified_Priority : constant Integer := -1;
   Unspecified_CPU : constant Integer := -1;

   type Task_Entry_Index is range 1 .. 255;
   type Call_Mode is (Simple_Call, Conditional_Call, Asynchronous_Call);
   type Select_Mode is
     (Simple_Mode, Else_Mode, Terminate_Mode, Delay_Mode);
   type Select_Index is range 0 .. 255;
   No_Rendezvous : constant Select_Index := 0;

   type Accept_Alternative is record
      Null_Body : Boolean;
      S         : Task_Entry_Index;
   end record;
   type Accept_List is array (Positive range <>) of Accept_Alternative;
   type Accept_List_Access is access all Accept_List;

   type Activation_Chain is limited private;
   type Activation_Chain_Access is access all Activation_Chain;

   type Dispatching_Domain is limited private;
   type Dispatching_Domain_Access is access all Dispatching_Domain;

   function Identity_For_Slot (Slot : Natural) return Task_Id;
   function Slot_Of (Item : Task_Id) return Natural;
   function Create_Identity
     (Execution_Slot : Natural;
      Incarnation    : Natural) return Task_Id;
   function Execution_Slot_Of (Item : Task_Id) return Natural;
   function Incarnation_Of (Item : Task_Id) return Natural;
   procedure Mark_Terminated (Item : Task_Id);
   function Identity_Is_Terminated (Item : Task_Id) return Boolean;
   function Identity_Is_Callable (Item : Task_Id) return Boolean;

private
   type Ada_Task_Control_Block is limited record
      Slot           : Natural := 0;
      Execution_Slot : Natural := 0;
      Incarnation    : Natural := 0;
      Used           : Boolean := False;
      Terminated     : Boolean := False;
   end record;

   type Task_Id_Array is array (Positive range 1 .. Max_Tasks) of Task_Id;

   type Activation_Chain is limited record
      Members : Task_Id_Array := [others => null];
      Length  : Natural range 0 .. Max_Tasks := 0;
   end record;

   type Dispatching_Domain is limited record
      Reserved : Integer := 0;
   end record;
end System.Tasking;
