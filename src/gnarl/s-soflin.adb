--  SPDX-License-Identifier: MIT OR Apache-2.0

with Flyology.RTS;

package body System.Soft_Links is
   use type Ada.Exceptions.Exception_Occurrence_Access;

   function Current_Occurrence return System.Address
   with Import, Convention => C,
        External_Name => "flyology_current_exception";

   function Get_Gnat_Exception return System.Address is
     (Current_Occurrence);

   procedure Save_Current_Library_Exception
   with Import, Convention => C,
        External_Name => "flyology_save_library_exception";

   procedure Save_Library_Occurrence
     (Occurrence : Ada.Exceptions.Exception_Occurrence_Access)
   is
   begin
      if Occurrence /= null then
         raise Program_Error;
      end if;
      Save_Current_Library_Exception;
   end Save_Library_Occurrence;
begin
   Abort_Defer := Flyology.RTS.Abort_Defer'Access;
   Abort_Undefer := Flyology.RTS.Abort_Undefer'Access;
   Enter_Master := Flyology.RTS.Enter_Master'Access;
   Complete_Master := Flyology.RTS.Complete_Master'Access;
   Current_Master := Flyology.RTS.Current_Master'Access;
end System.Soft_Links;
