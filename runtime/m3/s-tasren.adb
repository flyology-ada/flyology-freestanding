--  SPDX-License-Identifier: MIT OR Apache-2.0

with Flyology.M3_Runtime;

package body System.Tasking.Rendezvous is
   procedure Accept_Call
     (Entry_Index : System.Tasking.Task_Entry_Index;
      Parameters  : out System.Address)
   is
   begin
      Flyology.M3_Runtime.Accept_Call (Entry_Index, Parameters);
   end Accept_Call;

   procedure Call_Simple
     (Target      : System.Tasking.Task_Id;
      Entry_Index : System.Tasking.Task_Entry_Index;
      Parameters  : System.Address)
   is
   begin
      Flyology.M3_Runtime.Call_Simple (Target, Entry_Index, Parameters);
   end Call_Simple;

   procedure Complete_Rendezvous is
   begin
      Flyology.M3_Runtime.Complete_Rendezvous;
   end Complete_Rendezvous;

   procedure Exceptional_Complete_Rendezvous
     (Occurrence : System.Address)
   is
      pragma Unreferenced (Occurrence);
   begin
      Flyology.M3_Runtime.Unsupported_Exceptional_Rendezvous;
   end Exceptional_Complete_Rendezvous;
end System.Tasking.Rendezvous;
