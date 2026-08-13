--  SPDX-License-Identifier: MIT OR Apache-2.0

package body Flyology.Dispatcher_Model
  with SPARK_Mode => On
is
   function Transition_Result
     (State      : Task_State;
      Transition : Transition_Kind) return Task_State
   is
      pragma Unreferenced (State);
   begin
      return
        (case Transition is
            when Admit | Yield | Wake => Ready,
            when Dispatch             => Running,
            when Block                => Blocked,
            when Terminate_Task       => Terminated);
   end Transition_Result;

   function Begin_Wait (Before : Wait_State) return Wait_State is
   begin
      return
        (Reference  => Before.Reference,
         State      => Running,
         Phase      => Armed,
         Token      => Before.Token + 1,
         Wake_Saved => False);
   end Begin_Wait;

   function Publish_Wait (Before : Wait_State) return Wait_State is
   begin
      return
        (Reference  => Before.Reference,
         State      => (if Before.Wake_Saved then Running else Blocked),
         Phase      => (if Before.Wake_Saved then No_Wait else Committed),
         Token      => Before.Token,
         Wake_Saved => False);
   end Publish_Wait;

   function Wake_Exact
     (Before   : Wait_State;
      Reference : Task_Ref;
      Expected : Generation) return Wait_State
   is
   begin
      if Reference /= Before.Reference
        or else Expected /= Before.Token
        or else
          (not (Before.State = Running and then Before.Phase = Armed)
           and then
             not (Before.State = Blocked and then Before.Phase = Committed))
      then
         return Before;
      elsif Before.Phase = Armed then
         return
           (Reference  => Before.Reference,
            State      => Running,
            Phase      => No_Wait,
            Token      => Before.Token,
            Wake_Saved => True);
      else
         return
           (Reference  => Before.Reference,
            State      => Ready,
            Phase      => No_Wait,
            Token      => Before.Token,
            Wake_Saved => False);
      end if;
   end Wake_Exact;

   function Enter_Critical
     (Before : Preemption_State) return Preemption_State
   is
   begin
      return (Depth => Before.Depth + 1, Deferred => Before.Deferred);
   end Enter_Critical;

   function Request_Reschedule
     (Before : Preemption_State) return Preemption_State
   is
   begin
      return (Depth => Before.Depth, Deferred => True);
   end Request_Reschedule;

   function Leave_Critical
     (Before : Preemption_State) return Leave_Result
   is
   begin
      return
        (State      =>
           (Depth    => Before.Depth - 1,
            Deferred => Before.Depth > 1 and then Before.Deferred),
         Reschedule => Before.Depth = 1 and then Before.Deferred);
   end Leave_Critical;
end Flyology.Dispatcher_Model;
