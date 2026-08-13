--  SPDX-License-Identifier: MIT OR Apache-2.0

with Flyology.Dispatcher_Model;

package Flyology.Wait_Arbitration_Model
  with Pure,
       SPARK_Mode => On
is
   package Dispatcher renames Flyology.Dispatcher_Model;
   use type Dispatcher.Task_Ref;
   use type Dispatcher.Task_Incarnation;
   use type Dispatcher.Task_Slot;
   use type Dispatcher.Task_State;
   use type Dispatcher.Generation;

   type Wait_Kind is
     (No_Wait, Object_Wait, Delay_Wait, Timed_Object_Wait, Master_Wait,
      Activation_Wait);
   type Wait_Phase is (Idle, Armed, Committed, Resolved);
   type Resolution is (Pending, Object_Wake, Timer_Expiry, Abort_Wake);

   type Wait_State is record
      Reference  : Dispatcher.Task_Ref := Dispatcher.No_Task;
      Task_State : Dispatcher.Task_State := Dispatcher.Dormant;
      Kind       : Wait_Kind := No_Wait;
      Phase      : Wait_Phase := Idle;
      Generation : Dispatcher.Generation := Dispatcher.Generation'First;
      Outcome    : Resolution := Pending;
   end record;

   function Valid (State : Wait_State) return Boolean
   is (Dispatcher.Is_Valid_Task (State.Reference)
       and then
         (case State.Phase is
             when Idle =>
               State.Task_State = Dispatcher.Running
                 and then State.Kind = No_Wait
                 and then State.Outcome = Pending,
             when Armed =>
               State.Task_State = Dispatcher.Running
                 and then State.Kind /= No_Wait
                 and then State.Outcome = Pending
                 and then State.Generation /= Dispatcher.Generation'First,
             when Committed =>
               State.Task_State = Dispatcher.Blocked
                 and then State.Kind /= No_Wait
                 and then State.Outcome = Pending
                 and then State.Generation /= Dispatcher.Generation'First,
             when Resolved =>
               State.Task_State in Dispatcher.Running | Dispatcher.Ready
                 and then State.Kind /= No_Wait
                 and then State.Outcome /= Pending
                 and then State.Generation /= Dispatcher.Generation'First));

   type Arm_Status is (Armed_Now, Already_Waiting, Generation_Exhausted,
                       Invalid_State);
   type Arm_Result is record
      State  : Wait_State;
      Status : Arm_Status := Invalid_State;
   end record;

   function Arm
     (Before : Wait_State;
      Kind   : Wait_Kind) return Arm_Result
   with Pre => Valid (Before),
        Post => Valid (Arm'Result.State)
          and then
            (if Arm'Result.Status = Armed_Now
             then Arm'Result.State.Reference = Before.Reference
               and then Arm'Result.State.Task_State = Dispatcher.Running
               and then Arm'Result.State.Kind = Kind
               and then Arm'Result.State.Phase = Armed
               and then Arm'Result.State.Generation = Before.Generation + 1
               and then Arm'Result.State.Outcome = Pending
             else Arm'Result.State = Before);

   type Commit_Status is (Blocked_Now, Already_Satisfied, Not_Armed);
   type Commit_Result is record
      State   : Wait_State;
      Status  : Commit_Status := Not_Armed;
      Outcome : Resolution := Pending;
   end record;

   function Commit_Block (Before : Wait_State) return Commit_Result
   with Pre => Valid (Before),
        Post => Valid (Commit_Block'Result.State)
          and then
            (case Commit_Block'Result.Status is
                when Blocked_Now =>
                  Commit_Block'Result.State.Task_State = Dispatcher.Blocked
                    and then Commit_Block'Result.State.Phase = Committed
                    and then Commit_Block'Result.State.Outcome = Pending
                    and then Commit_Block'Result.Outcome = Pending,
                when Already_Satisfied =>
                  Commit_Block'Result.State.Task_State = Dispatcher.Running
                    and then Commit_Block'Result.State.Phase = Idle
                    and then Commit_Block'Result.State.Kind = No_Wait
                    and then Commit_Block'Result.State.Outcome = Pending
                    and then Commit_Block'Result.Outcome /= Pending,
                when Not_Armed => Commit_Block'Result.State = Before);

   type Resolve_Status is
     (Won_Before_Block, Made_Ready, Duplicate, Stale, Invalid_Future,
      Not_Active, Invalid_Resolution);
   type Resolve_Result is record
      State  : Wait_State;
      Status : Resolve_Status := Not_Active;
   end record;

   function Resolve
     (Before     : Wait_State;
      Reference  : Dispatcher.Task_Ref;
      Generation : Dispatcher.Generation;
      Outcome    : Resolution) return Resolve_Result
   with Pre => Valid (Before),
        Post => Valid (Resolve'Result.State)
          and then
            (if Resolve'Result.Status = Won_Before_Block
             then Resolve'Result.State.Task_State = Dispatcher.Running
               and then Resolve'Result.State.Phase = Resolved
               and then Resolve'Result.State.Outcome = Outcome
             elsif Resolve'Result.Status = Made_Ready
             then Resolve'Result.State.Task_State = Dispatcher.Ready
               and then Resolve'Result.State.Phase = Resolved
               and then Resolve'Result.State.Outcome = Outcome
             else Resolve'Result.State = Before);

   type Resume_Status is (Consumed, Not_Resolved);
   type Resume_Result is record
      State   : Wait_State;
      Status  : Resume_Status := Not_Resolved;
      Outcome : Resolution := Pending;
   end record;

   function Resume (Before : Wait_State) return Resume_Result
   with Pre => Valid (Before),
        Post => Valid (Resume'Result.State)
          and then
            (if Resume'Result.Status = Consumed
             then Resume'Result.State.Task_State = Dispatcher.Running
               and then Resume'Result.State.Phase = Idle
               and then Resume'Result.State.Kind = No_Wait
               and then Resume'Result.State.Outcome = Pending
               and then Resume'Result.Outcome /= Pending
             else Resume'Result.State = Before);
end Flyology.Wait_Arbitration_Model;
