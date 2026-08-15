--  SPDX-License-Identifier: MIT OR Apache-2.0

package System.Tasking.Protected_Objects is
   type Protected_Entry_Index is range 0 .. Integer'Last;

   type Protection is limited record
      Ceiling : Integer := System.Tasking.Unspecified_Priority;
   end record;
   type Protection_Access is access all Protection;

   procedure Initialize_Protection
     (Object  : Protection_Access;
      Ceiling : Integer);
   procedure Finalize_Protection (Object : in out Protection);
   procedure Lock (Object : Protection_Access);
   procedure Lock_Read_Only (Object : Protection_Access);
   procedure Unlock (Object : Protection_Access);
end System.Tasking.Protected_Objects;
