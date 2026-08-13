--  SPDX-License-Identifier: MIT OR Apache-2.0

package body System.Secondary_Stack is
   procedure SS_Allocate
     (Addr         : out System.Address;
      Storage_Size : System.Storage_Elements.Storage_Count;
      Alignment    : System.Storage_Elements.Storage_Count)
   is
      pragma Warnings
        (Off, "assignment to pass-by-copy formal may have no effect");
      pragma Warnings (Off, "raise statement may result in abnormal return");
      pragma Unreferenced (Storage_Size, Alignment);
   begin
      Addr := System.Null_Address;
      raise Storage_Error;
   end SS_Allocate;
end System.Secondary_Stack;
