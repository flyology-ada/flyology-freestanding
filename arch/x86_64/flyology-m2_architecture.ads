--  SPDX-License-Identifier: MIT OR Apache-2.0

with Flyology.Architecture_Context;
with System;

package Flyology.M2_Architecture is
   subtype Context is Flyology.Architecture_Context.Voluntary_Context;

   procedure Initialize
     (Item       : out Context;
      Stack_Top  : System.Address;
      Core_Value : System.Address);

   procedure Switch
     (Outgoing : access Context;
      Incoming : access Context);
end Flyology.M2_Architecture;
