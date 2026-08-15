--  SPDX-License-Identifier: MIT OR Apache-2.0

pragma Task_Dispatching_Policy (Round_Robin_Within_Priorities);

with Flyology_Freestanding.Console;
with Minimal_Workers;

procedure Minimal_Kernel is
begin
   Minimal_Workers.Run;
   Flyology_Freestanding.Console.Put_Line ("OK");
end Minimal_Kernel;
