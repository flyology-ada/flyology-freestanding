--  SPDX-License-Identifier: MIT OR Apache-2.0

package System.Tasking.Rendezvous is
   procedure Accept_Call
     (Entry_Index : System.Tasking.Task_Entry_Index;
      Parameters  : out System.Address);

   procedure Call_Simple
     (Target      : System.Tasking.Task_Id;
      Entry_Index : System.Tasking.Task_Entry_Index;
      Parameters  : System.Address);

   procedure Complete_Rendezvous;
   procedure Exceptional_Complete_Rendezvous
     (Occurrence : System.Address);
end System.Tasking.Rendezvous;
