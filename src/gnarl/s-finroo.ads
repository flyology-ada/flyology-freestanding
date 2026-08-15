--  SPDX-License-Identifier: MIT OR Apache-2.0

package System.Finalization_Root is
   pragma Pure;

   type Root_Controlled is abstract tagged private
   with Finalizable => [];
   pragma Preelaborable_Initialization (Root_Controlled);

   procedure Adjust (Object : in out Root_Controlled);
   procedure Finalize (Object : in out Root_Controlled);
   procedure Initialize (Object : in out Root_Controlled);

private
   type Root_Controlled is abstract tagged null record;
end System.Finalization_Root;
