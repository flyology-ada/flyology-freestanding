--  SPDX-License-Identifier: MIT OR Apache-2.0

with Flyology.Architecture_Context;
with Flyology.Clock_Model;
with Flyology.Interrupt_Frames;
with System;

package Flyology.M2_Architecture is
   subtype Context is Flyology.Architecture_Context.Voluntary_Context;
   subtype Interrupt_Frame is Flyology.Interrupt_Frames.Interrupt_Frame;
   subtype Tick is Flyology.Clock_Model.Tick;

   type Full_Context is record
      Frame : Interrupt_Frame;
   end record
     with Convention => C,
          Alignment  => 16;

   for Full_Context use record
      Frame at 0 range 0 .. 832 * 8 - 1;
   end record;
   for Full_Context'Size use 832 * 8;

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

   procedure Capture_Full_Context
     (Item   : out Full_Context;
      Source : Interrupt_Frame);

   procedure Switch_To_Full
     (Outgoing : access Context;
      Incoming : access Full_Context)
   with Import, Convention => C,
        External_Name => "flyology_context_switch_to_full";

   function Read_Clock return Tick
   with Import, Convention => C,
        External_Name => "flyology_m4_read_clock";

   --  Raw foreign value.  Task_Core validates it before conversion to the
   --  constrained proof-domain frequency type.
   function Clock_Frequency return System.Address
   with Import, Convention => C,
        External_Name => "flyology_m4_clock_frequency";

   procedure Program_Timer (Deadline : Tick)
   with Import, Convention => C,
        External_Name => "flyology_m4_program_timer";

   procedure Cancel_Timer
   with Import, Convention => C,
        External_Name => "flyology_m4_cancel_timer";
end Flyology.M2_Architecture;
