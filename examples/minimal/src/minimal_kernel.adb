--  SPDX-License-Identifier: MIT OR Apache-2.0

with Flyology.Console;
with Minimal_Workers;

procedure Minimal_Kernel is
begin
   Minimal_Workers.Run;
   Flyology.Console.Put_Line ("OK");
end Minimal_Kernel;
