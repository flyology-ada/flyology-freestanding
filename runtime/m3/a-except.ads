--  SPDX-License-Identifier: MIT OR Apache-2.0

package Ada.Exceptions is
   type Exception_Occurrence is limited private;
   type Exception_Occurrence_Access is access all Exception_Occurrence;

   function Triggered_By_Abort return Boolean;

private
   type Exception_Occurrence is limited null record;
end Ada.Exceptions;
