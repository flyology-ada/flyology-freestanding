--  SPDX-License-Identifier: MIT OR Apache-2.0

package body Ada.Finalization is
   procedure Initialize (Object : in out Controlled) is
      pragma Unreferenced (Object);
   begin
      null;
   end Initialize;

   procedure Adjust (Object : in out Controlled) is
      pragma Unreferenced (Object);
   begin
      null;
   end Adjust;

   procedure Finalize (Object : in out Controlled) is
      pragma Unreferenced (Object);
   begin
      null;
   end Finalize;

   procedure Initialize (Object : in out Limited_Controlled) is
      pragma Unreferenced (Object);
   begin
      null;
   end Initialize;

   procedure Finalize (Object : in out Limited_Controlled) is
      pragma Unreferenced (Object);
   begin
      null;
   end Finalize;
end Ada.Finalization;
