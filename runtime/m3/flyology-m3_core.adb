--  SPDX-License-Identifier: MIT OR Apache-2.0

with Flyology.M2_Architecture;

package body Flyology.M3_Core is
   package Architecture renames Flyology.M2_Architecture;
   use type System.Address;

   Max_Cores             : constant := 4;
   Dispatcher_Stack_Size : constant := 16 * 1_024;

   type Core_Number is range 0 .. Max_Cores - 1;
   type Stack_Byte is mod 2 ** 8 with Size => 8;
   type Dispatcher_Stack is array
     (Natural range 0 .. Dispatcher_Stack_Size - 1) of Stack_Byte
     with Component_Size => 8,
          Alignment      => 16;
   type Stack_Array is array (Core_Number) of aliased Dispatcher_Stack;
   type Context_Array is array (Core_Number) of aliased Architecture.Context;
   type Ready_Array is array (Core_Number) of Boolean;

   Dispatcher_Stacks   : Stack_Array;
   Dispatcher_Contexts : Context_Array;
   Bootstrap_Contexts  : Context_Array;
   Dispatcher_Ready    : Ready_Array := [others => False];
   Configured_Cores    : Core_Number := 0;
   Environment_Context : aliased Architecture.Context;

   procedure Publish_Ready
   with Import,
        Convention    => C,
        External_Name => "flyology_m3_dispatcher_ready";

   procedure Idle
   with Import,
        Convention    => C,
        External_Name => "flyology_m3_idle";

   procedure Fail
   with Import,
        Convention    => C,
        External_Name => "flyology_m2_report_failure";

   procedure Stop is
   begin
      Fail;
      loop
         null;
      end loop;
   end Stop;

   function To_Core (Raw : System.Address) return Core_Number is
   begin
      if Raw > System.Address (Configured_Cores) then
         Stop;
      end if;
      return Core_Number (Raw);
   end To_Core;

   procedure Initialize_Context (Core : Core_Number) is
      Base : constant System.Address :=
        Dispatcher_Stacks (Core) (Dispatcher_Stack'First)'Address;
   begin
      if Base > System.Address'Last - System.Address (Dispatcher_Stack_Size)
      then
         Stop;
      end if;
      Architecture.Initialize_Dispatcher
        (Dispatcher_Contexts (Core),
         Base + System.Address (Dispatcher_Stack_Size),
         System.Address (Core));
   end Initialize_Context;

   procedure Initialize (CPU_Count : System.Address) is
   begin
      if CPU_Count = 0 or else CPU_Count > Max_Cores then
         Stop;
      end if;
      Configured_Cores := Core_Number (CPU_Count - 1);
      Dispatcher_Ready := [others => False];
   end Initialize;

   procedure Prepare_Environment (Core : System.Address) is
      Dense : constant Core_Number := To_Core (Core);
   begin
      if Dense /= 0 or else Dispatcher_Ready (Dense) then
         Stop;
      end if;
      Initialize_Context (Dense);
      Dispatcher_Ready (Dense) := True;
      Publish_Ready;
   end Prepare_Environment;

   procedure Prepare_AP (Core : System.Address) is
      Dense : constant Core_Number := To_Core (Core);
   begin
      if Dense = 0 or else Dispatcher_Ready (Dense) then
         Stop;
      end if;
      Initialize_Context (Dense);
      Architecture.Switch
        (Bootstrap_Contexts (Dense)'Access,
         Dispatcher_Contexts (Dense)'Access);
      Stop;
   end Prepare_AP;

   procedure Dispatcher_Start (Core : System.Address) is
      Dense : constant Core_Number := To_Core (Core);
   begin
      if Dense /= 0 then
         if Dispatcher_Ready (Dense) then
            Stop;
         end if;
         Dispatcher_Ready (Dense) := True;
         Publish_Ready;
      elsif not Dispatcher_Ready (Dense) then
         Stop;
      end if;
      Idle;
      Stop;
   end Dispatcher_Start;

   procedure Environment_Complete is
   begin
      Architecture.Switch
        (Environment_Context'Access, Dispatcher_Contexts (0)'Access);
      Stop;
   end Environment_Complete;
end Flyology.M3_Core;
