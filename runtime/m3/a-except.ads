--  SPDX-License-Identifier: MIT OR Apache-2.0

with System;

package Ada.Exceptions is
   type Exception_Id is private;
   Null_Id : constant Exception_Id;

   type Exception_Occurrence is limited private;
   type Exception_Occurrence_Access is access all Exception_Occurrence;

   function Triggered_By_Abort return Boolean;
   procedure Raise_Exception
     (E       : Exception_Id;
      Message : String := "");

private
   type Exception_Id is new System.Address;
   Null_Id : constant Exception_Id := Exception_Id (System.Null_Address);
   type Exception_Occurrence is limited null record;
end Ada.Exceptions;
