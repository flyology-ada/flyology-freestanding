--  SPDX-License-Identifier: MIT OR Apache-2.0

with Flyology.Dispatcher_Model;
with Flyology.Clock_Model;
with Flyology.Placement_Model;
with Flyology.Task_Core;
with Flyology.Wait_Arbitration_Model;

package body Flyology.M3_Runtime is
   package Dispatcher renames Flyology.Dispatcher_Model;
   package Clock renames Flyology.Clock_Model;
   package Placement renames Flyology.Placement_Model;
   package Core renames Flyology.Task_Core;
   package Waits renames Flyology.Wait_Arbitration_Model;
   use type Dispatcher.Task_Ref;
   use type Dispatcher.Task_Slot;
   use type Dispatcher.Task_State;
   use type System.Address;
   use type System.Tasking.Task_Id;
   use type System.Tasking.Task_Procedure_Access;
   use type System.Tasking.Boolean_Access;
   use type Waits.Resolve_Status;
   use type Waits.Resolution;
   use type Clock.Tick;

   Max_Cores   : constant := Core.Max_Cores;
   Max_Tasks   : constant := System.Tasking.Max_Tasks;
   Max_Masters : constant := 32;
   Max_Groups  : constant := Max_Tasks;

   subtype Core_Number is Core.Core_Number;
   subtype Task_Slot is Core.Task_Slot;
   type Master_Number is range 1 .. Max_Masters;
   type Group_Number is range 1 .. Max_Groups;
   type Master_Stack is array (Positive range 1 .. 8) of Integer;

   type Task_Record is record
      Identity             : Task_Id := null;
      Body_Procedure       : System.Tasking.Task_Procedure_Access := null;
      Discriminants        : System.Address := System.Null_Address;
      Elaborated           : System.Tasking.Boolean_Access := null;
      Requested_CPU        : Integer := System.Tasking.Unspecified_CPU;
      Priority             : Dispatcher.Priority := Dispatcher.Priority'First;
      Master               : Integer := 0;
      Group                : Integer := 0;
      Activation_Completed : Boolean := False;
      Completion_Requested : Boolean := False;
      Masters              : Master_Stack := [others => 0];
      Master_Depth         : Natural range 0 .. Master_Stack'Last := 0;
      Abort_Depth          : Natural range 0 .. 255 := 0;
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
      Wait      : Core.Wait_Token;
   end record;
   type Group_Array is array (Group_Number) of Group_Record;
   type Boolean_Core_Array is array (Core_Number) of Boolean;
   type Core_Plan is array (Positive range <>) of Core_Number;

   Tasks          : Task_Record_Array;
   Masters        : Master_Array;
   Groups         : Group_Array;
   Placement_Next : Core_Number := 0;

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

   procedure Stop is
   begin
      Report_Failure;
      loop
         null;
      end loop;
   end Stop;

   function To_Reference (Item : Task_Id) return Dispatcher.Task_Ref is
      Slot : Natural;
   begin
      if Item = null then
         return Core.No_Task;
      end if;
      Slot := System.Tasking.Slot_Of (Item);
      if Slot >= Max_Tasks then
         return Core.No_Task;
      end if;
      return (Slot => Dispatcher.Task_Slot (Slot), Incarnation => 1);
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
      Slot      : constant Natural := System.Tasking.Slot_Of (Item);
      Reference : Dispatcher.Task_Ref;
   begin
      if Slot >= Max_Tasks or else Tasks (Task_Slot (Slot)).Identity /= Item then
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
      Created_Task := System.Tasking.Identity_For_Slot (Natural (Slot));
      Tasks (Slot) :=
        (Identity             => Created_Task,
         Body_Procedure       => Body_Procedure,
         Discriminants        => Discriminants,
         Elaborated           => Elaborated,
         Requested_CPU        => CPU,
         Priority             => Effective_Priority,
         Master               => Master,
         Group                => 0,
         Activation_Completed => False,
         Completion_Requested => False,
         Masters              => [others => 0],
         Master_Depth         => 0,
         Abort_Depth          => 1);
      Core.Register_Dormant_Locked (To_Reference (Created_Task));
      Masters (Master_Number (Master)).Dependents :=
        Masters (Master_Number (Master)).Dependents + 1;
      Leave_Kernel;
   end Create_Task;

   procedure Activate_Tasks (Members : Task_List) is
      Dense          : constant Core_Number := Core_Of_Current;
      Activator      : Dispatcher.Task_Ref;
      Activator_Slot : Task_Slot;
      Group          : Group_Number;
      Kicks          : Boolean_Core_Array := [others => False];
      Plan           : Core_Plan (Members'Range);
      Needed         : array (Core_Number) of Natural := [others => 0];
      Cursor         : Placement.Core_Id := Placement.Core_Id (Placement_Next);
      Outcome        : Waits.Resolution;
   begin
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

      --  Validate the complete chain and placement plan before publishing any
      --  Ready transition.  This is the production use of the proved mapping.
      for Index in Members'Range loop
         declare
            Slot : constant Task_Slot := Record_Of (Members (Index));
            CPU  : constant Integer := Tasks (Slot).Requested_CPU;
            Result : Placement.Placement_Result;
         begin
            if Core.State_Locked (To_Reference (Members (Index))) /=
              Dispatcher.Dormant
              or else CPU not in Integer (Placement.Ada_CPU'First) ..
                Integer (Placement.Ada_CPU'Last)
            then
               Leave_Kernel;
               Stop;
            end if;
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
      Core.Arm_Wait_Locked
        (Activator, Waits.Activation_Wait, Groups (Group).Wait);
      for Index in Members'Range loop
         declare
            Slot : constant Task_Slot := Record_Of (Members (Index));
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
      pragma Unreferenced (Activator_Slot);
   end Activate_Tasks;

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
         Groups (Group).Used := False;
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
   begin
      Enter_Kernel;
      Slot := Record_Of (To_Identity (Core.Current_Locked (Dense)));
      if Tasks (Slot).Abort_Depth = 0 then
         Leave_Kernel;
         Stop;
      end if;
      Tasks (Slot).Abort_Depth := Tasks (Slot).Abort_Depth - 1;
      Leave_Kernel;
   end Abort_Undefer;

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
      Masters (Master).Open := False;
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
      Masters (Master).Used := False;
      Masters (Master).Waiting := False;
      Tasks (Slot).Masters (Tasks (Slot).Master_Depth) := 0;
      Tasks (Slot).Master_Depth := Tasks (Slot).Master_Depth - 1;
      Leave_Kernel;
   end Complete_Master;

   function Current_Task return Task_Id is
     (To_Identity (Core.Current (Core_Of_Current)));

   function Is_Callable (Item : Task_Id) return Boolean is
     (Core.Is_Callable (To_Reference (Item)));

   function Is_Terminated (Item : Task_Id) return Boolean is
     (Core.Is_Terminated (To_Reference (Item)));

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

   procedure Delay_For (Interval : Duration) is
      Dense      : constant Core_Number := Core_Of_Current;
      Reference  : Dispatcher.Task_Ref;
      Token      : Core.Wait_Token;
      Outcome    : Waits.Resolution;
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
      Enter_Kernel;
      Reference := Core.Current_Locked (Dense);
      Core.Arm_Wait_Locked (Reference, Waits.Delay_Wait, Token);
      Core.Register_Deadline_Locked (Token, Core.Tick (Deadline));
      Core.Block_Current_And_Release (Dense, Token, Outcome);
      if Outcome /= Waits.Timer_Expiry
        or else Clock.Tick (Core.Read_Clock) < Deadline
      then
         Stop;
      end if;
   end Delay_For;

   procedure Core_Initialize (CPU_Count : System.Address) is
      Environment : Task_Id;
   begin
      if CPU_Count = 0 or else CPU_Count > Max_Cores then
         Stop;
      end if;
      Core.Initialize (Positive (CPU_Count));
      Tasks := [others => (others => <>)];
      Masters := [others => (others => <>)];
      Groups := [others => (others => <>)];
      Placement_Next := 0;
      Environment := System.Tasking.Identity_For_Slot (0);
      Tasks (0).Identity := Environment;
      Enter_Kernel;
      Core.Register_Environment_Locked (To_Reference (Environment));
      Leave_Kernel;
   end Core_Initialize;

   procedure Task_Start (Task_Address : System.Address) is
      Dense     : constant Core_Number := Core_Of_Current;
      Slot      : Task_Slot;
      Reference : Dispatcher.Task_Ref;
      Wake_Core : Core_Number := 0;
      Wake      : Boolean := False;
      Master    : Master_Number;
      Status    : Waits.Resolve_Status;
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
      then
         Leave_Kernel;
         Stop;
      end if;
      Leave_Kernel;
      Tasks (Slot).Body_Procedure (Tasks (Slot).Discriminants);
      if not Tasks (Slot).Completion_Requested then
         Stop;
      end if;
      Enter_Kernel;
      Core.Terminate_Current_Locked (Dense, Reference);
      Master := Master_Number (Tasks (Slot).Master);
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
      Core.Switch_To_Dispatcher (Dense, Reference);
   end Task_Start;
begin
   --  The architecture has validated topology and installed the BSP core
   --  pointer before adainit.  Adopt that state as soon as the task core and
   --  this compiler facade are elaborated, before Soft_Links or application
   --  units can execute tasking operations.
   Core_Initialize (Boot_CPU_Count);
end Flyology.M3_Runtime;
