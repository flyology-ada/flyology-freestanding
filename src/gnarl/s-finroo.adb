--  SPDX-License-Identifier: MIT OR Apache-2.0

package body System.Finalization_Root is
   procedure Adjust (Object : in out Root_Controlled) is
      pragma Unreferenced (Object);
   begin
      null;
   end Adjust;

   procedure Finalize (Object : in out Root_Controlled) is
      pragma Unreferenced (Object);
   begin
      null;
   end Finalize;

   procedure Initialize (Object : in out Root_Controlled) is
      pragma Unreferenced (Object);
   begin
      null;
   end Initialize;
end System.Finalization_Root;
