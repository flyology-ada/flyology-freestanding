--  SPDX-License-Identifier: MIT OR Apache-2.0

separate (Flyology_Freestanding.RTS)
package body Rendezvous_Operations is
   function Allocate_Call_Locked return Call_Number is
   begin
      for Call in Call_Number loop
         if Calls (Call).Phase = Free then
            return Call;
         end if;
      end loop;
      Stop;
      return Call_Number'First;
   end Allocate_Call_Locked;

   function Allocate_Call_Sequence_Locked return Call_Sequence is
      Result : constant Call_Sequence := Next_Call_Sequence;
   begin
      if Result = No_Call_Sequence or else Result = Call_Sequence'Last then
         Stop;
      end if;
      Next_Call_Sequence := Result + 1;
      return Result;
   end Allocate_Call_Sequence_Locked;

   function Oldest_Queued_Call_Locked
     (Server      : Dispatcher.Task_Ref;
      Entry_Index : System.Tasking.Task_Entry_Index) return Natural
   is
      Selected : Natural range 0 .. Max_Calls := 0;
      Oldest   : Call_Sequence := Call_Sequence'Last;
   begin
      for Call in Call_Number loop
         if Calls (Call).Phase = Queued
           and then Calls (Call).Target = Server
           and then Calls (Call).Entry_Index = Entry_Index
           and then Core.Wait_Is_Pending_Locked (Calls (Call).Caller_Wait)
         then
            if Calls (Call).Sequence = No_Call_Sequence then
               Stop;
            elsif Calls (Call).Sequence < Oldest then
               Selected := Natural (Call);
               Oldest := Calls (Call).Sequence;
            end if;
         end if;
      end loop;
      return Selected;
   end Oldest_Queued_Call_Locked;

   procedure Accept_Queued_Call_Locked
     (Server_Slot : Task_Slot;
      Selected    : Call_Number;
      Parameters  : out System.Address)
   is
      Cancel_Status : Core.Timer_Cancel_Status;
   begin
      if Calls (Selected).Phase /= Queued
        or else Tasks (Server_Slot).Active_Call /= 0
      then
         Stop;
      end if;
      if Calls (Selected).Timed then
         Core.Cancel_Deadline_Locked
           (Calls (Selected).Caller_Wait, Cancel_Status);
         if Cancel_Status /= Core.Cancelled then
            Stop;
         end if;
      end if;
      Calls (Selected).Phase := Accepted_Call;
      Tasks (Server_Slot).Active_Call := Natural (Selected);
      Tasks (Server_Slot).Accepting := False;
      Tasks (Server_Slot).Terminate_Open := False;
      Parameters := Calls (Selected).Parameters;
   end Accept_Queued_Call_Locked;

   procedure Consume_Call_Completion
     (Call     : Call_Number;
      Caller   : Dispatcher.Task_Ref)
   is
      Identity : System.Address;
      Consumed : Completions.Consume_Result;
   begin
      Enter_Kernel;
      if Calls (Call).Caller /= Caller
        or else Core.Current_Locked (Core_Of_Current) /= Caller
        or else Calls (Call).Phase not in
          Completed_Normal | Completed_Exceptional
      then
         Leave_Kernel;
         Stop;
      end if;
      Identity := Calls (Call).Exception_Identity;
      if not Completions.Stored_Is_Valid
        (Calls (Call).Phase, Identity /= System.Null_Address)
      then
         Leave_Kernel;
         Stop;
      end if;
      Consumed := Completions.Consume (Calls (Call).Phase);
      if Consumed.Status /= Completions.Consumed
        or else Consumed.Phase /= Completions.Free
      then
         Leave_Kernel;
         Stop;
      end if;
      Calls (Call) := (others => <>);
      Leave_Kernel;
      Deliver_Completion (Identity);
   end Consume_Call_Completion;

   procedure Call_Simple
     (Target      : Task_Id;
      Entry_Index : System.Tasking.Task_Entry_Index;
      Parameters  : System.Address)
   is
      Dense       : constant Core_Number := Core_Of_Current;
      Caller      : Dispatcher.Task_Ref;
      Target_Ref  : Dispatcher.Task_Ref;
      Target_Slot : Task_Slot;
      Call        : Call_Number;
      Outcome     : Waits.Resolution;
      Status      : Waits.Resolve_Status;
      Wake_Core   : Core_Number := 0;
      Wake        : Boolean := False;
   begin
      Enter_Kernel;
      Caller := Core.Current_Locked (Dense);
      Deliver_Pending_Abort_Locked;
      Target_Slot := Record_Of (Target);
      Target_Ref := To_Reference (Target);
      if Natural (Entry_Index) > Tasks (Target_Slot).Entry_Count then
         Leave_Kernel;
         raise Program_Error;
      elsif Tasks (Target_Slot).Terminate_Selected
        or else Core.State_Locked (Target_Ref) in
          Dispatcher.Retiring | Dispatcher.Terminated
      then
         Leave_Kernel;
         Raise_Tasking_Error (System.Null_Address, 0);
      end if;
      Call := Allocate_Call_Locked;
      Calls (Call) :=
        (Phase => Queued, Timed => False, Caller => Caller,
         Sequence => Allocate_Call_Sequence_Locked,
         Target => Target_Ref, Entry_Index => Entry_Index,
         Parameters => Parameters,
         Caller_Wait =>
           (Task_Reference => Core.No_Task, Generation => 0),
         Exception_Identity => System.Null_Address);
      Core.Arm_Wait_Locked
        (Caller, Waits.Object_Wait, Calls (Call).Caller_Wait);

      if Tasks (Target_Slot).Accepting
        and then Tasks (Target_Slot).Accept_Entry = Entry_Index
        and then Tasks (Target_Slot).Active_Call = 0
      then
         Calls (Call).Phase := Accepted_Call;
         Tasks (Target_Slot).Active_Call := Natural (Call);
         Core.Resolve_Exact_Locked
           (Tasks (Target_Slot).Accept_Wait, Waits.Object_Wake,
            Status, Wake_Core);
         if Status /= Waits.Made_Ready then
            Leave_Kernel;
            Stop;
         end if;
         Wake := True;
      end if;

      if Wake then
         Kick_Core (System.Address (Wake_Core));
      else
         Kick_Core
           (System.Address (Core.Assigned_Core_Locked (Target_Ref)));
      end if;
      Core.Block_Current_And_Release
        (Dense, Calls (Call).Caller_Wait, Outcome);
      if Outcome = Waits.Abort_Wake then
         Deliver_Pending_Abort;
      elsif Outcome /= Waits.Object_Wake then
         Stop;
      end if;
      Consume_Call_Completion (Call, Caller);
   end Call_Simple;

   procedure Task_Entry_Call
     (Target      : Task_Id;
      Entry_Index : System.Tasking.Task_Entry_Index;
      Parameters  : System.Address;
      Mode        : System.Tasking.Call_Modes;
      Accepted    : out Boolean)
   is
      Dense       : constant Core_Number := Core_Of_Current;
      Caller      : Dispatcher.Task_Ref;
      Target_Ref  : Dispatcher.Task_Ref;
      Target_Slot : Task_Slot;
      Call        : Call_Number;
      Outcome     : Waits.Resolution;
      Status      : Waits.Resolve_Status;
      Wake_Core   : Core_Number := 0;
   begin
      Accepted := False;
      if Mode /= System.Tasking.Conditional_Call then
         Stop;
      end if;
      Enter_Kernel;
      Caller := Core.Current_Locked (Dense);
      Deliver_Pending_Abort_Locked;
      Target_Slot := Record_Of (Target);
      Target_Ref := To_Reference (Target);
      if Natural (Entry_Index) > Tasks (Target_Slot).Entry_Count then
         Leave_Kernel;
         raise Program_Error;
      elsif Tasks (Target_Slot).Terminate_Selected
        or else Core.State_Locked (Target_Ref) in
          Dispatcher.Retiring | Dispatcher.Terminated
      then
         Leave_Kernel;
         Raise_Tasking_Error (System.Null_Address, 0);
      end if;
      if not Tasks (Target_Slot).Accepting
        or else Tasks (Target_Slot).Accept_Entry /= Entry_Index
        or else Tasks (Target_Slot).Active_Call /= 0
      then
         Leave_Kernel;
         return;
      end if;

      Call := Allocate_Call_Locked;
      Calls (Call) :=
        (Phase => Accepted_Call, Timed => False, Caller => Caller,
         Sequence => Allocate_Call_Sequence_Locked,
         Target => Target_Ref, Entry_Index => Entry_Index,
         Parameters => Parameters,
         Caller_Wait =>
           (Task_Reference => Core.No_Task, Generation => 0),
         Exception_Identity => System.Null_Address);
      Core.Arm_Wait_Locked
        (Caller, Waits.Object_Wait, Calls (Call).Caller_Wait);
      Tasks (Target_Slot).Active_Call := Natural (Call);
      Core.Resolve_Exact_Locked
        (Tasks (Target_Slot).Accept_Wait, Waits.Object_Wake,
         Status, Wake_Core);
      if Status /= Waits.Made_Ready then
         Leave_Kernel;
         Stop;
      end if;
      Accepted := True;
      Kick_Core (System.Address (Wake_Core));
      Core.Block_Current_And_Release
        (Dense, Calls (Call).Caller_Wait, Outcome);
      if Outcome = Waits.Abort_Wake then
         Deliver_Pending_Abort;
      elsif Outcome /= Waits.Object_Wake then
         Stop;
      end if;
      Consume_Call_Completion (Call, Caller);
   end Task_Entry_Call;

   procedure Timed_Task_Entry_Call
     (Target      : Task_Id;
      Entry_Index : System.Tasking.Task_Entry_Index;
      Parameters  : System.Address;
      Timeout     : Duration;
      Mode        : Integer;
      Accepted    : out Boolean)
   is
      Dense       : constant Core_Number := Core_Of_Current;
      Caller      : Dispatcher.Task_Ref;
      Target_Ref  : Dispatcher.Task_Ref;
      Target_Slot : Task_Slot;
      Call        : Call_Number;
      Caller_Wait : Core.Wait_Token;
      Outcome     : Waits.Resolution;
      Status      : Waits.Resolve_Status;
      Wake_Core   : Core_Number := 0;
      Tick_Count  : Clock.Tick;
      Deadline    : Clock.Tick;
      Rate        : Clock.Frequency;
      Nanoseconds : Long_Long_Integer;
   begin
      Accepted := False;
      if Mode /= 0 then
         Stop;
      elsif Timeout <= 0.0 then
         return;
      end if;
      if Timeout > Duration (Long_Long_Integer'Last / 1_000_000_000) then
         raise Storage_Error;
      end if;
      Nanoseconds := Long_Long_Integer (Timeout * 1_000_000_000) + 1;
      Rate := Clock.Frequency (Core.Clock_Frequency);
      if Nanoseconds <= 0
        or else Nanoseconds > Long_Long_Integer (Clock.Nanoseconds'Last)
        or else not Clock.Conversion_Fits
          (Clock.Nanoseconds (Nanoseconds), Rate)
      then
         raise Storage_Error;
      end if;
      Tick_Count := Clock.To_Ticks_Ceiling
        (Clock.Nanoseconds (Nanoseconds), Rate);
      Deadline := Clock.Tick (Core.Read_Clock);
      if not Clock.Deadline_Fits (Deadline, Tick_Count) then
         raise Storage_Error;
      end if;
      Deadline := Clock.Add_Delay (Deadline, Tick_Count);

      Enter_Kernel;
      Caller := Core.Current_Locked (Dense);
      Deliver_Pending_Abort_Locked;
      Target_Slot := Record_Of (Target);
      Target_Ref := To_Reference (Target);
      if Natural (Entry_Index) > Tasks (Target_Slot).Entry_Count then
         Leave_Kernel;
         raise Program_Error;
      elsif Tasks (Target_Slot).Terminate_Selected
        or else Core.State_Locked (Target_Ref) in
          Dispatcher.Retiring | Dispatcher.Terminated
      then
         Leave_Kernel;
         Raise_Tasking_Error (System.Null_Address, 0);
      end if;
      Call := Allocate_Call_Locked;
      Calls (Call) :=
        (Phase => Queued, Timed => True, Caller => Caller,
         Sequence => Allocate_Call_Sequence_Locked,
         Target => Target_Ref, Entry_Index => Entry_Index,
         Parameters => Parameters,
         Caller_Wait =>
           (Task_Reference => Core.No_Task, Generation => 0),
         Exception_Identity => System.Null_Address);
      Core.Arm_Wait_Locked
        (Caller, Waits.Timed_Object_Wait, Calls (Call).Caller_Wait);
      Caller_Wait := Calls (Call).Caller_Wait;

      if Tasks (Target_Slot).Accepting
        and then Tasks (Target_Slot).Accept_Entry = Entry_Index
        and then Tasks (Target_Slot).Active_Call = 0
      then
         Calls (Call).Phase := Accepted_Call;
         Tasks (Target_Slot).Active_Call := Natural (Call);
         Core.Resolve_Exact_Locked
           (Tasks (Target_Slot).Accept_Wait, Waits.Object_Wake,
            Status, Wake_Core);
         if Status /= Waits.Made_Ready then
            Leave_Kernel;
            Stop;
         end if;
         Accepted := True;
         Kick_Core (System.Address (Wake_Core));
      else
         Core.Register_Deadline_Locked
           (Caller_Wait, Core.Tick (Deadline));
         Kick_Core
           (System.Address (Core.Assigned_Core_Locked (Target_Ref)));
      end if;
      Core.Block_Current_And_Release
        (Dense, Caller_Wait, Outcome);

      if Outcome = Waits.Abort_Wake then
         Deliver_Pending_Abort;
      end if;

      Enter_Kernel;
      if Outcome = Waits.Timer_Expiry then
         if Calls (Call).Phase /= Queued
           or else Calls (Call).Caller /= Caller
           or else Calls (Call).Caller_Wait /= Caller_Wait
           or else not Calls (Call).Timed
           or else Core.Current_Locked (Dense) /= Caller
         then
            Leave_Kernel;
            Stop;
         end if;
         Calls (Call) := (others => <>);
         Accepted := False;
      elsif Outcome = Waits.Object_Wake then
         if not Accepted then
            Accepted := True;
         end if;
      else
         Leave_Kernel;
         Stop;
      end if;
      Leave_Kernel;
      if Outcome = Waits.Object_Wake then
         Consume_Call_Completion (Call, Caller);
      end if;
   end Timed_Task_Entry_Call;

   procedure Accept_Call
     (Entry_Index : System.Tasking.Task_Entry_Index;
      Parameters  : out System.Address)
   is
      Dense      : constant Core_Number := Core_Of_Current;
      Server     : Dispatcher.Task_Ref;
      Server_Slot : Task_Slot;
      Selected   : Natural range 0 .. Max_Calls := 0;
      Outcome    : Waits.Resolution;
   begin
      Enter_Kernel;
      Server := Core.Current_Locked (Dense);
      Deliver_Pending_Abort_Locked;
      Server_Slot := Record_Of (To_Identity (Server));
      if Natural (Entry_Index) > Tasks (Server_Slot).Entry_Count
        or else Tasks (Server_Slot).Accepting
        or else Tasks (Server_Slot).Active_Call /= 0
      then
         Leave_Kernel;
         raise Program_Error;
      end if;
      Selected := Oldest_Queued_Call_Locked (Server, Entry_Index);

      if Selected = 0 then
         Tasks (Server_Slot).Accepting := True;
         Tasks (Server_Slot).Accept_Entry := Entry_Index;
         Core.Arm_Wait_Locked
           (Server, Waits.Object_Wait, Tasks (Server_Slot).Accept_Wait);
         Core.Block_Current_And_Release
           (Dense, Tasks (Server_Slot).Accept_Wait, Outcome);
         if Outcome = Waits.Abort_Wake then
            Enter_Kernel;
            if not Tasks (Server_Slot).Accepting
              or else Tasks (Server_Slot).Active_Call /= 0
            then
               Leave_Kernel;
               Stop;
            end if;
            Tasks (Server_Slot).Accepting := False;
            Leave_Kernel;
            Deliver_Pending_Abort;
            Stop;
         elsif Outcome /= Waits.Object_Wake then
            Stop;
         end if;
         Enter_Kernel;
         Selected := Tasks (Server_Slot).Active_Call;
         if Selected = 0 then
            Leave_Kernel;
            Stop;
         end if;
      else
         Accept_Queued_Call_Locked
           (Server_Slot, Call_Number (Selected), Parameters);
      end if;
      Tasks (Server_Slot).Accepting := False;
      Tasks (Server_Slot).Terminate_Open := False;
      if Selected /= 0 and then Tasks (Server_Slot).Active_Call = Selected then
         Parameters := Calls (Call_Number (Selected)).Parameters;
      else
         Leave_Kernel;
         Stop;
      end if;
      --  The compiler-generated accept-action wrapper begins by calling
      --  Abort_Undefer.  Return the accepted rendezvous with the matching
      --  deferral already established, for both queued and blocking paths.
      Defer_Abort_Locked (Server_Slot);
      Leave_Kernel;
   end Accept_Call;

   procedure Complete_Rendezvous is
      Dense       : constant Core_Number := Core_Of_Current;
      Server      : Dispatcher.Task_Ref;
      Server_Slot : Task_Slot;
      Call        : Call_Number;
      Status      : Waits.Resolve_Status;
      Wake_Core   : Core_Number := 0;
      Completion  : Completions.Complete_Result;
   begin
      Enter_Kernel;
      Server := Core.Current_Locked (Dense);
      Server_Slot := Record_Of (To_Identity (Server));
      if Tasks (Server_Slot).Active_Call = 0 then
         Leave_Kernel;
         raise Program_Error;
      end if;
      Call := Call_Number (Tasks (Server_Slot).Active_Call);
      if Calls (Call).Phase /= Accepted_Call
        or else Calls (Call).Target /= Server
      then
         Leave_Kernel;
         Stop;
      end if;
      Core.Resolve_Exact_Locked
        (Calls (Call).Caller_Wait, Waits.Object_Wake, Status, Wake_Core);
      if Status /= Waits.Made_Ready then
         Leave_Kernel;
         Stop;
      end if;
      Completion := Completions.Complete
        (Calls (Call).Phase, Completions.Normal);
      if Completion.Status /= Completions.Completed then
         Leave_Kernel;
         Stop;
      end if;
      Calls (Call).Phase := Completion.Phase;
      Calls (Call).Exception_Identity := System.Null_Address;
      Tasks (Server_Slot).Active_Call := 0;
      Leave_Kernel;
      Kick_Core (System.Address (Wake_Core));
   end Complete_Rendezvous;

   procedure Exceptional_Complete_Rendezvous
     (Occurrence : System.Address)
   is
      Dense       : constant Core_Number := Core_Of_Current;
      Server      : Dispatcher.Task_Ref;
      Server_Slot : Task_Slot;
      Call        : Call_Number;
      Status      : Waits.Resolve_Status;
      Wake_Core   : Core_Number := 0;
      Identity    : constant System.Address :=
        Snapshot_Exception_Identity (Occurrence);
      Completion  : Completions.Complete_Result;
   begin
      Enter_Kernel;
      Server := Core.Current_Locked (Dense);
      Server_Slot := Record_Of (To_Identity (Server));
      if Tasks (Server_Slot).Active_Call = 0 then
         Leave_Kernel;
         raise Program_Error;
      end if;
      Call := Call_Number (Tasks (Server_Slot).Active_Call);
      if Calls (Call).Phase /= Accepted_Call
        or else Calls (Call).Target /= Server
        or else Identity = System.Null_Address
      then
         Leave_Kernel;
         Stop;
      end if;
      Core.Resolve_Exact_Locked
        (Calls (Call).Caller_Wait, Waits.Object_Wake, Status, Wake_Core);
      if Status /= Waits.Made_Ready then
         Leave_Kernel;
         Stop;
      end if;
      Completion := Completions.Complete
        (Calls (Call).Phase, Completions.Exceptional);
      if Completion.Status /= Completions.Completed then
         Leave_Kernel;
         Stop;
      end if;
      Calls (Call).Phase := Completion.Phase;
      Calls (Call).Exception_Identity := Identity;
      Tasks (Server_Slot).Active_Call := 0;
      Leave_Kernel;
      Kick_Core (System.Address (Wake_Core));
      Reraise_Exception (Occurrence);
   end Exceptional_Complete_Rendezvous;

   procedure Selective_Wait
     (Alternatives : System.Tasking.Accept_List_Access;
      Mode         : System.Tasking.Select_Mode;
      Parameters   : out System.Address;
      Selected     : out System.Tasking.Select_Index)
   is
      Dense       : constant Core_Number := Core_Of_Current;
      Alternative : System.Tasking.Accept_Alternative;
      Server      : Dispatcher.Task_Ref;
      Server_Slot : Task_Slot;
      Call        : Natural range 0 .. Max_Calls := 0;
      Outcome     : Waits.Resolution;
      Kicks       : Boolean_Core_Array := [others => False];
   begin
      if Alternatives = null or else Alternatives'Length /= 1
        or else Mode /= System.Tasking.Terminate_Mode
      then
         raise Program_Error;
      end if;
      Alternative := Alternatives (Alternatives'First);
      Enter_Kernel;
      Server := Core.Current_Locked (Dense);
      Deliver_Pending_Abort_Locked;
      Server_Slot := Record_Of (To_Identity (Server));
      if Natural (Alternative.S) > Tasks (Server_Slot).Entry_Count
        or else Tasks (Server_Slot).Accepting
        or else Tasks (Server_Slot).Active_Call /= 0
        or else Tasks (Server_Slot).Terminate_Open
        or else Tasks (Server_Slot).Terminate_Selected
      then
         Leave_Kernel;
         raise Program_Error;
      end if;
      Call := Oldest_Queued_Call_Locked (Server, Alternative.S);
      if Call /= 0 then
         Accept_Queued_Call_Locked
           (Server_Slot, Call_Number (Call), Parameters);
         Selected := System.Tasking.Select_Index (Alternatives'First);
         Defer_Abort_Locked (Server_Slot);
         Leave_Kernel;
      else
         Tasks (Server_Slot).Accepting := True;
         Tasks (Server_Slot).Accept_Entry := Alternative.S;
         Tasks (Server_Slot).Terminate_Open := True;
         Core.Arm_Wait_Locked
           (Server, Waits.Object_Wait, Tasks (Server_Slot).Accept_Wait);
         Try_All_Closed_Masters_Locked (Kicks);
         for Candidate in Core_Number loop
            if Natural (Candidate) < Core.CPU_Count
              and then Kicks (Candidate)
            then
               Kick_Core (System.Address (Candidate));
            end if;
         end loop;
         Core.Block_Current_And_Release
           (Dense, Tasks (Server_Slot).Accept_Wait, Outcome);
         if Outcome = Waits.Abort_Wake then
            Enter_Kernel;
            if not Tasks (Server_Slot).Accepting
              or else not Tasks (Server_Slot).Terminate_Open
              or else Tasks (Server_Slot).Active_Call /= 0
              or else Tasks (Server_Slot).Terminate_Selected
            then
               Leave_Kernel;
               Stop;
            end if;
            Tasks (Server_Slot).Accepting := False;
            Tasks (Server_Slot).Terminate_Open := False;
            Leave_Kernel;
            Deliver_Pending_Abort;
            Stop;
         elsif Outcome /= Waits.Object_Wake then
            Stop;
         end if;
         Enter_Kernel;
         if Tasks (Server_Slot).Terminate_Selected then
            if Tasks (Server_Slot).Accepting
              or else Tasks (Server_Slot).Terminate_Open
              or else Tasks (Server_Slot).Active_Call /= 0
            then
               Leave_Kernel;
               Stop;
            end if;
            Selected := System.Tasking.No_Rendezvous;
            Parameters := System.Null_Address;
            Leave_Kernel;
            Raise_Terminate;
         end if;
         Call := Tasks (Server_Slot).Active_Call;
         if Call = 0 or else not Tasks (Server_Slot).Accepting
           or else not Tasks (Server_Slot).Terminate_Open
         then
            Leave_Kernel;
            Stop;
         end if;
         Tasks (Server_Slot).Accepting := False;
         Tasks (Server_Slot).Terminate_Open := False;
         Parameters := Calls (Call_Number (Call)).Parameters;
         Selected := System.Tasking.Select_Index (Alternatives'First);
         Defer_Abort_Locked (Server_Slot);
         Leave_Kernel;
      end if;
      if Alternative.Null_Body then
         Complete_Rendezvous;
      end if;
   end Selective_Wait;
end Rendezvous_Operations;
