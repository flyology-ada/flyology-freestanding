--  SPDX-License-Identifier: MIT OR Apache-2.0

with Flyology_Freestanding.RTS;

package body System.Soft_Links is
   use type Ada.Exceptions.Exception_Occurrence_Access;

   function Current_Occurrence return System.Address
   with Import, Convention => C,
        External_Name => "flyology_freestanding_current_exception";

   function Get_Gnat_Exception return System.Address is
     (Current_Occurrence);

   procedure Save_Current_Library_Exception
   with Import, Convention => C,
        External_Name => "flyology_freestanding_save_library_exception";

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
   Abort_Defer := Flyology_Freestanding.RTS.Abort_Defer'Access;
   Abort_Undefer := Flyology_Freestanding.RTS.Abort_Undefer'Access;
   Enter_Master := Flyology_Freestanding.RTS.Enter_Master'Access;
   Complete_Master := Flyology_Freestanding.RTS.Complete_Master'Access;
   Current_Master := Flyology_Freestanding.RTS.Current_Master'Access;
end System.Soft_Links;
