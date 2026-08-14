--  SPDX-License-Identifier: MIT OR Apache-2.0

package body Ada.Exceptions is
   type C_Boolean is mod 2 ** 8
   with Convention => C;

   function Current_Is_Abort return C_Boolean
   with Import, Convention => C,
        External_Name => "flyology_current_exception_is_abort";

   function Triggered_By_Abort return Boolean is (Current_Is_Abort /= 0);
end Ada.Exceptions;
