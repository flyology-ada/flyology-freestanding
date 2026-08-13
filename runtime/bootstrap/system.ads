--  SPDX-License-Identifier: MIT OR Apache-2.0
--
--  Clean-room minimum discovered by compiling Flyology's M0 no-op probe on
--  both pinned targets. Add declarations only when an owned probe proves
--  that a later language feature requires them.

package System is
   pragma Pure;

   type Address is mod 2 ** 64;
   for Address'Size use 64;

   Null_Address : constant Address := 0;

   type Any_Priority is range 0 .. 255;
   subtype Priority is Any_Priority range 0 .. 239;
   subtype Interrupt_Priority is Any_Priority range 240 .. 255;
   Default_Priority : constant Priority := Priority'First;
end System;
