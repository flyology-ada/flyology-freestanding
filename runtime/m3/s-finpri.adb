--  SPDX-License-Identifier: MIT OR Apache-2.0

package body System.Finalization_Primitives is
   procedure Attach_Object_To_Node
     (Object   : System.Address;
      Finalize : Finalize_Address;
      Node     : in out Master_Node)
   is
   begin
      if Object = System.Null_Address or else Finalize = null
        or else Node.Attached
      then
         raise Program_Error;
      end if;
      Node.Object := Object;
      Node.Finalize := Finalize;
      Node.Attached := True;
   end Attach_Object_To_Node;

   procedure Finalize_Object
     (Node     : in out Master_Node;
      Finalize : Finalize_Address)
   is
   begin
      if not Node.Attached or else Finalize = null
        or else Finalize /= Node.Finalize
      then
         raise Program_Error;
      end if;
      Finalize (Node.Object);
      Node.Object := System.Null_Address;
      Node.Finalize := null;
      Node.Attached := False;
   end Finalize_Object;
end System.Finalization_Primitives;
