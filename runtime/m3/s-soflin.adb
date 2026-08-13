--  SPDX-License-Identifier: MIT OR Apache-2.0

with Flyology.M3_Runtime;

package body System.Soft_Links is
   function Get_Gnat_Exception return System.Address is
     (System.Null_Address);
begin
   Abort_Defer := Flyology.M3_Runtime.Abort_Defer'Access;
   Abort_Undefer := Flyology.M3_Runtime.Abort_Undefer'Access;
   Enter_Master := Flyology.M3_Runtime.Enter_Master'Access;
   Complete_Master := Flyology.M3_Runtime.Complete_Master'Access;
   Current_Master := Flyology.M3_Runtime.Current_Master'Access;
end System.Soft_Links;
