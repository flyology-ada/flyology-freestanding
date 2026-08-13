--  SPDX-License-Identifier: MIT OR Apache-2.0

package body Flyology.Wait_Arbitration_Model
  with SPARK_Mode => On
is
   function Idle_State (Before : Wait_State) return Wait_State
   is ((Reference  => Before.Reference,
        Task_State => Dispatcher.Running,
        Kind       => No_Wait,
        Phase      => Idle,
        Generation => Before.Generation,
        Outcome    => Pending));

   function Arm
     (Before : Wait_State;
      Kind   : Wait_Kind) return Arm_Result
   is
   begin
      if Before.Phase /= Idle then
         return (State => Before, Status => Already_Waiting);
      elsif Kind = No_Wait or else Before.Task_State /= Dispatcher.Running then
         return (State => Before, Status => Invalid_State);
      elsif Before.Generation = Dispatcher.Generation'Last then
         return (State => Before, Status => Generation_Exhausted);
      else
         return
           (State  =>
              (Reference  => Before.Reference,
               Task_State => Dispatcher.Running,
               Kind       => Kind,
               Phase      => Armed,
               Generation => Before.Generation + 1,
               Outcome    => Pending),
            Status => Armed_Now);
      end if;
   end Arm;

   function Commit_Block (Before : Wait_State) return Commit_Result is
   begin
      if Before.Phase = Armed then
         return
           (State   =>
              (Reference  => Before.Reference,
               Task_State => Dispatcher.Blocked,
               Kind       => Before.Kind,
               Phase      => Committed,
               Generation => Before.Generation,
               Outcome    => Pending),
            Status  => Blocked_Now,
            Outcome => Pending);
      elsif Before.Phase = Resolved
        and then Before.Task_State = Dispatcher.Running
      then
         return
           (State   => Idle_State (Before),
            Status  => Already_Satisfied,
            Outcome => Before.Outcome);
      else
         return
           (State => Before, Status => Not_Armed, Outcome => Pending);
      end if;
   end Commit_Block;

   function Resolve
     (Before     : Wait_State;
      Reference  : Dispatcher.Task_Ref;
      Generation : Dispatcher.Generation;
      Outcome    : Resolution) return Resolve_Result
   is
   begin
      if Outcome = Pending then
         return (State => Before, Status => Invalid_Resolution);
      elsif Reference.Slot = Before.Reference.Slot
        and then Reference.Incarnation > Before.Reference.Incarnation
      then
         return (State => Before, Status => Invalid_Future);
      elsif Reference /= Before.Reference
        or else Generation < Before.Generation
      then
         return (State => Before, Status => Stale);
      elsif Generation > Before.Generation then
         return (State => Before, Status => Invalid_Future);
      elsif Before.Phase = Resolved then
         return (State => Before, Status => Duplicate);
      elsif Before.Phase = Armed then
         return
           (State  =>
              (Reference  => Before.Reference,
               Task_State => Dispatcher.Running,
               Kind       => Before.Kind,
               Phase      => Resolved,
               Generation => Before.Generation,
               Outcome    => Outcome),
            Status => Won_Before_Block);
      elsif Before.Phase = Committed then
         return
           (State  =>
              (Reference  => Before.Reference,
               Task_State => Dispatcher.Ready,
               Kind       => Before.Kind,
               Phase      => Resolved,
               Generation => Before.Generation,
               Outcome    => Outcome),
            Status => Made_Ready);
      else
         return (State => Before, Status => Not_Active);
      end if;
   end Resolve;

   function Resume (Before : Wait_State) return Resume_Result is
   begin
      if Before.Phase = Resolved
        and then Before.Task_State in Dispatcher.Running | Dispatcher.Ready
      then
         return
           (State   => Idle_State (Before),
            Status  => Consumed,
            Outcome => Before.Outcome);
      else
         return
           (State => Before, Status => Not_Resolved, Outcome => Pending);
      end if;
   end Resume;
end Flyology.Wait_Arbitration_Model;
