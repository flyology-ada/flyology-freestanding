--  SPDX-License-Identifier: MIT OR Apache-2.0

with System.Tasking.Protected_Objects.Entries;

package System.Tasking.Protected_Objects.Operations is
   pragma Elaborate_Body;

   type Communication_Block is limited private;

   procedure Protected_Entry_Call
     (Object     : Entries.Protection_Entries_Access;
      Index      : Protected_Entry_Index;
      Parameters : System.Address;
      Mode       : System.Tasking.Call_Mode;
      Block      : in out Communication_Block);

   function Cancelled (Block : Communication_Block) return Boolean;

   function Protected_Count
     (Object : Entries.Protection_Entries;
      Index  : Protected_Entry_Index) return Natural;

   procedure Service_Entries (Object : Entries.Protection_Entries_Access);
   procedure Complete_Entry_Body
     (Object : Entries.Protection_Entries_Access);
   procedure Exceptional_Complete_Entry_Body
     (Object     : Entries.Protection_Entries_Access;
      Occurrence : System.Address);

private
   type Communication_Block is limited record
      Was_Cancelled : Boolean := False;
   end record;
end System.Tasking.Protected_Objects.Operations;
