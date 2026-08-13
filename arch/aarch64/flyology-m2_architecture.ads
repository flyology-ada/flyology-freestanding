--  SPDX-License-Identifier: MIT OR Apache-2.0

with Flyology.Architecture_Context;
with Flyology.Clock_Model;
with System;

package Flyology.M2_Architecture is
   subtype Context is Flyology.Architecture_Context.Voluntary_Context;
   subtype Tick is Flyology.Clock_Model.Tick;
   subtype Frequency is Flyology.Clock_Model.Frequency;

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

   function Read_Clock return Tick
   with Import, Convention => C,
        External_Name => "flyology_m4_read_clock";

   function Clock_Frequency return Frequency
   with Import, Convention => C,
        External_Name => "flyology_m4_clock_frequency";

   procedure Program_Timer (Deadline : Tick)
   with Import, Convention => C,
        External_Name => "flyology_m4_program_timer";

   procedure Cancel_Timer
   with Import, Convention => C,
        External_Name => "flyology_m4_cancel_timer";
end Flyology.M2_Architecture;
