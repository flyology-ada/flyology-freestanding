--  SPDX-License-Identifier: MIT OR Apache-2.0

package body Flyology_Freestanding.Reschedule_Model
  with SPARK_Mode => On
is
   function Epoch_Of (Seen : Dispatch_Snapshot) return Request_Epoch is
     (Seen.Epoch);

   function Can_Acknowledge
     (Before : Request_State;
      Seen   : Dispatch_Snapshot) return Boolean
   is (Is_Valid (Before)
       and then Seen.Epoch <= Before.Requested
       and then Seen.Epoch >= Before.Acknowledged
       and then
         (Seen.Epoch /= Before.Requested
          or else Same_Reasons (Seen.Reasons, Before.Reasons)));

   function Post_Request
     (Before : Request_State;
      Reason : Reschedule_Reason) return Request_State
   is
      Result : Request_State := Before;
   begin
      Result.Requested := Before.Requested + 1;
      Result.Reasons (Reason) := True;
      return Result;
   end Post_Request;

   function Snapshot (State : Request_State) return Dispatch_Snapshot is
   begin
      return (Epoch => State.Requested, Reasons => State.Reasons);
   end Snapshot;

   function Acknowledge
     (Before : Request_State;
      Seen   : Dispatch_Snapshot) return Request_State
   is
   begin
      return
        (Requested    => Before.Requested,
         Acknowledged => Seen.Epoch,
         Reasons      => Before.Reasons);
   end Acknowledge;
end Flyology_Freestanding.Reschedule_Model;
