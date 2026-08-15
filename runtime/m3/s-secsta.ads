--  SPDX-License-Identifier: MIT OR Apache-2.0

with System.Storage_Elements;
with System.Parameters;

package System.Secondary_Stack is
   pragma Preelaborate;

   type Mark_Id is private;
   type SS_Stack (Size : System.Parameters.Size_Type) is
     limited private;

   SS_Pool : Integer := 0;

   function SS_Mark return Mark_Id;
   procedure SS_Release (Mark : Mark_Id);

   procedure SS_Allocate
     (Addr         : out System.Address;
      Storage_Size : System.Storage_Elements.Storage_Count;
      Alignment    : System.Storage_Elements.Storage_Count);

private
   type Mark_Id is new System.Storage_Elements.Storage_Count;
   type SS_Stack (Size : System.Parameters.Size_Type) is
     limited null record;
end System.Secondary_Stack;
