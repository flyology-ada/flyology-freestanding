--  SPDX-License-Identifier: MIT OR Apache-2.0

package body System.Standard_Library is
   type No_Param_Procedure is access procedure;

   Finalize_Library_Objects : No_Param_Procedure
     with Import,
          Convention    => C,
          External_Name => "__gnat_finalize_library_objects";

   procedure AdaFinal is
   begin
      if Finalize_Library_Objects /= null then
         Finalize_Library_Objects.all;
         Finalize_Library_Objects := null;
      end if;
   end AdaFinal;

   procedure Abort_Undefer_Direct is
   begin
      null;
   end Abort_Undefer_Direct;
end System.Standard_Library;
