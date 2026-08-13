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
   type Reason_Set is array (Reschedule_Reason) of Boolean;

   No_Reasons : constant Reason_Set := [others => False];

   function Same_Reasons (Left, Right : Reason_Set) return Boolean
   is (for all Reason in Reschedule_Reason => Left (Reason) = Right (Reason));

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
          and then
            (for all Existing in Reschedule_Reason =>
               (if Before.Reasons (Existing)
                then Post_Request'Result.Reasons (Existing)))
          and then Is_Pending (Post_Request'Result);

   type Dispatch_Snapshot is private;

   function Epoch_Of (Seen : Dispatch_Snapshot) return Request_Epoch;

   function Snapshot (State : Request_State) return Dispatch_Snapshot
   with Pre  => Is_Valid (State),
        Post => Epoch_Of (Snapshot'Result) = State.Requested;

   function Can_Acknowledge
     (Before : Request_State;
      Seen   : Dispatch_Snapshot) return Boolean;

   function Acknowledge
     (Before : Request_State;
      Seen   : Dispatch_Snapshot) return Request_State
   with Pre  => Can_Acknowledge (Before, Seen),
        Post => Is_Valid (Acknowledge'Result)
          and then Acknowledge'Result.Requested = Before.Requested
          and then Acknowledge'Result.Acknowledged = Epoch_Of (Seen)
          and then Is_Pending (Acknowledge'Result)
            = (Before.Requested /= Epoch_Of (Seen))
          and then Acknowledge'Result.Reasons = Before.Reasons;

private
   type Dispatch_Snapshot is record
      Epoch   : Request_Epoch := Request_Epoch'First;
      Reasons : Reason_Set := No_Reasons;
   end record;
end Flyology.Reschedule_Model;
