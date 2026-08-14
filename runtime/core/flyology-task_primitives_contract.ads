--  SPDX-License-Identifier: MIT OR Apache-2.0
--
--  Internal GNARL-to-core contract.  This is not an application task API:
--  GNARL supplies task identities and owns all Ada lifecycle semantics.

with Flyology.Dispatcher_Model;

package Flyology.Task_Primitives_Contract is
   package Model renames Flyology.Dispatcher_Model;

   type Lock_Handle is range 0 .. 2 ** 31 - 1;
   No_Lock : constant Lock_Handle := Lock_Handle'First;

   type Wait_Kind is
     (Protected_Entry,
      Rendezvous,
      Delay_Wait,
      Master_Completion,
      Abort_Wakeup);

   type Wait_Token is record
      Task_Reference : Model.Task_Ref := Model.No_Task;
      Generation : Model.Generation := Model.Generation'First;
   end record;

   type Block_Result is (Blocked_And_Switched, Already_Satisfied);
   type Wake_Result is
     (Won_Before_Block, Made_Ready, Duplicate, Stale, Invalid_Future);
   type Cancellation_Result is (Cancelled, Already_Cancelled, Stale);

   type Reschedule_Reason is
     (Timer,
      Local_Ready,
      Remote_Ready,
      Priority_Change,
      Voluntary_Yield,
      Stop_Request);

   --  Enter/Leave are nestable per core.  Only the outer level owns the
   --  global RTS lock.  Interrupt ingress may acquire it only through a
   --  nonblocking try operation; failure retains the request and arranges a
   --  later local prompt instead of waiting in interrupt context.
   procedure Enter_Runtime_Critical
   with Import, Convention => Ada,
        External_Name => "flyology_enter_runtime_critical";
   procedure Leave_Runtime_Critical
   with Import, Convention => Ada,
        External_Name => "flyology_leave_runtime_critical";

   --  The caller holds the RTS lock and the synchronization-object lock.
   --  Publication, Running->Blocked, relevant-lock release, ownership
   --  removal, and dispatcher handoff form one non-preemptible operation.
   procedure Arm_Wait
     (Task_Reference : Model.Task_Ref;
      Kind  : Wait_Kind;
      Lock  : Lock_Handle;
      Token : out Wait_Token)
   with Import, Convention => Ada, External_Name => "flyology_arm_wait";

   procedure Block_Current_And_Release
     (Token  : Wait_Token;
      Lock   : Lock_Handle;
      Result : out Block_Result)
   with Import, Convention => Ada,
        External_Name => "flyology_block_current_and_release";

   procedure Make_Ready_Exact
     (Token  : Wait_Token;
      Result : out Wake_Result)
   with Import, Convention => Ada,
        External_Name => "flyology_make_ready_exact";

   procedure Change_Active_Priority
     (Task_Reference : Model.Task_Ref;
      Priority       : Model.Priority)
   with Import, Convention => Ada,
        External_Name => "flyology_change_active_priority";

   procedure Register_Deadline
     (Token        : Wait_Token;
      Deadline     : Long_Long_Integer;
      Registration : out Lock_Handle)
   with Import, Convention => Ada,
        External_Name => "flyology_register_deadline";

   procedure Cancel_Deadline
     (Token        : Wait_Token;
      Registration : Lock_Handle;
      Result       : out Cancellation_Result)
   with Import, Convention => Ada,
        External_Name => "flyology_cancel_deadline";

   procedure Request_Reschedule
     (Core   : Model.Core_Id;
      Reason : Reschedule_Reason)
   with Import, Convention => Ada,
        External_Name => "flyology_request_reschedule";
end Flyology.Task_Primitives_Contract;
