--  SPDX-License-Identifier: MIT OR Apache-2.0

package System.Tasking.Rendezvous is
   procedure Accept_Call
     (Entry_Index : System.Tasking.Task_Entry_Index;
      Parameters  : out System.Address);

   procedure Accept_Trivial
     (Entry_Index : System.Tasking.Task_Entry_Index);

   procedure Call_Simple
     (Target      : System.Tasking.Task_Id;
      Entry_Index : System.Tasking.Task_Entry_Index;
      Parameters  : System.Address);

   procedure Task_Entry_Call
     (Target      : System.Tasking.Task_Id;
      Entry_Index : System.Tasking.Task_Entry_Index;
      Parameters  : System.Address;
      Mode        : System.Tasking.Call_Mode;
      Accepted    : out Boolean);

   procedure Timed_Task_Entry_Call
     (Target      : System.Tasking.Task_Id;
      Entry_Index : System.Tasking.Task_Entry_Index;
      Parameters  : System.Address;
      Timeout     : Duration;
      Mode        : Integer;
      Accepted    : out Boolean);

   procedure Complete_Rendezvous;
   procedure Exceptional_Complete_Rendezvous
     (Occurrence : System.Address);

   procedure Selective_Wait
     (Alternatives : System.Tasking.Accept_List_Access;
      Mode         : System.Tasking.Select_Mode;
      Parameters   : out System.Address;
      Selected     : out System.Tasking.Select_Index);
end System.Tasking.Rendezvous;
