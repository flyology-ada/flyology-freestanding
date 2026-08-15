--  SPDX-License-Identifier: MIT OR Apache-2.0

with Flyology_Freestanding.RTS;

package body System.Tasking.Protected_Objects.Entries is
   use type Pending_Phase;

   procedure Report_Finalization_Pass
     with Import,
          Convention    => C,
          External_Name =>
            "flyology_freestanding_conformance_report_finalization_pass";

   procedure Initialize_Protection_Entries
     (Object           : Protection_Entries_Access;
      Ceiling          : Integer;
      Enclosing_Object : System.Address;
      Queue_Limits     : Queue_Limits_Access;
      Entry_Bodies     : Protected_Entry_Body_Array_Access;
      Find_Body_Index  : Body_Index_Function)
   is
      pragma Unreferenced (Queue_Limits);
   begin
      if Object = null or else Object.Initialized
        or else Enclosing_Object = System.Null_Address
        or else Entry_Bodies = null or else Find_Body_Index = null
        or else Entry_Bodies'Length /= Integer (Object.Entry_Count)
      then
         raise Program_Error;
      end if;
      Object.Ceiling := Ceiling;
      Object.Enclosing_Object := Enclosing_Object;
      Object.Entry_Bodies := Entry_Bodies;
      Object.Find_Body_Index := Find_Body_Index;
      Object.Initialized := True;
   end Initialize_Protection_Entries;

   procedure Lock_Entries (Object : Protection_Entries_Access) is
   begin
      if Object = null or else not Object.Initialized then
         raise Program_Error;
      end if;
      Flyology_Freestanding.RTS.Protected_Enter (Object.Ceiling);
   end Lock_Entries;

   procedure Unlock_Entries (Object : Protection_Entries_Access) is
   begin
      if Object = null or else not Object.Initialized then
         raise Program_Error;
      end if;
      Flyology_Freestanding.RTS.Protected_Leave;
   end Unlock_Entries;

   overriding procedure Finalize (Object : in out Protection_Entries) is
   begin
      if Object.Initialized then
         if Object.Queue.Length /= 0 then
            raise Program_Error;
         end if;
         for Call of Object.Pending loop
            if Call.Phase /= Free then
               raise Program_Error;
            end if;
         end loop;
         Object.Initialized := False;
         Report_Finalization_Pass;
      end if;
   end Finalize;
end System.Tasking.Protected_Objects.Entries;
