--  SPDX-License-Identifier: MIT OR Apache-2.0

with Flyology.Architecture_Context;
with Flyology.Clock_Model;
with Flyology.Interrupt_Frames;
with System;

package Flyology.Platform is
   subtype Context is Flyology.Architecture_Context.Voluntary_Context;
   subtype Interrupt_Frame is Flyology.Interrupt_Frames.Interrupt_Frame;
   subtype Tick is Flyology.Clock_Model.Tick;

   type Full_Context is record
      Frame          : Interrupt_Frame;
      Extended_State : Flyology.Interrupt_Frames.XSAVE_Area;
   end record
     with Convention => C,
          Alignment  => 64;

   for Full_Context use record
      Frame          at 0 range 0 .. 256 * 8 - 1;
      Extended_State at 256 range 0 ..
        Flyology.Interrupt_Frames.XSAVE_Capacity * 8 - 1;
   end record;
   for Full_Context'Size use
     (256 + Flyology.Interrupt_Frames.XSAVE_Capacity) * 8;

   procedure Initialize
     (Item       : out Context;
      Stack_Top  : System.Address;
      Core_Value : System.Address);

   procedure Initialize_Dispatcher
     (Item       : out Context;
      Stack_Top  : System.Address;
      Core_Value : System.Address);

   procedure Switch
     (Outgoing : access Context;
      Incoming : access Context);

   procedure Switch_To_Task
     (Outgoing : access Context;
      Incoming : access Context)
   with Import, Convention => C,
        External_Name => "flyology_context_switch_to_task";

   procedure Capture_Full_Context
     (Item   : out Full_Context;
      Source : Interrupt_Frame);

   function Interrupted_Stack (Source : Interrupt_Frame) return System.Address;

   function Validate_Environment_Stack
     (Core  : System.Address;
      Probe : System.Address) return System.Address
   with Import, Convention => C,
        External_Name => "flyology_conformance_validate_environment_stack";

   procedure Switch_To_Full
     (Outgoing : access Context;
      Incoming : access Full_Context)
   with Import, Convention => C,
        External_Name => "flyology_context_switch_to_full";

   function Read_Clock return Tick
   with Import, Convention => C,
        External_Name => "flyology_platform_read_clock";

   --  Raw foreign value.  Flyology.Kernel validates it before conversion to the
   --  constrained proof-domain frequency type.
   function Clock_Frequency return System.Address
   with Import, Convention => C,
        External_Name => "flyology_platform_clock_frequency";

   procedure Program_Timer (Deadline : Tick)
   with Import, Convention => C,
        External_Name => "flyology_platform_program_timer";

   procedure Cancel_Timer
   with Import, Convention => C,
        External_Name => "flyology_platform_cancel_timer";

   procedure Retry_Interrupt
   with Import, Convention => C,
        External_Name => "flyology_platform_retry_interrupt";
end Flyology.Platform;
