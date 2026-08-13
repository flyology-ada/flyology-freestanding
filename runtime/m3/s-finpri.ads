--  SPDX-License-Identifier: MIT OR Apache-2.0

package System.Finalization_Primitives is
   type Finalize_Address is access procedure (Object : System.Address);

   type Master_Node is limited record
      Object   : System.Address := System.Null_Address;
      Finalize : Finalize_Address := null;
      Attached : Boolean := False;
   end record;

   procedure Attach_Object_To_Node
     (Object   : System.Address;
      Finalize : Finalize_Address;
      Node     : in out Master_Node);

   procedure Finalize_Object
     (Node     : in out Master_Node;
      Finalize : Finalize_Address);
end System.Finalization_Primitives;
