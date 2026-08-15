--  SPDX-License-Identifier: MIT OR Apache-2.0

package body Ada.Exceptions is
   type C_Boolean is mod 2 ** 8
   with Convention => C;

   function Current_Is_Abort return C_Boolean
   with Import, Convention => C,
        External_Name => "flyology_freestanding_current_exception_is_abort";

   function Triggered_By_Abort return Boolean is (Current_Is_Abort /= 0);

   procedure Raise_Exception_Identity (Identity : System.Address)
   with Import,
        Convention => C,
        External_Name => "flyology_freestanding_raise_exception_identity",
        No_Return;

   procedure Raise_Exception
     (E       : Exception_Id;
      Message : String := "")
   is
      pragma Unreferenced (Message);
   begin
      Raise_Exception_Identity (System.Address (E));
   end Raise_Exception;
end Ada.Exceptions;
