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

   procedure Accept_Trivial
     (Entry_Index : System.Tasking.Task_Entry_Index)
   is
      Parameters : System.Address;
   begin
      Flyology.M3_Runtime.Accept_Call (Entry_Index, Parameters);
      Flyology.M3_Runtime.Complete_Rendezvous;
   end Accept_Trivial;

   procedure Call_Simple
     (Target      : System.Tasking.Task_Id;
      Entry_Index : System.Tasking.Task_Entry_Index;
      Parameters  : System.Address)
   is
   begin
      Flyology.M3_Runtime.Call_Simple (Target, Entry_Index, Parameters);
   end Call_Simple;

   procedure Task_Entry_Call
     (Target      : System.Tasking.Task_Id;
      Entry_Index : System.Tasking.Task_Entry_Index;
      Parameters  : System.Address;
      Mode        : System.Tasking.Call_Modes;
      Accepted    : out Boolean)
   is
   begin
      Flyology.M3_Runtime.Task_Entry_Call
        (Target, Entry_Index, Parameters, Mode, Accepted);
   end Task_Entry_Call;

   procedure Timed_Task_Entry_Call
     (Target      : System.Tasking.Task_Id;
      Entry_Index : System.Tasking.Task_Entry_Index;
      Parameters  : System.Address;
      Timeout     : Duration;
      Mode        : Integer;
      Accepted    : out Boolean)
   is
   begin
      Flyology.M3_Runtime.Timed_Task_Entry_Call
        (Target, Entry_Index, Parameters, Timeout, Mode, Accepted);
   end Timed_Task_Entry_Call;

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

   procedure Selective_Wait
     (Alternatives : System.Tasking.Accept_List_Access;
      Mode         : System.Tasking.Select_Mode;
      Parameters   : out System.Address;
      Selected     : out System.Tasking.Select_Index)
   is
   begin
      Flyology.M3_Runtime.Selective_Wait
        (Alternatives, Mode, Parameters, Selected);
   end Selective_Wait;
end System.Tasking.Rendezvous;
