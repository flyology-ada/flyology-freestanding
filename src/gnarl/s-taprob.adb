--  SPDX-License-Identifier: MIT OR Apache-2.0

with Flyology_Freestanding.RTS;

package body System.Tasking.Protected_Objects is
   procedure Initialize_Protection
     (Object  : Protection_Access;
      Ceiling : Integer)
   is
   begin
      if Object = null then
         raise Program_Error;
      end if;
      Object.Ceiling := Ceiling;
   end Initialize_Protection;

   procedure Finalize_Protection (Object : in out Protection) is
      pragma Unreferenced (Object);
   begin
      null;
   end Finalize_Protection;

   procedure Lock (Object : Protection_Access) is
   begin
      if Object = null then
         raise Program_Error;
      end if;
      Flyology_Freestanding.RTS.Protected_Enter (Object.Ceiling);
   end Lock;

   procedure Lock_Read_Only (Object : Protection_Access) is
   begin
      Lock (Object);
   end Lock_Read_Only;

   procedure Unlock (Object : Protection_Access) is
   begin
      if Object = null then
         raise Program_Error;
      end if;
      Flyology_Freestanding.RTS.Protected_Leave;
   end Unlock;
end System.Tasking.Protected_Objects;
