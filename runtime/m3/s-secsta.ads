--  SPDX-License-Identifier: MIT OR Apache-2.0

with System.Storage_Elements;

package System.Secondary_Stack is
   pragma Preelaborate;

   SS_Pool : Integer := 0;

   procedure SS_Allocate
     (Addr         : out System.Address;
      Storage_Size : System.Storage_Elements.Storage_Count;
      Alignment    : System.Storage_Elements.Storage_Count);
end System.Secondary_Stack;
