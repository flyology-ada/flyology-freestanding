--  SPDX-License-Identifier: MIT OR Apache-2.0

with Flyology.Dispatcher_Model;
with Ada.Exceptions;
with Flyology.Clock_Model;
with Flyology.Exceptional_Completion_Model;
with Flyology.Placement_Model;
with Flyology.Task_Core;
with Flyology.Wait_Arbitration_Model;

package body Flyology.M3_Runtime is
   package Dispatcher renames Flyology.Dispatcher_Model;
   package Clock renames Flyology.Clock_Model;
   package Completions renames Flyology.Exceptional_Completion_Model;
   package Placement renames Flyology.Placement_Model;
   package Core renames Flyology.Task_Core;
   package Waits renames Flyology.Wait_Arbitration_Model;
   use type Dispatcher.Task_Ref;
   use type Dispatcher.Task_Slot;
   use type Dispatcher.Task_Incarnation;
   use type Dispatcher.Task_State;
   use type System.Address;
   use type System.Tasking.Task_Id;
   use type System.Tasking.Task_Procedure_Access;
   use type System.Tasking.Boolean_Access;
   use type System.Tasking.Task_Entry_Index;
   use type System.Tasking.Call_Modes;
   use type System.Tasking.Select_Mode;
   use type System.Tasking.Accept_List_Access;
   use type Waits.Resolve_Status;
   use type Waits.Resolution;
   use type Waits.Wait_Kind;
   use type Clock.Tick;
   use type Completions.Complete_Status;
   use type Completions.Completion_Phase;
   use type Completions.Consume_Status;
   use type Core.Timer_Cancel_Status;
   use type Core.Wait_Token;

   Max_Cores   : constant := Core.Max_Cores;
   Max_Tasks   : constant := System.Tasking.Max_Tasks;
   Max_Masters : constant := 32;
   Max_Groups  : constant := Max_Tasks;
   Max_Calls   : constant := Max_Tasks;

   subtype Core_Number is Core.Core_Number;
   subtype Task_Slot is Core.Task_Slot;
   type Master_Number is range 1 .. Max_Masters;
   type Group_Number is range 1 .. Max_Groups;
   type Call_Number is range 1 .. Max_Calls;
   type Call_Sequence is range 0 .. 2 ** 63 - 1;
   No_Call_Sequence : constant Call_Sequence := Call_Sequence'First;
   type Master_Stack is array (Positive range 1 .. 8) of Integer;

   type Task_Record is record
      Identity             : Task_Id := null;
      Body_Procedure       : System.Tasking.Task_Procedure_Access := null;
      Discriminants        : System.Address := System.Null_Address;
      Elaborated           : System.Tasking.Boolean_Access := null;
      Requested_CPU        : Integer := System.Tasking.Unspecified_CPU;
      Priority             : Dispatcher.Priority := Dispatcher.Priority'First;
      Entry_Count          : Natural range 0 .. 255 := 0;
      Master               : Integer := 0;
      Group                : Integer := 0;
      Activation_Completed : Boolean := False;
      Completion_Requested : Boolean := False;
      Masters              : Master_Stack := [others => 0];
      Master_Depth         : Natural range 0 .. Master_Stack'Last := 0;
      Abort_Depth          : Natural range 0 .. 255 := 0;
      Abort_Pending        : Boolean := False;
      Abort_In_Progress    : Boolean := False;
      Accepting            : Boolean := False;
      Accept_Entry         : System.Tasking.Task_Entry_Index := 1;
      Accept_Wait          : Core.Wait_Token;
      Active_Call          : Natural range 0 .. Max_Calls := 0;
   end record;
   type Task_Record_Array is array (Task_Slot) of Task_Record;

   type Master_Record is record
      Used       : Boolean := False;
      Open       : Boolean := False;
      Waiting    : Boolean := False;
      Owner      : Dispatcher.Task_Ref := Core.No_Task;
      Dependents : Natural range 0 .. Max_Tasks := 0;
      Wait       : Core.Wait_Token;
   end record;
   type Master_Array is array (Master_Number) of Master_Record;

   type Group_Record is record
      Used      : Boolean := False;
      Activator : Dispatcher.Task_Ref := Core.No_Task;
      Pending   : Natural range 0 .. Max_Tasks := 0;
      Any_Failed : Boolean := False;
      Wait      : Core.Wait_Token;
   end record;
   type Group_Array is array (Group_Number) of Group_Record;
   subtype Call_Phase is Completions.Completion_Phase;
   Free : constant Call_Phase := Completions.Free;
   Queued : constant Call_Phase := Completions.Queued;
   Accepted_Call : constant Call_Phase := Completions.Accepted;
   Completed_Normal : constant Call_Phase := Completions.Completed_Normal;
   Completed_Exceptional : constant Call_Phase :=
     Completions.Completed_Exceptional;
   type Call_Record is record
      Phase      : Call_Phase := Free;
      Timed      : Boolean := False;
      Sequence   : Call_Sequence := No_Call_Sequence;
      Caller     : Dispatcher.Task_Ref := Core.No_Task;
      Target     : Dispatcher.Task_Ref := Core.No_Task;
      Entry_Index : System.Tasking.Task_Entry_Index := 1;
      Parameters : System.Address := System.Null_Address;
      Caller_Wait : Core.Wait_Token;
      Exception_Identity : System.Address := System.Null_Address;
   end record;
   type Call_Array is array (Call_Number) of Call_Record;
   type Boolean_Core_Array is array (Core_Number) of Boolean;
   type Core_Plan is array (Positive range <>) of Core_Number;

   Tasks          : Task_Record_Array;
   Masters        : Master_Array;
   Groups         : Group_Array;
   Calls          : Call_Array;
   Next_Incarnation : array (Task_Slot) of Dispatcher.Task_Incarnation :=
     [others => 1];
   Placement_Next : Core_Number := 0;
   Next_Call_Sequence : Call_Sequence := No_Call_Sequence + 1;

   function Current_Core_Raw return System.Address
   with Import, Convention => C, External_Name => "flyology_current_core";

   function Boot_CPU_Count return System.Address
   with Import, Convention => C,
        External_Name => "flyology_m3_boot_cpu_count";

   procedure Enter_Kernel
   with Import, Convention => C, External_Name => "flyology_rts_lock_acquire";

   procedure Leave_Kernel
   with Import, Convention => C, External_Name => "flyology_rts_lock_release";

   procedure Kick_Core (Core : System.Address)
   with Import, Convention => C, External_Name => "flyology_m3_kick_core";

   procedure Parallel_Barrier (Phase : System.Address)
   with Import, Convention => C,
        External_Name => "flyology_m3_parallel_barrier";

   procedure Report_Failure
   with Import, Convention => C, External_Name => "flyology_m2_report_failure";

   procedure Raise_Tasking_Error (Location : System.Address; Line : Integer)
   with Import, Convention => C,
        External_Name => "__gnat_rcheck_TE_Explicit_Raise",
        No_Return;

   procedure Raise_Abort
   with Import, Convention => C, External_Name => "flyology_raise_abort",
        No_Return;

   function Snapshot_Exception_Identity
     (Occurrence : System.Address) return System.Address
   with Import, Convention => C,
        External_Name => "flyology_exception_identity";

   procedure Raise_Exception_Identity (Identity : System.Address)
   with Import, Convention => C,
        External_Name => "flyology_raise_exception_identity", No_Return;

   procedure Reraise_Exception (Occurrence : System.Address)
   with Import, Convention => C,
        External_Name => "__gnat_reraise_zcx", No_Return;

   function Exception_Task_Capacity return System.Address
   with Import, Convention => C,
        External_Name => "flyology_exception_task_capacity";

   procedure Release_Exception_Task_Slot (Slot : System.Address)
   with Import, Convention => C,
        External_Name => "flyology_exception_release_task_slot";

   procedure Task_Root_Invoke
     (Body_Procedure : System.Tasking.Task_Procedure_Access;
      Discriminants  : System.Address)
   with Export, Convention => C,
        External_Name => "flyology_task_root_invoke";

   function Exception_Task_Slot return System.Address
   with Export, Convention => C,
        External_Name => "flyology_exception_task_slot";

   procedure Stop is
   begin
      Report_Failure;
      loop
         null;
      end loop;
   end Stop;

   function To_Reference (Item : Task_Id) return Dispatcher.Task_Ref is
      Slot        : Natural;
      Incarnation : Natural;
   begin
      if Item = null then
         return Core.No_Task;
      end if;
      Slot := System.Tasking.Execution_Slot_Of (Item);
      Incarnation := System.Tasking.Incarnation_Of (Item);
      if Slot > Natural (Task_Slot'Last) or else Incarnation = 0
        or else Incarnation > Natural (Dispatcher.Task_Incarnation'Last)
      then
         return Core.No_Task;
      end if;
      return
        (Slot        => Dispatcher.Task_Slot (Slot),
         Incarnation => Dispatcher.Task_Incarnation (Incarnation));
   end To_Reference;

   function To_Identity (Reference : Dispatcher.Task_Ref) return Task_Id is
   begin
      if Reference = Core.No_Task or else Reference.Slot > Task_Slot'Last
      then
         return null;
      end if;
      return Tasks (Task_Slot (Reference.Slot)).Identity;
   end To_Identity;

   function Core_Of_Current return Core_Number is
      Raw : constant System.Address := Current_Core_Raw;
   begin
      if Raw >= System.Address (Core.CPU_Count) then
         Stop;
      end if;
      return Core_Number (Raw);
   end Core_Of_Current;

   function Record_Of (Item : Task_Id) return Task_Slot is
      Slot      : constant Natural :=
        System.Tasking.Execution_Slot_Of (Item);
      Reference : Dispatcher.Task_Ref;
   begin
      if Slot > Natural (Task_Slot'Last)
        or else Tasks (Task_Slot (Slot)).Identity /= Item
      then
         Stop;
      end if;
      Reference := To_Reference (Item);
      if not Core.Known_Locked (Reference) then
         Stop;
      end if;
      return Task_Slot (Slot);
   end Record_Of;

   function Allocate_Group return Group_Number is
   begin
      for Group in Group_Number loop
         if not Groups (Group).Used then
            Groups (Group).Used := True;
            return Group;
         end if;
      end loop;
      Stop;
      return Group_Number'First;
   end Allocate_Group;

   procedure Create_Task
     (Body_Procedure : System.Tasking.Task_Procedure_Access;
      Discriminants  : System.Address;
      Elaborated     : System.Tasking.Boolean_Access;
      Priority       : Integer;
      CPU            : Integer;
      Entry_Count    : Natural;
      Master         : Integer;
      Created_Task   : out Task_Id)
   is
      Slot               : Task_Slot := 1;
      Found              : Boolean := False;
      Effective_Priority : Dispatcher.Priority;
   begin
      if Body_Procedure = null or else Elaborated = null
        or else Master not in Integer (Master_Number'First) ..
          Integer (Master_Number'Last)
        or else Priority < System.Tasking.Unspecified_Priority
        or else Priority > Integer (Dispatcher.Priority'Last)
        or else Entry_Count > 255
      then
         Stop;
      end if;
      if Priority = System.Tasking.Unspecified_Priority then
         Effective_Priority := Dispatcher.Priority'First;
      else
         Effective_Priority := Dispatcher.Priority (Priority);
      end if;
      Enter_Kernel;
      for Candidate in Task_Slot range 1 .. Task_Slot'Last loop
         if Tasks (Candidate).Identity = null then
            Slot := Candidate;
            Found := True;
            exit;
         end if;
      end loop;
      if not Found
        or else not Masters (Master_Number (Master)).Used
        or else not Masters (Master_Number (Master)).Open
        or else Masters (Master_Number (Master)).Dependents = Max_Tasks
      then
         Leave_Kernel;
         Stop;
      end if;
      Created_Task := System.Tasking.Create_Identity
        (Natural (Slot), Natural (Next_Incarnation (Slot)));
      if Created_Task = null then
         Leave_Kernel;
         raise Storage_Error;
      end if;
      Tasks (Slot) :=
        (Identity             => Created_Task,
         Body_Procedure       => Body_Procedure,
         Discriminants        => Discriminants,
         Elaborated           => Elaborated,
         Requested_CPU        => CPU,
         Priority             => Effective_Priority,
         Entry_Count          => Entry_Count,
         Master               => Master,
         Group                => 0,
         Activation_Completed => False,
         Completion_Requested => False,
         Masters              => [others => 0],
         Master_Depth         => 0,
         Abort_Depth          => 1,
         Abort_Pending        => False,
         Abort_In_Progress    => False,
         Accepting            => False,
         Accept_Entry         => 1,
         Accept_Wait          =>
           (Task_Reference => Core.No_Task, Generation => 0),
         Active_Call          => 0);
      Core.Register_Dormant_Locked (To_Reference (Created_Task));
      Masters (Master_Number (Master)).Dependents :=
        Masters (Master_Number (Master)).Dependents + 1;
      Leave_Kernel;
   end Create_Task;

   function Can_Release_Unactivated_Locked
     (Slot            : Task_Slot;
      Expected_Master : Master_Number) return Boolean
   is
      Identity  : constant Task_Id := Tasks (Slot).Identity;
      Reference : Dispatcher.Task_Ref;
   begin
      if Identity = null
        or else Tasks (Slot).Master not in Integer (Master_Number'First) ..
          Integer (Master_Number'Last)
        or else Tasks (Slot).Master /= Integer (Expected_Master)
        or else Tasks (Slot).Group /= 0
        or else Tasks (Slot).Activation_Completed
        or else Tasks (Slot).Completion_Requested
        or else Tasks (Slot).Accepting
        or else Tasks (Slot).Active_Call /= 0
        or else not Dispatcher.Can_Advance_Incarnation
          (Next_Incarnation (Slot))
      then
         return False;
      end if;
      Reference := To_Reference (Identity);
      return Masters (Expected_Master).Used
        and then Masters (Expected_Master).Dependents > 0
        and then Core.Can_Cancel_Dormant_Locked (Reference);
   end Can_Release_Unactivated_Locked;

   procedure Release_Unactivated_Locked (Slot : Task_Slot) is
      Identity  : constant Task_Id := Tasks (Slot).Identity;
      Reference : constant Dispatcher.Task_Ref := To_Reference (Identity);
      Master    : constant Master_Number :=
        Master_Number (Tasks (Slot).Master);
   begin
      if not Can_Release_Unactivated_Locked (Slot, Master) then
         Stop;
      end if;
      Core.Cancel_Dormant_Locked (Reference);
      System.Tasking.Mark_Terminated (Identity);
      Masters (Master).Dependents := Masters (Master).Dependents - 1;
      Release_Exception_Task_Slot (System.Address (Slot));
      Core.Release_Terminated_Locked (Reference);
      Tasks (Slot) := (others => <>);
      Next_Incarnation (Slot) :=
        Dispatcher.Next_Incarnation (Next_Incarnation (Slot));
   end Release_Unactivated_Locked;

   procedure Expunge_Unactivated_Tasks (Members : Task_List) is
      type Slot_Plan is array (Members'Range) of Task_Slot;
      Dense : constant Core_Number := Core_Of_Current;
      Owner : Dispatcher.Task_Ref;
      Planned : Slot_Plan;
      Removal_Count : array (Master_Number) of Natural := [others => 0];
      Planned_Master : Master_Number := Master_Number'First;
   begin
      if Members'Length = 0 then
         return;
      end if;
      Enter_Kernel;
      Owner := Core.Current_Locked (Dense);
      if Core.State_Locked (Owner) /= Dispatcher.Running then
         Leave_Kernel;
         Stop;
      end if;
      for Index in Members'Range loop
         Planned (Index) := Record_Of (Members (Index));
         declare
            Slot      : constant Task_Slot := Planned (Index);
            Reference : constant Dispatcher.Task_Ref :=
              To_Reference (Members (Index));
            Master    : Master_Number;
         begin
            if Core.State_Locked (Reference) /= Dispatcher.Dormant
              or else Tasks (Slot).Group /= 0
              or else Tasks (Slot).Master not in
                Integer (Master_Number'First) .. Integer (Master_Number'Last)
            then
               Leave_Kernel;
               Stop;
            end if;
            if Index > Members'First then
               for Prior in Members'First .. Index - 1 loop
                  if Planned (Prior) = Slot then
                     Leave_Kernel;
                     Stop;
                  end if;
               end loop;
            end if;
            Master := Master_Number (Tasks (Slot).Master);
            if Index = Members'First then
               Planned_Master := Master;
            elsif Master /= Planned_Master then
               Leave_Kernel;
               Stop;
            end if;
            if not Can_Release_Unactivated_Locked (Slot, Master) then
               Leave_Kernel;
               Stop;
            end if;
            Removal_Count (Master) := Removal_Count (Master) + 1;
         end;
      end loop;
      for Master in Master_Number loop
         if Removal_Count (Master) > 0
           and then
             (not Masters (Master).Used
              or else not Masters (Master).Open
              or else Masters (Master).Owner /= Owner
              or else Removal_Count (Master) > Masters (Master).Dependents)
         then
            Leave_Kernel;
            Stop;
         end if;
      end loop;
      for Slot of Planned loop
         Release_Unactivated_Locked (Slot);
      end loop;
      Leave_Kernel;
   end Expunge_Unactivated_Tasks;

   procedure Activate_Tasks
     (Members : Task_List;
      Failed  : out Boolean)
   is
      type Slot_Plan is array (Members'Range) of Task_Slot;
      Dense          : constant Core_Number := Core_Of_Current;
      Activator      : Dispatcher.Task_Ref;
      Activator_Slot : Task_Slot;
      Group          : Group_Number;
      Kicks          : Boolean_Core_Array := [others => False];
      Plan           : Core_Plan (Members'Range);
      Slots          : Slot_Plan;
      Needed         : array (Core_Number) of Natural := [others => 0];
      Cursor         : Placement.Core_Id := Placement.Core_Id (Placement_Next);
      Outcome        : Waits.Resolution;
      Planned_Master : Master_Number := Master_Number'First;
   begin
      Failed := False;
      if Members'Length = 0 then
         return;
      end if;
      Enter_Kernel;
      Activator := Core.Current_Locked (Dense);
      Activator_Slot := Record_Of (To_Identity (Activator));
      if Core.State_Locked (Activator) /= Dispatcher.Running then
         Leave_Kernel;
         Stop;
      end if;
      Deliver_Pending_Abort_Locked;
      if Tasks (Activator_Slot).Abort_Depth = 255 then
         Leave_Kernel;
         Stop;
      end if;
      --  Activation is an indivisible language-level cleanup boundary.  A
      --  remote abort may become pending after publication, but it cannot
      --  replace the exact activation-completion wake.  The matching
      --  Abort_Undefer below delivers it immediately after group cleanup.
      Tasks (Activator_Slot).Abort_Depth :=
        Tasks (Activator_Slot).Abort_Depth + 1;

      --  Validate the complete chain and placement plan before publishing any
      --  Ready transition.  This is the production use of the proved mapping.
      for Index in Members'Range loop
         declare
            Slot : constant Task_Slot := Record_Of (Members (Index));
            CPU  : constant Integer := Tasks (Slot).Requested_CPU;
            Result : Placement.Placement_Result;
         begin
            Slots (Index) := Slot;
            if Core.State_Locked (To_Reference (Members (Index))) /=
              Dispatcher.Dormant
              or else CPU not in Integer (Placement.Ada_CPU'First) ..
                Integer (Placement.Ada_CPU'Last)
              or else Tasks (Slot).Master not in
                Integer (Master_Number'First) .. Integer (Master_Number'Last)
            then
               Leave_Kernel;
               Stop;
            end if;
            if Index > Members'First then
               for Prior in Members'First .. Index - 1 loop
                  if Slots (Prior) = Slot then
                     Leave_Kernel;
                     Stop;
                  end if;
               end loop;
            end if;
            declare
               Master : constant Master_Number :=
                 Master_Number (Tasks (Slot).Master);
            begin
               if Index = Members'First then
                  Planned_Master := Master;
               elsif Master /= Planned_Master then
                  Leave_Kernel;
                  Stop;
               end if;
               if not Masters (Master).Used
                 or else not Masters (Master).Open
                 or else Masters (Master).Owner /= Activator
               then
                  Leave_Kernel;
                  Stop;
               end if;
            end;
            Result := Placement.Place
              (Placement.Ada_CPU (CPU), Placement.Core_Count (Core.CPU_Count),
               Cursor);
            if not Result.Accepted then
               Leave_Kernel;
               Stop;
            end if;
            Plan (Index) := Core_Number (Result.Core);
            Cursor := Result.Next_Cursor;
            Needed (Plan (Index)) := Needed (Plan (Index)) + 1;
         end;
      end loop;
      for Candidate in Core_Number loop
         if Natural (Candidate) < Core.CPU_Count
           and then Needed (Candidate) > Core.Queue_Space_Locked (Candidate)
         then
            Leave_Kernel;
            Stop;
         end if;
      end loop;

      Group := Allocate_Group;
      Groups (Group).Activator := Activator;
      Groups (Group).Pending := Members'Length;
      Groups (Group).Any_Failed := False;
      Core.Arm_Wait_Locked
        (Activator, Waits.Activation_Wait, Groups (Group).Wait);
      for Index in Members'Range loop
         declare
            Slot : constant Task_Slot := Slots (Index);
         begin
            Tasks (Slot).Group := Integer (Group);
            Core.Activate_Locked
              (To_Reference (Members (Index)), Plan (Index),
               Tasks (Slot).Priority);
            Kicks (Plan (Index)) := True;
         end;
      end loop;
      Placement_Next := Core_Number (Cursor);
      for Candidate in Core_Number loop
         if Natural (Candidate) < Core.CPU_Count and then Kicks (Candidate) then
            Kick_Core (System.Address (Candidate));
         end if;
      end loop;
      --  Activation waits for every compiler wrapper to acknowledge entry.
      Core.Block_Current_And_Release
        (Dense, Groups (Group).Wait, Outcome);
      if Outcome /= Waits.Object_Wake then
         Stop;
      end if;
      Enter_Kernel;
      if not Groups (Group).Used
        or else Groups (Group).Pending /= 0
        or else Groups (Group).Activator /= Activator
      then
         Leave_Kernel;
         Stop;
      end if;
      Failed := Groups (Group).Any_Failed;
      for Index in Members'Range loop
         declare
            Slot : constant Task_Slot := Record_Of (Members (Index));
         begin
            if Tasks (Slot).Group /= Integer (Group) then
               Leave_Kernel;
               Stop;
            end if;
            Tasks (Slot).Group := 0;
         end;
      end loop;
      Groups (Group) := (others => <>);
      Leave_Kernel;
   end Activate_Tasks;

   procedure Raise_Activation_Failure is
   begin
      Raise_Tasking_Error (System.Null_Address, 0);
   end Raise_Activation_Failure;

   procedure Complete_Activation is
      Dense     : constant Core_Number := Core_Of_Current;
      Reference : Dispatcher.Task_Ref;
      Slot      : Task_Slot;
      Group     : Group_Number;
      Wake_Core : Core_Number := 0;
      Wake      : Boolean := False;
      Status    : Waits.Resolve_Status;
   begin
      Enter_Kernel;
      Reference := Core.Current_Locked (Dense);
      Slot := Record_Of (To_Identity (Reference));
      if Core.State_Locked (Reference) /= Dispatcher.Running
        or else Tasks (Slot).Activation_Completed
        or else Tasks (Slot).Group = 0
      then
         Leave_Kernel;
         Stop;
      end if;
      Group := Group_Number (Tasks (Slot).Group);
      if not Groups (Group).Used or else Groups (Group).Pending = 0 then
         Leave_Kernel;
         Stop;
      end if;
      Tasks (Slot).Activation_Completed := True;
      Groups (Group).Pending := Groups (Group).Pending - 1;
      if Groups (Group).Pending = 0 then
         Core.Resolve_Exact_Locked
           (Groups (Group).Wait, Waits.Object_Wake, Status, Wake_Core);
         if Status /= Waits.Made_Ready then
            Leave_Kernel;
            Stop;
         end if;
         Wake := True;
      end if;
      Leave_Kernel;
      if Wake then
         Kick_Core (System.Address (Wake_Core));
      end if;
   end Complete_Activation;

   procedure Complete_Task is
      Dense     : constant Core_Number := Core_Of_Current;
      Reference : Dispatcher.Task_Ref;
      Slot      : Task_Slot;
   begin
      Enter_Kernel;
      Reference := Core.Current_Locked (Dense);
      Slot := Record_Of (To_Identity (Reference));
      if Core.State_Locked (Reference) /= Dispatcher.Running
        or else Tasks (Slot).Completion_Requested
      then
         Leave_Kernel;
         Stop;
      end if;
      Tasks (Slot).Completion_Requested := True;
      Leave_Kernel;
   end Complete_Task;

   procedure Observe_Abort_Cleanup is
      Dense : constant Core_Number := Core_Of_Current;
      Slot  : Task_Slot;
      Aborting : Boolean;
   begin
      Enter_Kernel;
      Slot := Record_Of (To_Identity (Core.Current_Locked (Dense)));
      Aborting := Tasks (Slot).Abort_In_Progress;
      Leave_Kernel;
      if Aborting then
         --  A nested handled exception must not erase the outer abort that
         --  is still driving this compiler-generated cleanup.
         begin
            raise Program_Error;
         exception
            when Program_Error =>
               null;
         end;
         if not Ada.Exceptions.Triggered_By_Abort then
            Stop;
         end if;
      end if;
   end Observe_Abort_Cleanup;

   procedure Abort_Defer is
      Dense : constant Core_Number := Core_Of_Current;
      Slot  : Task_Slot;
   begin
      Enter_Kernel;
      Slot := Record_Of (To_Identity (Core.Current_Locked (Dense)));
      if Tasks (Slot).Abort_Depth = 255 then
         Leave_Kernel;
         Stop;
      end if;
      Tasks (Slot).Abort_Depth := Tasks (Slot).Abort_Depth + 1;
      Leave_Kernel;
   end Abort_Defer;

   procedure Abort_Undefer is
      Dense : constant Core_Number := Core_Of_Current;
      Slot  : Task_Slot;
      Deliver : Boolean;
   begin
      Enter_Kernel;
      Slot := Record_Of (To_Identity (Core.Current_Locked (Dense)));
      if Tasks (Slot).Abort_Depth = 0 then
         Leave_Kernel;
         Stop;
      end if;
      Tasks (Slot).Abort_Depth := Tasks (Slot).Abort_Depth - 1;
      Deliver := Tasks (Slot).Abort_Depth = 0
        and then Tasks (Slot).Abort_Pending;
      if Deliver then
         Tasks (Slot).Abort_Pending := False;
         Tasks (Slot).Abort_In_Progress := True;
      end if;
      Leave_Kernel;
      if Deliver then
         Raise_Abort;
      end if;
   end Abort_Undefer;

   procedure Deliver_Pending_Abort is
      Dense   : constant Core_Number := Core_Of_Current;
      Slot    : Task_Slot;
      Deliver : Boolean;
   begin
      Enter_Kernel;
      Slot := Record_Of (To_Identity (Core.Current_Locked (Dense)));
      Deliver := Tasks (Slot).Abort_Depth = 0
        and then Tasks (Slot).Abort_Pending;
      if Deliver then
         Tasks (Slot).Abort_Pending := False;
         Tasks (Slot).Abort_In_Progress := True;
      end if;
      Leave_Kernel;
      if Deliver then
         Raise_Abort;
      end if;
   end Deliver_Pending_Abort;

   procedure Deliver_Pending_Abort_Locked is
      Dense : constant Core_Number := Core_Of_Current;
      Slot  : Task_Slot;
   begin
      Slot := Record_Of (To_Identity (Core.Current_Locked (Dense)));
      if Tasks (Slot).Abort_Depth = 0
        and then Tasks (Slot).Abort_Pending
      then
         Tasks (Slot).Abort_Pending := False;
         Tasks (Slot).Abort_In_Progress := True;
         Leave_Kernel;
         Raise_Abort;
      end if;
   end Deliver_Pending_Abort_Locked;

   procedure Abort_Tasks (Members : Task_List) is
      Kicks         : Boolean_Core_Array := [others => False];
      Reference     : Dispatcher.Task_Ref;
      Slot          : Task_Slot;
      State         : Dispatcher.Task_State;
      Token         : Core.Wait_Token;
      Kind          : Core.Wait_Kind;
      Status        : Waits.Resolve_Status;
      Wake_Core     : Core_Number := 0;
      Cancel_Status : Core.Timer_Cancel_Status;
      Matching_Call : Natural range 0 .. Max_Calls;
      type Abort_Wait_Action is
        (Resolve_Only, Resolve_And_Remove_Call, Retain_Natural_Wake);
      Wait_Action : Abort_Wait_Action;
   begin
      if Members'Length /= 1 then
         Stop;
      end if;
      Enter_Kernel;
      for Index in Members'Range loop
         if Members (Index) = null then
            Leave_Kernel;
            raise Program_Error;
         elsif System.Tasking.Identity_Is_Terminated (Members (Index)) then
            null;
         else
            Slot := Record_Of (Members (Index));
            Reference := To_Reference (Members (Index));
            State := Core.State_Locked (Reference);
            Wait_Action := Resolve_Only;
            if State = Dispatcher.Dormant then
               Leave_Kernel;
               Stop;
            elsif State in Dispatcher.Retiring | Dispatcher.Terminated then
               null;
            end if;
            if State = Dispatcher.Retiring
              or else Tasks (Slot).Abort_In_Progress
              or else Tasks (Slot).Abort_Pending
            then
               null;
            else
               Tasks (Slot).Abort_Pending := True;
            end if;
            if State = Dispatcher.Retiring
              or else Tasks (Slot).Abort_In_Progress
              or else not Tasks (Slot).Abort_Pending
            then
               null;
            elsif Tasks (Slot).Abort_Depth > 0 then
               --  Abort-deferred operations retain their exact wait.  In
               --  particular activation and master completion must finish
               --  their language-mandated cleanup before Abort_Undefer can
               --  deliver the pending abort.
               if State = Dispatcher.Running then
                  Kicks (Core.Assigned_Core_Locked (Reference)) := True;
               end if;
            elsif State = Dispatcher.Blocked then
               Core.Active_Wait_Locked (Reference, Token, Kind);
               if Kind = Waits.Delay_Wait then
                  Core.Cancel_Deadline_Locked (Token, Cancel_Status);
                  if Cancel_Status /= Core.Cancelled then
                     Leave_Kernel;
                     Stop;
                  end if;
               elsif Kind in Waits.Object_Wait | Waits.Timed_Object_Wait then
                  Matching_Call := 0;
                  for Call in Call_Number loop
                     if Calls (Call).Phase /= Free
                       and then Calls (Call).Caller = Reference
                       and then Calls (Call).Caller_Wait = Token
                     then
                        if Matching_Call /= 0 then
                           Leave_Kernel;
                           Stop;
                        end if;
                        Matching_Call := Natural (Call);
                     end if;
                  end loop;
                  if Matching_Call = 0
                    and then Tasks (Slot).Accepting
                    and then Tasks (Slot).Accept_Wait = Token
                    and then Tasks (Slot).Active_Call = 0
                  then
                     --  The blocked task is the accepting server, not a
                     --  caller.  Accept_Call owns publication cleanup after
                     --  this exact abort wake resumes it.
                     Wait_Action := Resolve_Only;
                  elsif Matching_Call = 0 then
                     Leave_Kernel;
                     Stop;
                  elsif Calls (Call_Number (Matching_Call)).Phase = Accepted_Call
                  then
                     Kicks
                       (Core.Assigned_Core_Locked
                          (Calls (Call_Number (Matching_Call)).Target)) := True;
                     Wait_Action := Retain_Natural_Wake;
                  else
                     if Calls (Call_Number (Matching_Call)).Timed then
                        Core.Cancel_Deadline_Locked (Token, Cancel_Status);
                        if Cancel_Status /= Core.Cancelled then
                           Leave_Kernel;
                           Stop;
                        end if;
                     end if;
                     Wait_Action := Resolve_And_Remove_Call;
                  end if;
                  if Wait_Action = Resolve_And_Remove_Call then
                     Calls (Call_Number (Matching_Call)) := (others => <>);
                  end if;
               elsif Kind in Waits.Protected_Entry_Wait |
                 Waits.Timed_Protected_Entry_Wait
               then
                  if Kind = Waits.Timed_Protected_Entry_Wait then
                     Core.Cancel_Deadline_Locked (Token, Cancel_Status);
                     if Cancel_Status /= Core.Cancelled then
                        Leave_Kernel;
                        Stop;
                     end if;
                  end if;
               elsif Kind in Waits.Master_Wait | Waits.Activation_Wait then
                  --  Master completion is compiler-bracketed by abort
                  --  deferral, and Activate_Tasks establishes its own
                  --  internal deferral.  Reaching either lifecycle wait at
                  --  depth zero violates that contract.
                  Leave_Kernel;
                  Stop;
               else
                  Leave_Kernel;
                  Stop;
               end if;
               if Wait_Action /= Retain_Natural_Wake then
                  Core.Resolve_Exact_Locked
                    (Token, Waits.Abort_Wake, Status, Wake_Core);
                  if Status /= Waits.Made_Ready then
                     Leave_Kernel;
                     Stop;
                  end if;
                  Kicks (Wake_Core) := True;
               end if;
            else
               Kicks (Core.Assigned_Core_Locked (Reference)) := True;
            end if;
         end if;
      end loop;
      Leave_Kernel;
      for Candidate in Core_Number loop
         if Natural (Candidate) < Core.CPU_Count and then Kicks (Candidate) then
            Kick_Core (System.Address (Candidate));
         end if;
      end loop;
   end Abort_Tasks;

   procedure Enter_Master is
      Dense      : constant Core_Number := Core_Of_Current;
      Owner      : Dispatcher.Task_Ref;
      Slot       : Task_Slot;
      New_Master : Master_Number := Master_Number'First;
   begin
      Enter_Kernel;
      Owner := Core.Current_Locked (Dense);
      Slot := Record_Of (To_Identity (Owner));
      while New_Master < Master_Number'Last
        and then Masters (New_Master).Used
      loop
         New_Master := Master_Number'Succ (New_Master);
      end loop;
      if Masters (New_Master).Used
        or else Tasks (Slot).Master_Depth = Tasks (Slot).Masters'Last
      then
         Leave_Kernel;
         Stop;
      end if;
      Masters (New_Master) :=
        (Used => True, Open => True, Waiting => False,
         Owner => Owner, Dependents => 0,
         Wait => (Task_Reference => Core.No_Task, Generation => 0));
      Tasks (Slot).Master_Depth := Tasks (Slot).Master_Depth + 1;
      Tasks (Slot).Masters (Tasks (Slot).Master_Depth) := Integer (New_Master);
      Leave_Kernel;
   end Enter_Master;

   function Current_Master return Integer is
      Dense  : constant Core_Number := Core_Of_Current;
      Slot   : Task_Slot;
      Result : Integer;
   begin
      Enter_Kernel;
      Slot := Record_Of (To_Identity (Core.Current_Locked (Dense)));
      if Tasks (Slot).Master_Depth = 0 then
         Leave_Kernel;
         Stop;
      end if;
      Result := Tasks (Slot).Masters (Tasks (Slot).Master_Depth);
      Leave_Kernel;
      return Result;
   end Current_Master;

   procedure Complete_Master is
      Dense  : constant Core_Number := Core_Of_Current;
      Owner  : Dispatcher.Task_Ref;
      Slot   : Task_Slot;
      Master : Master_Number;
      Outcome : Waits.Resolution;
      Dormant_Count : Natural := 0;
   begin
      Enter_Kernel;
      Owner := Core.Current_Locked (Dense);
      Slot := Record_Of (To_Identity (Owner));
      if Tasks (Slot).Master_Depth = 0 then
         Leave_Kernel;
         Stop;
      end if;
      Master := Master_Number (Tasks (Slot).Masters (Tasks (Slot).Master_Depth));
      if not Masters (Master).Used or else Masters (Master).Owner /= Owner then
         Leave_Kernel;
         Stop;
      end if;
      Deliver_Pending_Abort_Locked;
      for Candidate in Task_Slot range 1 .. Task_Slot'Last loop
         if Tasks (Candidate).Identity /= null
           and then Tasks (Candidate).Master = Integer (Master)
           and then Core.State_Locked (To_Reference (Tasks (Candidate).Identity)) =
             Dispatcher.Dormant
         then
            if not Can_Release_Unactivated_Locked (Candidate, Master) then
               Leave_Kernel;
               Stop;
            end if;
            Dormant_Count := Dormant_Count + 1;
         end if;
      end loop;
      if Dormant_Count > Masters (Master).Dependents then
         Leave_Kernel;
         Stop;
      end if;
      Masters (Master).Open := False;
      for Candidate in Task_Slot range 1 .. Task_Slot'Last loop
         if Tasks (Candidate).Identity /= null
           and then Tasks (Candidate).Master = Integer (Master)
           and then Core.State_Locked (To_Reference (Tasks (Candidate).Identity)) =
             Dispatcher.Dormant
         then
            Release_Unactivated_Locked (Candidate);
         end if;
      end loop;
      if Masters (Master).Dependents > 0 then
         Masters (Master).Waiting := True;
         Core.Arm_Wait_Locked
           (Owner, Waits.Master_Wait, Masters (Master).Wait);
         Core.Block_Current_And_Release
           (Dense, Masters (Master).Wait, Outcome);
         if Outcome /= Waits.Object_Wake then
            Stop;
         end if;
         Enter_Kernel;
      end if;
      if Masters (Master).Dependents /= 0 then
         Leave_Kernel;
         Stop;
      end if;
      for Candidate in Task_Slot range 1 .. Task_Slot'Last loop
         if Tasks (Candidate).Identity /= null
           and then Tasks (Candidate).Master = Integer (Master)
         then
            declare
               Dependent : constant Task_Id := Tasks (Candidate).Identity;
               Reference : constant Dispatcher.Task_Ref :=
                 To_Reference (Dependent);
            begin
               if not System.Tasking.Identity_Is_Terminated (Dependent)
                 or else Core.State_Locked (Reference) /= Dispatcher.Terminated
                 or else not Dispatcher.Can_Advance_Incarnation
                   (Next_Incarnation (Candidate))
               then
                  Leave_Kernel;
                  Stop;
               end if;
               Release_Exception_Task_Slot (System.Address (Candidate));
               Core.Release_Terminated_Locked (Reference);
               Tasks (Candidate) := (others => <>);
               Next_Incarnation (Candidate) :=
                 Dispatcher.Next_Incarnation
                   (Next_Incarnation (Candidate));
            end;
         end if;
      end loop;
      Masters (Master).Used := False;
      Masters (Master).Waiting := False;
      Tasks (Slot).Masters (Tasks (Slot).Master_Depth) := 0;
      Tasks (Slot).Master_Depth := Tasks (Slot).Master_Depth - 1;
      Leave_Kernel;
   end Complete_Master;

   function Current_Task return Task_Id is
     (To_Identity (Core.Current (Core_Of_Current)));

   function Is_Callable (Item : Task_Id) return Boolean is
      Result : Boolean;
      Slot   : Natural;
   begin
      Enter_Kernel;
      Result := System.Tasking.Identity_Is_Callable (Item);
      if Result then
         Slot := System.Tasking.Execution_Slot_Of (Item);
         Result := Slot <= Natural (Task_Slot'Last)
           and then Tasks (Task_Slot (Slot)).Identity = Item
           and then Core.State_Locked (To_Reference (Item)) not in
             Dispatcher.Retiring | Dispatcher.Terminated;
      end if;
      Leave_Kernel;
      return Result;
   end Is_Callable;

   function Is_Terminated (Item : Task_Id) return Boolean is
      Result : Boolean;
   begin
      Enter_Kernel;
      Result := System.Tasking.Identity_Is_Terminated (Item);
      Leave_Kernel;
      return Result;
   end Is_Terminated;

   function Number_Of_CPUs return Natural is (Core.CPU_Count);

   function Current_Core_Number return Natural is
     (Natural (Core_Of_Current));

   function Validate_Current_Stack (Probe : System.Address) return Boolean is
     (Core.Validate_Current_Stack (Core_Of_Current, Probe));

   procedure Demo_Parallel_Barrier (Phase : Positive) is
   begin
      if Core.CPU_Count = 4 then
         Parallel_Barrier (System.Address (Phase));
      end if;
   end Demo_Parallel_Barrier;

   procedure Delay_Until_Tick (Deadline : Clock.Tick) is
      Dense      : constant Core_Number := Core_Of_Current;
      Reference  : Dispatcher.Task_Ref;
      Token      : Core.Wait_Token;
      Outcome    : Waits.Resolution;
   begin
      if Clock.Tick (Core.Read_Clock) >= Deadline then
         return;
      end if;
      Enter_Kernel;
      Reference := Core.Current_Locked (Dense);
      Deliver_Pending_Abort_Locked;
      Core.Arm_Wait_Locked (Reference, Waits.Delay_Wait, Token);
      Core.Register_Deadline_Locked (Token, Core.Tick (Deadline));
      Core.Block_Current_And_Release (Dense, Token, Outcome);
      if Outcome = Waits.Abort_Wake then
         Deliver_Pending_Abort;
      elsif Outcome /= Waits.Timer_Expiry
        or else Clock.Tick (Core.Read_Clock) < Deadline
      then
         Stop;
      end if;
      Deliver_Pending_Abort;
   end Delay_Until_Tick;

   procedure Delay_For (Interval : Duration) is
      Nanosecond_Count : Long_Long_Integer;
      Tick_Count : Clock.Tick;
      Deadline   : Clock.Tick;
      Rate       : Clock.Frequency;
   begin
      if Interval <= 0.0 then
         return;
      end if;
      if Interval > Duration (Long_Long_Integer'Last / 1_000_000_000) then
         raise Storage_Error;
      end if;
      Nanosecond_Count :=
        Long_Long_Integer (Interval * 1_000_000_000) + 1;
      Rate := Clock.Frequency (Core.Clock_Frequency);
      if Nanosecond_Count <= 0
        or else Nanosecond_Count > Long_Long_Integer (Clock.Nanoseconds'Last)
        or else not Clock.Conversion_Fits
          (Clock.Nanoseconds (Nanosecond_Count), Rate)
      then
         raise Storage_Error;
      end if;
      Tick_Count := Clock.To_Ticks_Ceiling
        (Clock.Nanoseconds (Nanosecond_Count), Rate);
      Deadline := Clock.Tick (Core.Read_Clock);
      if not Clock.Deadline_Fits (Deadline, Tick_Count) then
         raise Storage_Error;
      end if;
      Deadline := Clock.Add_Delay (Deadline, Tick_Count);
      Delay_Until_Tick (Deadline);
   end Delay_For;

   procedure Delay_Until (Deadline : Long_Long_Integer) is
   begin
      if Deadline <= 0 then
         return;
      elsif Deadline > Long_Long_Integer (Clock.Tick'Last) then
         raise Storage_Error;
      end if;
      Delay_Until_Tick (Clock.Tick (Deadline));
   end Delay_Until;

   procedure Protected_Enter (Ceiling : Integer) is
      Dense     : constant Core_Number := Core_Of_Current;
      Reference : Dispatcher.Task_Ref;
      Effective : Dispatcher.Priority;
   begin
      if Ceiling = System.Tasking.Unspecified_Priority then
         Effective := Dispatcher.Priority'Last;
      elsif Ceiling in Integer (Dispatcher.Priority'First) ..
        Integer (Dispatcher.Priority'Last)
      then
         Effective := Dispatcher.Priority (Ceiling);
      else
         raise Program_Error;
      end if;
      Enter_Kernel;
      Reference := Core.Current_Locked (Dense);
      if not Core.Enter_Protected_Locked (Reference, Effective) then
         Leave_Kernel;
         raise Program_Error;
      end if;
   end Protected_Enter;

   procedure Protected_Leave is
      Dense     : constant Core_Number := Core_Of_Current;
      Reference : Dispatcher.Task_Ref;
   begin
      Reference := Core.Current_Locked (Dense);
      Core.Leave_Protected_Locked (Reference);
      Leave_Kernel;
   end Protected_Leave;

   procedure Set_Priority (Priority : Integer; Item : Task_Id) is
      Reference : Dispatcher.Task_Ref;
      State     : Dispatcher.Task_State;
      Core_Id   : Core_Number := 0;
      Kick      : Boolean := False;
   begin
      if Item = null then
         raise Program_Error;
      end if;
      Enter_Kernel;
      Reference := To_Reference (Item);
      State := Core.State_Locked (Reference);
      if State not in Dispatcher.Retiring | Dispatcher.Terminated then
         Core.Change_Base_Priority_Locked
           (Reference, Dispatcher.Priority (Priority));
         Core_Id := Core.Assigned_Core_Locked (Reference);
         Kick := State in Dispatcher.Ready | Dispatcher.Running |
           Dispatcher.Blocked;
      end if;
      Leave_Kernel;
      if Kick then
         Kick_Core (System.Address (Core_Id));
      end if;
   end Set_Priority;

   function Get_Priority (Item : Task_Id) return Integer is
      Reference : Dispatcher.Task_Ref;
      Result    : Dispatcher.Priority;
   begin
      if Item = null then
         raise Program_Error;
      end if;
      Enter_Kernel;
      Reference := To_Reference (Item);
      if Core.State_Locked (Reference) in
        Dispatcher.Retiring | Dispatcher.Terminated
      then
         Leave_Kernel;
         Raise_Tasking_Error (System.Null_Address, 0);
      end if;
      Result := Core.Base_Priority_Locked (Reference);
      Leave_Kernel;
      return Integer (Result);
   end Get_Priority;

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
      if Identity /= System.Null_Address then
         Raise_Exception_Identity (Identity);
      end if;
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
      if Natural (Entry_Index) > Tasks (Target_Slot).Entry_Count
        or else Core.State_Locked (Target_Ref) in
          Dispatcher.Retiring | Dispatcher.Terminated
      then
         Leave_Kernel;
         raise Program_Error;
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
      Deliver_Pending_Abort;
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
      if Natural (Entry_Index) > Tasks (Target_Slot).Entry_Count
        or else Core.State_Locked (Target_Ref) in
          Dispatcher.Retiring | Dispatcher.Terminated
      then
         Leave_Kernel;
         raise Program_Error;
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
      Deliver_Pending_Abort;
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
      if Natural (Entry_Index) > Tasks (Target_Slot).Entry_Count
        or else Core.State_Locked (Target_Ref) in
          Dispatcher.Retiring | Dispatcher.Terminated
      then
         Leave_Kernel;
         raise Program_Error;
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
      Deliver_Pending_Abort;
   end Timed_Task_Entry_Call;

   procedure Accept_Call
     (Entry_Index : System.Tasking.Task_Entry_Index;
      Parameters  : out System.Address)
   is
      Dense      : constant Core_Number := Core_Of_Current;
      Server     : Dispatcher.Task_Ref;
      Server_Slot : Task_Slot;
      Selected   : Natural range 0 .. Max_Calls := 0;
      Oldest     : Call_Sequence := Call_Sequence'Last;
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
      for Call in Call_Number loop
         if Calls (Call).Phase = Queued
           and then Calls (Call).Target = Server
           and then Calls (Call).Entry_Index = Entry_Index
         then
            if Core.Wait_Is_Pending_Locked (Calls (Call).Caller_Wait) then
               if Calls (Call).Sequence = No_Call_Sequence then
                  Leave_Kernel;
                  Stop;
               elsif Calls (Call).Sequence < Oldest then
                  Selected := Natural (Call);
                  Oldest := Calls (Call).Sequence;
               end if;
            end if;
         end if;
      end loop;

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
         if Calls (Call_Number (Selected)).Timed then
            declare
               Cancel_Status : Core.Timer_Cancel_Status;
            begin
               Core.Cancel_Deadline_Locked
                 (Calls (Call_Number (Selected)).Caller_Wait,
                  Cancel_Status);
               if Cancel_Status /= Core.Cancelled then
                  Leave_Kernel;
                  Stop;
               end if;
            end;
         end if;
         Calls (Call_Number (Selected)).Phase := Accepted_Call;
         Tasks (Server_Slot).Active_Call := Selected;
      end if;
      Tasks (Server_Slot).Accepting := False;
      Parameters := Calls (Call_Number (Selected)).Parameters;
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
      Alternative : System.Tasking.Accept_Alternative;
   begin
      if Alternatives = null or else Alternatives'Length /= 1
        or else Mode /= System.Tasking.Terminate_Mode
      then
         raise Program_Error;
      end if;
      Alternative := Alternatives (Alternatives'First);
      Accept_Call (Alternative.S, Parameters);
      Selected := System.Tasking.Select_Index (Alternatives'First);
      if Alternative.Null_Body then
         Complete_Rendezvous;
      end if;
   end Selective_Wait;

   procedure Task_Root_Invoke
     (Body_Procedure : System.Tasking.Task_Procedure_Access;
      Discriminants  : System.Address)
   is
   begin
      if Body_Procedure = null then
         Stop;
      end if;
      Body_Procedure (Discriminants);
   exception
      when others =>
         null;
   end Task_Root_Invoke;

   function Exception_Task_Slot return System.Address is
      Reference : constant Dispatcher.Task_Ref :=
        Core.Current (Core_Of_Current);
   begin
      if Reference = Core.No_Task or else Reference.Slot > Task_Slot'Last then
         Stop;
      end if;
      return System.Address (Reference.Slot);
   end Exception_Task_Slot;

   procedure Core_Initialize (CPU_Count : System.Address) is
      Environment : Task_Id;
   begin
      if CPU_Count = 0 or else CPU_Count > Max_Cores then
         Stop;
      end if;
      if Exception_Task_Capacity /= System.Address (Task_Slot'Last + 1) then
         Stop;
      end if;
      Core.Install_Retirement_Hook (Finish_Task_Retirement'Access);
      Core.Initialize (Positive (CPU_Count));
      Tasks := [others => (others => <>)];
      Masters := [others => (others => <>)];
      Groups := [others => (others => <>)];
      Calls := [others => (others => <>)];
      Next_Call_Sequence := No_Call_Sequence + 1;
      Placement_Next := 0;
      Next_Incarnation := [others => 1];
      Environment := System.Tasking.Identity_For_Slot (0);
      Tasks (0).Identity := Environment;
      Enter_Kernel;
      Core.Register_Environment_Locked (To_Reference (Environment));
      Leave_Kernel;
      Enter_Master;
   end Core_Initialize;

   procedure Task_Start (Task_Address : System.Address) is
      Dense     : constant Core_Number := Core_Of_Current;
      Slot      : Task_Slot;
      Reference : Dispatcher.Task_Ref;
      Body_Elaborated : Boolean;
   begin
      if Task_Address > System.Address (Task_Slot'Last) then
         Stop;
      end if;
      Slot := Task_Slot (Task_Address);
      Reference := To_Reference (Tasks (Slot).Identity);
      Enter_Kernel;
      if not Core.Known_Locked (Reference)
        or else Core.Current_Locked (Dense) /= Reference
        or else Core.State_Locked (Reference) /= Dispatcher.Running
        or else Tasks (Slot).Body_Procedure = null
        or else Tasks (Slot).Elaborated = null
      then
         Leave_Kernel;
         Stop;
      end if;
      Body_Elaborated := Tasks (Slot).Elaborated.all;
      if not Body_Elaborated then
         Tasks (Slot).Completion_Requested := True;
      end if;
      Leave_Kernel;
      if Body_Elaborated then
         Task_Root_Invoke
           (Tasks (Slot).Body_Procedure, Tasks (Slot).Discriminants);
      end if;
      if not Tasks (Slot).Completion_Requested then
         Stop;
      end if;
      Enter_Kernel;
      Core.Begin_Retirement_Locked (Dense, Reference);
      Leave_Kernel;
      Core.Switch_To_Dispatcher (Dense, Reference);
   end Task_Start;

   procedure Finish_Task_Retirement
     (Core_Address : System.Address;
      Slot_Address : System.Address)
   is
      Dense     : Core_Number;
      Task_Slot_Number : Task_Slot;
      Reference : Dispatcher.Task_Ref;
      Wake_Core : Core_Number := 0;
      Wake      : Boolean := False;
      Activation_Wake_Core : Core_Number := 0;
      Activation_Wake      : Boolean := False;
      Master    : Master_Number;
      Group     : Group_Number;
      Status    : Waits.Resolve_Status;
      Stack_Probe : aliased Integer := 0;
   begin
      if Core_Address >= System.Address (Core.CPU_Count)
        or else Slot_Address = 0
        or else Slot_Address > System.Address (Task_Slot'Last)
      then
         Stop;
      end if;
      Dense := Core_Number (Core_Address);
      Task_Slot_Number := Task_Slot (Slot_Address);
      if not Core.Validate_Dispatcher_Stack (Dense, Stack_Probe'Address) then
         Stop;
      end if;
      if Is_Callable (Tasks (Task_Slot_Number).Identity) then
         Stop;
      end if;
      Reference := To_Reference (Tasks (Task_Slot_Number).Identity);
      Enter_Kernel;
      if not Tasks (Task_Slot_Number).Completion_Requested
        or else Core.Assigned_Core_Locked (Reference) /= Dense
        or else Core.State_Locked (Reference) /= Dispatcher.Retiring
      then
         Leave_Kernel;
         Stop;
      end if;
      Core.Finish_Retirement_Locked (Reference);
      System.Tasking.Mark_Terminated (Tasks (Task_Slot_Number).Identity);
      if not Tasks (Task_Slot_Number).Activation_Completed then
         if Tasks (Task_Slot_Number).Group not in
           Integer (Group_Number'First) .. Integer (Group_Number'Last)
         then
            Leave_Kernel;
            Stop;
         end if;
         Group := Group_Number (Tasks (Task_Slot_Number).Group);
         if not Groups (Group).Used or else Groups (Group).Pending = 0 then
            Leave_Kernel;
            Stop;
         end if;
         Groups (Group).Any_Failed := True;
         Groups (Group).Pending := Groups (Group).Pending - 1;
         if Groups (Group).Pending = 0 then
            Core.Resolve_Exact_Locked
              (Groups (Group).Wait, Waits.Object_Wake, Status,
               Activation_Wake_Core);
            if Status /= Waits.Made_Ready then
               Leave_Kernel;
               Stop;
            end if;
            Activation_Wake := True;
         end if;
      end if;
      Master := Master_Number (Tasks (Task_Slot_Number).Master);
      if not Masters (Master).Used or else Masters (Master).Dependents = 0 then
         Leave_Kernel;
         Stop;
      end if;
      Masters (Master).Dependents := Masters (Master).Dependents - 1;
      if not Masters (Master).Open and then Masters (Master).Waiting
        and then Masters (Master).Dependents = 0
      then
         Core.Resolve_Exact_Locked
           (Masters (Master).Wait, Waits.Object_Wake, Status, Wake_Core);
         if Status /= Waits.Made_Ready then
            Leave_Kernel;
            Stop;
         end if;
         Wake := True;
      end if;
      Leave_Kernel;
      if Wake then
         Kick_Core (System.Address (Wake_Core));
      end if;
      if Activation_Wake then
         Kick_Core (System.Address (Activation_Wake_Core));
      end if;
   end Finish_Task_Retirement;
begin
   --  The architecture has validated topology and installed the BSP core
   --  pointer before adainit.  Adopt that state as soon as the task core and
   --  this compiler facade are elaborated, before Soft_Links or application
   --  units can execute tasking operations.
   Core_Initialize (Boot_CPU_Count);
end Flyology.M3_Runtime;
