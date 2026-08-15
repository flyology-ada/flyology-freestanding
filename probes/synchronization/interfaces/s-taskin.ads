package System.Tasking is
   pragma Preelaborate;
   type Ada_Task_Control_Block is limited private;
   type Task_Id is access all Ada_Task_Control_Block;
   type Task_Procedure_Access is access procedure (Argument : Address);
   type Boolean_Access is access all Boolean;
   Null_Task : constant Task_Id := null;
   Unspecified_Priority : constant Integer := -1;
   Unspecified_CPU : constant Integer := -1;
   type Activation_Chain is limited private;
   type Activation_Chain_Access is access all Activation_Chain;
   type Dispatching_Domain is limited private;
   type Dispatching_Domain_Access is access all Dispatching_Domain;
private
   type Ada_Task_Control_Block is limited record
      Dummy : Integer := 0;
   end record;
   type Activation_Chain is limited record
      Dummy : Integer := 0;
   end record;
   type Dispatching_Domain is limited record
      Dummy : Integer := 0;
   end record;
end System.Tasking;
