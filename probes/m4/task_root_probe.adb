--  SPDX-License-Identifier: MIT OR Apache-2.0

with System;
with System.Tasking;

procedure Task_Root_Probe
  (Body_Procedure : System.Tasking.Task_Procedure_Access;
   Discriminants  : System.Address)
is
begin
   Body_Procedure (Discriminants);
exception
   when others =>
      null;
end Task_Root_Probe;
