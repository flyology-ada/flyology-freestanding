--  SPDX-License-Identifier: MIT OR Apache-2.0

with Flyology.Dispatcher_Model;
with Flyology.Task_Primitives_Contract;
with System;

package Flyology.Task_Core is
   package Dispatcher renames Flyology.Dispatcher_Model;
   use type Dispatcher.Task_Slot;

   Max_Cores : constant := 4;
   Max_Tasks : constant := 16;

   subtype Core_Number is Natural range 0 .. Max_Cores - 1;
   subtype Task_Slot is Dispatcher.Task_Slot range 0 .. Max_Tasks - 1;
   subtype Task_Ref is Dispatcher.Task_Ref;
   subtype Task_State is Dispatcher.Task_State;
   subtype Wait_Token is Flyology.Task_Primitives_Contract.Wait_Token;

   No_Task : Task_Ref renames Dispatcher.No_Task;

   procedure Initialize (CPU_Count : Positive);
   function CPU_Count return Positive;

   procedure Register_Environment_Locked (Reference : Task_Ref);
   procedure Register_Dormant_Locked (Reference : Task_Ref);

   function Known_Locked (Reference : Task_Ref) return Boolean;
   function State_Locked (Reference : Task_Ref) return Task_State;
   function Current_Locked (Core : Core_Number) return Task_Ref;
   function Assigned_Core_Locked (Reference : Task_Ref) return Core_Number;
   function Queue_Space_Locked (Core : Core_Number) return Natural;

   procedure Activate_Locked
     (Reference : Task_Ref;
      Core      : Core_Number);

   procedure Arm_Wait_Locked
     (Reference : Task_Ref;
      Token     : out Wait_Token);

   procedure Wake_Exact_Locked
     (Token : Wait_Token;
      Core  : out Core_Number);

   procedure Block_Current_And_Release
     (Core  : Core_Number;
      Token : Wait_Token);

   procedure Terminate_Current_Locked
     (Core      : Core_Number;
      Reference : Task_Ref);

   function Current (Core : Core_Number) return Task_Ref;
   function Is_Callable (Reference : Task_Ref) return Boolean;
   function Is_Terminated (Reference : Task_Ref) return Boolean;
   function Validate_Current_Stack
     (Core  : Core_Number;
      Probe : System.Address) return Boolean;

   procedure Prepare_Environment (Core : System.Address)
   with Export, Convention => C,
        External_Name => "flyology_m3_prepare_environment";

   procedure Prepare_AP (Core : System.Address)
   with Export, Convention => C,
        External_Name => "flyology_m3_prepare_ap";

   procedure Dispatcher_Start (Core : System.Address)
   with Export, Convention => C,
        External_Name => "flyology_dispatcher_start";

   procedure Switch_To_Dispatcher
     (Core      : Core_Number;
      Reference : Task_Ref);

   procedure Environment_Complete
   with Export, Convention => C,
        External_Name => "flyology_m3_environment_complete";
end Flyology.Task_Core;
