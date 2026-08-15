--  SPDX-License-Identifier: MIT OR Apache-2.0

package body Flyology.Elaboration_Probe is
   Elaborated : Boolean := False;

   function Ready return Boolean is (Elaborated);
begin
   Elaborated := True;
end Flyology.Elaboration_Probe;
