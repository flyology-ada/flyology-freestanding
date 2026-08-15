--  SPDX-License-Identifier: MIT OR Apache-2.0

with System.Finalization_Root;

package Ada.Finalization is
   pragma Pure;

   type Controlled is abstract tagged private;
   pragma Preelaborable_Initialization (Controlled);
   procedure Initialize (Object : in out Controlled);
   procedure Adjust (Object : in out Controlled);
   procedure Finalize (Object : in out Controlled);

   type Limited_Controlled is abstract tagged limited private;
   pragma Preelaborable_Initialization (Limited_Controlled);
   procedure Initialize (Object : in out Limited_Controlled);
   procedure Finalize (Object : in out Limited_Controlled);

private
   package SFR renames System.Finalization_Root;

   type Controlled is abstract new SFR.Root_Controlled with null record;
   type Limited_Controlled is
     abstract new SFR.Root_Controlled with null record;
end Ada.Finalization;
