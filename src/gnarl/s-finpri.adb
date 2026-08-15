--  SPDX-License-Identifier: MIT OR Apache-2.0

package body System.Finalization_Primitives is
   procedure Attach_Object_To_Node
     (Object   : System.Address;
      Finalize : Finalize_Address;
      Node     : in out Master_Node)
   is
   begin
      if Object = System.Null_Address or else Finalize = null
        or else Node.Finalize_Address /= null
      then
         raise Program_Error;
      end if;
      Node.Object_Address := Object;
      Node.Finalize_Address := Finalize;
   end Attach_Object_To_Node;

   procedure Finalize_Object
     (Node     : in out Master_Node;
      Finalize : Finalize_Address)
   is
   begin
      if Node.Finalize_Address = null or else Finalize = null
        or else Finalize /= Node.Finalize_Address
      then
         raise Program_Error;
      end if;
      Finalize (Node.Object_Address);
      Node.Object_Address := System.Null_Address;
      Node.Finalize_Address := null;
   end Finalize_Object;
end System.Finalization_Primitives;
