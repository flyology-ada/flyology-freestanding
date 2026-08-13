--  SPDX-License-Identifier: MIT OR Apache-2.0

package Flyology.Reschedule_Model
  with Pure,
       SPARK_Mode => On
is
   type Request_Epoch is range 0 .. 2 ** 63 - 1;

   type Reschedule_Reason is
     (Timer,
      Local_Ready,
      Remote_Ready,
      Priority_Change,
      Voluntary_Yield,
      Stop_Request);
   type Reason_Set is array (Reschedule_Reason) of Boolean
     with Pack;

   No_Reasons : constant Reason_Set := (others => False);

   type Request_State is record
      Requested    : Request_Epoch := Request_Epoch'First;
      Acknowledged : Request_Epoch := Request_Epoch'First;
      Reasons      : Reason_Set := No_Reasons;
   end record;

   function Is_Valid (State : Request_State) return Boolean
   is (State.Acknowledged <= State.Requested);

   function Is_Pending (State : Request_State) return Boolean
   is (State.Requested /= State.Acknowledged);

   function Can_Request (State : Request_State) return Boolean
   is (Is_Valid (State) and then State.Requested < Request_Epoch'Last);

   function Post_Request
     (Before : Request_State;
      Reason : Reschedule_Reason) return Request_State
   with Pre  => Can_Request (Before),
        Post => Is_Valid (Post_Request'Result)
          and then Post_Request'Result.Requested = Before.Requested + 1
          and then Post_Request'Result.Acknowledged = Before.Acknowledged
          and then Post_Request'Result.Reasons (Reason)
          and then Is_Pending (Post_Request'Result);

   type Dispatch_Snapshot is record
      Epoch   : Request_Epoch := Request_Epoch'First;
      Reasons : Reason_Set := No_Reasons;
   end record;

   function Snapshot (State : Request_State) return Dispatch_Snapshot
   with Pre  => Is_Valid (State),
        Post => Snapshot'Result.Epoch = State.Requested
          and then Snapshot'Result.Reasons = State.Reasons;

   function Acknowledge
     (Before : Request_State;
      Seen   : Dispatch_Snapshot) return Request_State
   with Pre  => Is_Valid (Before)
          and then Seen.Epoch <= Before.Requested
          and then Seen.Epoch >= Before.Acknowledged,
        Post => Is_Valid (Acknowledge'Result)
          and then Acknowledge'Result.Requested = Before.Requested
          and then Acknowledge'Result.Acknowledged = Seen.Epoch
          and then Is_Pending (Acknowledge'Result)
            = (Before.Requested /= Seen.Epoch)
          and then
            (if Before.Requested = Seen.Epoch
             then Acknowledge'Result.Reasons = No_Reasons
             else Acknowledge'Result.Reasons = Before.Reasons);
end Flyology.Reschedule_Model;
