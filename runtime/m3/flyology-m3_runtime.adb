--  SPDX-License-Identifier: MIT OR Apache-2.0

with Flyology.M2_Architecture;

package body Flyology.M3_Runtime is
   package Architecture renames Flyology.M2_Architecture;
   use type System.Address;
   use type System.Tasking.Task_Id;
   use type System.Tasking.Task_Procedure_Access;
   use type System.Tasking.Boolean_Access;

   Max_Cores             : constant := 4;
   Max_Tasks             : constant := System.Tasking.Max_Tasks;
   Max_Masters           : constant := 32;
   Max_Groups            : constant := Max_Tasks;
   Dispatcher_Stack_Size : constant := 16 * 1_024;
   Task_Stack_Size       : constant := 64 * 1_024;
   Stack_Canary_Length   : constant := 32;

   type Core_Number is range 0 .. Max_Cores - 1;
   type Task_Slot is range 0 .. Max_Tasks - 1;
   type Master_Number is range 1 .. Max_Masters;
   type Group_Number is range 1 .. Max_Groups;
   type Task_State is (Unused, Dormant, Ready, Running, Blocked, Terminated);

   type Stack_Byte is mod 2 ** 8 with Size => 8;
   type Dispatcher_Stack is array
     (Natural range 0 .. Dispatcher_Stack_Size - 1) of Stack_Byte
     with Component_Size => 8, Alignment => 16;
   type Task_Stack is array
     (Natural range 0 .. Task_Stack_Size - 1) of Stack_Byte
     with Component_Size => 8, Alignment => 16;

   type Dispatcher_Stack_Array is
     array (Core_Number) of aliased Dispatcher_Stack;
   type Task_Stack_Array is array (Task_Slot) of aliased Task_Stack;
   type Context_Array is array (Core_Number) of aliased Architecture.Context;

   type Master_Stack is array (Positive range 1 .. 8) of Integer;

   type Task_Record is record
      Identity             : Task_Id := null;
      State                : Task_State := Unused;
      Context              : aliased Architecture.Context;
      Body_Procedure       : System.Tasking.Task_Procedure_Access := null;
      Discriminants        : System.Address := System.Null_Address;
      Elaborated           : System.Tasking.Boolean_Access := null;
      Requested_CPU        : Integer := System.Tasking.Unspecified_CPU;
      Assigned_Core        : Core_Number := 0;
      Master               : Integer := 0;
      Group                 : Integer := 0;
      Activation_Completed : Boolean := False;
      Completion_Requested : Boolean := False;
      Masters              : Master_Stack := [others => 0];
      Master_Depth         : Natural range 0 .. Master_Stack'Last := 0;
      Abort_Depth          : Natural range 0 .. 255 := 0;
   end record;

   type Task_Record_Array is array (Task_Slot) of aliased Task_Record;
   type Task_Id_Array is array (Task_Slot) of Task_Id;

   type Ready_Queue is record
      Items  : Task_Id_Array := [others => null];
      Length : Natural range 0 .. Max_Tasks := 0;
   end record;
   type Ready_Queue_Array is array (Core_Number) of Ready_Queue;
   type Current_Array is array (Core_Number) of Task_Id;
   type Boolean_Core_Array is array (Core_Number) of Boolean;

   type Master_Record is record
      Used       : Boolean := False;
      Open       : Boolean := False;
      Waiting    : Boolean := False;
      Owner      : Task_Id := null;
      Dependents : Natural range 0 .. Max_Tasks := 0;
   end record;
   type Master_Array is array (Master_Number) of Master_Record;

   type Group_Record is record
      Used      : Boolean := False;
      Activator : Task_Id := null;
      Pending   : Natural range 0 .. Max_Tasks := 0;
   end record;
   type Group_Array is array (Group_Number) of Group_Record;

   Dispatcher_Stacks   : Dispatcher_Stack_Array;
   Task_Stacks         : Task_Stack_Array;
   Dispatcher_Contexts : Context_Array;
   Bootstrap_Contexts  : Context_Array;
   Environment_Context : aliased Architecture.Context;
   Dispatcher_Ready    : Boolean_Core_Array := [others => False];

   Tasks          : Task_Record_Array;
   Current        : Current_Array := [others => null];
   Queues         : Ready_Queue_Array;
   Masters        : Master_Array;
   Groups         : Group_Array;
   Configured     : Natural range 0 .. Max_Cores := 0;
   Placement_Next : Core_Number := 0;

   function Current_Core_Raw return System.Address
   with Import, Convention => C, External_Name => "flyology_current_core";

   procedure Enter_Kernel
   with Import, Convention => C, External_Name => "flyology_rts_lock_acquire";

   procedure Leave_Kernel
   with Import, Convention => C, External_Name => "flyology_rts_lock_release";

   procedure Publish_Ready
   with Import, Convention => C,
        External_Name => "flyology_m3_dispatcher_ready";

   procedure Idle
   with Import, Convention => C, External_Name => "flyology_m3_idle";

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

   function Canary_Value (Slot : Task_Slot) return Stack_Byte is
     (Stack_Byte (16#A5# + Natural (Slot)));

   procedure Initialize_Canary (Slot : Task_Slot) is
   begin
      for Index in 0 .. Stack_Canary_Length - 1 loop
         Task_Stacks (Slot) (Index) := Canary_Value (Slot);
      end loop;
   end Initialize_Canary;

   function Canary_Is_Valid (Slot : Task_Slot) return Boolean is
   begin
      for Index in 0 .. Stack_Canary_Length - 1 loop
         if Task_Stacks (Slot) (Index) /= Canary_Value (Slot) then
            return False;
         end if;
      end loop;
      return True;
   end Canary_Is_Valid;

   function Core_Of_Current return Core_Number is
      Raw : constant System.Address := Current_Core_Raw;
   begin
      if Raw >= System.Address (Configured) then
         Stop;
      end if;
      return Core_Number (Raw);
   end Core_Of_Current;

   function Record_Of (Item : Task_Id) return Task_Slot is
      Slot : constant Natural := System.Tasking.Slot_Of (Item);
   begin
      if Slot >= Max_Tasks
        or else Tasks (Task_Slot (Slot)).Identity /= Item
        or else Tasks (Task_Slot (Slot)).State = Unused
      then
         Stop;
      end if;
      return Task_Slot (Slot);
   end Record_Of;

   procedure Enqueue (Item : Task_Id; Core : Core_Number) is
      Queue : Ready_Queue renames Queues (Core);
   begin
      if Item = null or else Queue.Length = Max_Tasks then
         Stop;
      end if;
      for Index in 1 .. Queue.Length loop
         if Queue.Items (Task_Slot (Index - 1)) = Item then
            Stop;
         end if;
      end loop;
      Queue.Items (Task_Slot (Queue.Length)) := Item;
      Queue.Length := Queue.Length + 1;
   end Enqueue;

   function Dequeue (Core : Core_Number) return Task_Id is
      Queue  : Ready_Queue renames Queues (Core);
      Result : Task_Id;
   begin
      if Queue.Length = 0 then
         return null;
      end if;
      Result := Queue.Items (0);
      for Index in 0 .. Queue.Length - 2 loop
         Queue.Items (Task_Slot (Index)) :=
           Queue.Items (Task_Slot (Index + 1));
      end loop;
      Queue.Length := Queue.Length - 1;
      Queue.Items (Task_Slot (Queue.Length)) := null;
      return Result;
   end Dequeue;

   procedure Make_Ready (Item : Task_Id; Kick : out Core_Number) is
      Slot : constant Task_Slot := Record_Of (Item);
   begin
      if Tasks (Slot).State /= Blocked then
         Stop;
      end if;
      Tasks (Slot).State := Ready;
      Enqueue (Item, Tasks (Slot).Assigned_Core);
      Kick := Tasks (Slot).Assigned_Core;
   end Make_Ready;

   procedure Block_Current (Core : Core_Number; Slot : Task_Slot) is
   begin
      if Current (Core) /= Tasks (Slot).Identity
        or else Tasks (Slot).State /= Running
      then
         Stop;
      end if;
      Tasks (Slot).State := Blocked;
      Current (Core) := null;
      Leave_Kernel;
      Architecture.Switch
        (Tasks (Slot).Context'Access, Dispatcher_Contexts (Core)'Access);
      if Tasks (Slot).State /= Running
        or else Current (Core) /= Tasks (Slot).Identity
      then
         Stop;
      end if;
   end Block_Current;

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
      CPU            : Integer;
      Master         : Integer;
      Created_Task   : out Task_Id)
   is
      Slot : Task_Slot := 1;
      Found : Boolean := False;
   begin
      if Body_Procedure = null or else Elaborated = null
        or else Master not in Integer (Master_Number'First) ..
          Integer (Master_Number'Last)
      then
         Stop;
      end if;
      Enter_Kernel;
      for Candidate in Task_Slot range 1 .. Task_Slot'Last loop
         if Tasks (Candidate).State = Unused then
            Slot := Candidate;
            Found := True;
            exit;
         end if;
      end loop;
      if not Found
        or else not Masters (Master_Number (Master)).Used
        or else not Masters (Master_Number (Master)).Open
      then
         Leave_Kernel;
         Stop;
      end if;
      Created_Task := System.Tasking.Identity_For_Slot (Natural (Slot));
      Tasks (Slot).Identity := Created_Task;
      Tasks (Slot).State := Dormant;
      Tasks (Slot).Body_Procedure := Body_Procedure;
      Tasks (Slot).Discriminants := Discriminants;
      Tasks (Slot).Elaborated := Elaborated;
      Tasks (Slot).Requested_CPU := CPU;
      Tasks (Slot).Master := Master;
      Tasks (Slot).Group := 0;
      Tasks (Slot).Activation_Completed := False;
      Tasks (Slot).Completion_Requested := False;
      Tasks (Slot).Master_Depth := 0;
      Tasks (Slot).Abort_Depth := 1;
      Masters (Master_Number (Master)).Dependents :=
        Masters (Master_Number (Master)).Dependents + 1;
      Leave_Kernel;
   end Create_Task;

   procedure Activate_Tasks (Members : Task_List) is
      Core        : constant Core_Number := Core_Of_Current;
      Activator   : constant Task_Id := Current (Core);
      Activator_Slot : constant Task_Slot := Record_Of (Activator);
      Group       : Group_Number;
      Target      : Core_Number;
      Kicks       : Boolean_Core_Array := [others => False];
      Slot        : Task_Slot;
   begin
      if Members'Length = 0 then
         return;
      end if;
      Enter_Kernel;
      if Tasks (Activator_Slot).State /= Running then
         Leave_Kernel;
         Stop;
      end if;
      for Index in Members'Range loop
         Slot := Record_Of (Members (Index));
         if Tasks (Slot).State /= Dormant then
            Leave_Kernel;
            Stop;
         end if;
         if Tasks (Slot).Requested_CPU > Configured
           or else Tasks (Slot).Requested_CPU < System.Tasking.Unspecified_CPU
         then
            Leave_Kernel;
            Stop;
         end if;
      end loop;
      Group := Allocate_Group;
      Groups (Group).Activator := Activator;
      Groups (Group).Pending := Members'Length;
      for Index in Members'Range loop
         Slot := Record_Of (Members (Index));
         if Tasks (Slot).Requested_CPU in
           System.Tasking.Unspecified_CPU | 0
         then
            Target := Placement_Next;
            if Natural (Placement_Next) + 1 = Configured then
               Placement_Next := 0;
            else
               Placement_Next := Core_Number'Succ (Placement_Next);
            end if;
         else
            Target := Core_Number (Tasks (Slot).Requested_CPU - 1);
         end if;
         Tasks (Slot).Assigned_Core := Target;
         Tasks (Slot).Group := Integer (Group);
         Tasks (Slot).State := Ready;
         declare
            Base : constant System.Address :=
              Task_Stacks (Slot) (Task_Stack'First)'Address;
         begin
            Initialize_Canary (Slot);
            Architecture.Initialize
              (Tasks (Slot).Context,
               Base + System.Address (Task_Stack_Size),
               Tasks (Slot)'Address);
         end;
         Enqueue (Tasks (Slot).Identity, Target);
         Kicks (Target) := True;
      end loop;
      Tasks (Activator_Slot).State := Blocked;
      Current (Core) := null;
      Leave_Kernel;
      for Candidate in Core_Number loop
         if Natural (Candidate) < Configured and then Kicks (Candidate) then
            Kick_Core (System.Address (Candidate));
         end if;
      end loop;
      Architecture.Switch
        (Tasks (Activator_Slot).Context'Access,
         Dispatcher_Contexts (Core)'Access);
      if Tasks (Activator_Slot).State /= Running then
         Stop;
      end if;
   end Activate_Tasks;

   procedure Complete_Activation is
      Core : constant Core_Number := Core_Of_Current;
      Item : constant Task_Id := Current (Core);
      Slot : constant Task_Slot := Record_Of (Item);
      Group : Group_Number;
      Wake_Core : Core_Number := 0;
      Wake : Boolean := False;
   begin
      Enter_Kernel;
      if Tasks (Slot).State /= Running
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
         Make_Ready (Groups (Group).Activator, Wake_Core);
         Wake := True;
         Groups (Group).Used := False;
      end if;
      Leave_Kernel;
      if Wake then
         Kick_Core (System.Address (Wake_Core));
      end if;
   end Complete_Activation;

   procedure Complete_Task is
      Core : constant Core_Number := Core_Of_Current;
      Slot : constant Task_Slot := Record_Of (Current (Core));
   begin
      Enter_Kernel;
      if Tasks (Slot).State /= Running
        or else Tasks (Slot).Completion_Requested
      then
         Leave_Kernel;
         Stop;
      end if;
      Tasks (Slot).Completion_Requested := True;
      Leave_Kernel;
   end Complete_Task;

   procedure Abort_Defer is
      Core : constant Core_Number := Core_Of_Current;
      Slot : constant Task_Slot := Record_Of (Current (Core));
   begin
      if Tasks (Slot).Abort_Depth = 255 then
         Stop;
      end if;
      Tasks (Slot).Abort_Depth := Tasks (Slot).Abort_Depth + 1;
   end Abort_Defer;

   procedure Abort_Undefer is
      Core : constant Core_Number := Core_Of_Current;
      Slot : constant Task_Slot := Record_Of (Current (Core));
   begin
      if Tasks (Slot).Abort_Depth = 0 then
         Stop;
      end if;
      Tasks (Slot).Abort_Depth := Tasks (Slot).Abort_Depth - 1;
   end Abort_Undefer;

   procedure Enter_Master is
      Core : constant Core_Number := Core_Of_Current;
      Owner : constant Task_Id := Current (Core);
      Slot : constant Task_Slot := Record_Of (Owner);
      New_Master : Master_Number := Master_Number'First;
   begin
      Enter_Kernel;
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
         Owner => Owner, Dependents => 0);
      Tasks (Slot).Master_Depth := Tasks (Slot).Master_Depth + 1;
      Tasks (Slot).Masters (Tasks (Slot).Master_Depth) :=
        Integer (New_Master);
      Leave_Kernel;
   end Enter_Master;

   function Current_Master return Integer is
      Core : constant Core_Number := Core_Of_Current;
      Slot : constant Task_Slot := Record_Of (Current (Core));
   begin
      if Tasks (Slot).Master_Depth = 0 then
         Stop;
      end if;
      return Tasks (Slot).Masters (Tasks (Slot).Master_Depth);
   end Current_Master;

   procedure Complete_Master is
      Core : constant Core_Number := Core_Of_Current;
      Owner : constant Task_Id := Current (Core);
      Slot : constant Task_Slot := Record_Of (Owner);
      Master : Master_Number;
   begin
      Enter_Kernel;
      if Tasks (Slot).Master_Depth = 0 then
         Leave_Kernel;
         Stop;
      end if;
      Master := Master_Number
        (Tasks (Slot).Masters (Tasks (Slot).Master_Depth));
      if not Masters (Master).Used or else Masters (Master).Owner /= Owner then
         Leave_Kernel;
         Stop;
      end if;
      Masters (Master).Open := False;
      if Masters (Master).Dependents > 0 then
         Masters (Master).Waiting := True;
         Block_Current (Core, Slot);
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
      Core : constant Core_Number := Core_Of_Current;
   begin
      return Current (Core);
   end Current_Task;

   function Is_Callable (Item : Task_Id) return Boolean is
      Slot : Natural;
   begin
      if Item = null then
         return False;
      end if;
      Slot := System.Tasking.Slot_Of (Item);
      return Slot < Max_Tasks
        and then Tasks (Task_Slot (Slot)).Identity = Item
        and then Tasks (Task_Slot (Slot)).State not in Unused | Terminated;
   end Is_Callable;

   function Is_Terminated (Item : Task_Id) return Boolean is
      Slot : Natural;
   begin
      if Item = null then
         return False;
      end if;
      Slot := System.Tasking.Slot_Of (Item);
      return Slot < Max_Tasks
        and then Tasks (Task_Slot (Slot)).Identity = Item
        and then Tasks (Task_Slot (Slot)).State = Terminated;
   end Is_Terminated;

   function Number_Of_CPUs return Natural is (Configured);

   function Current_Core_Number return Natural is
     (Natural (Core_Of_Current));

   function Validate_Current_Stack (Probe : System.Address) return Boolean is
      Core : constant Core_Number := Core_Of_Current;
      Slot : constant Task_Slot := Record_Of (Current (Core));
      Base : constant System.Address :=
        Task_Stacks (Slot) (Task_Stack'First)'Address;
   begin
      return Slot /= 0
        and then Base <= System.Address'Last - System.Address (Task_Stack_Size)
        and then Probe >= Base + System.Address (Stack_Canary_Length)
        and then Probe < Base + System.Address (Task_Stack_Size)
        and then Canary_Is_Valid (Slot);
   end Validate_Current_Stack;

   procedure Demo_Parallel_Barrier (Phase : Positive) is
   begin
      if Configured = 4 then
         Parallel_Barrier (System.Address (Phase));
      end if;
   end Demo_Parallel_Barrier;

   procedure Core_Initialize (CPU_Count : System.Address) is
      Environment : Task_Id;
   begin
      if CPU_Count = 0 or else CPU_Count > Max_Cores then
         Stop;
      end if;
      Configured := Natural (CPU_Count);
      Placement_Next := 0;
      Current := [others => null];
      Queues := [others => (Items => [others => null], Length => 0)];
      Masters := [others => (others => <>)];
      Groups := [others => (others => <>)];
      Dispatcher_Ready := [others => False];
      for Slot in Task_Slot loop
         Tasks (Slot).Identity := null;
         Tasks (Slot).State := Unused;
         Tasks (Slot).Master_Depth := 0;
      end loop;
      Environment := System.Tasking.Identity_For_Slot (0);
      Tasks (0).Identity := Environment;
      Tasks (0).State := Running;
      Tasks (0).Assigned_Core := 0;
      Tasks (0).Abort_Depth := 0;
      Current (0) := Environment;
   end Core_Initialize;

   procedure Initialize_Dispatcher (Core : Core_Number) is
      Base : constant System.Address :=
        Dispatcher_Stacks (Core) (Dispatcher_Stack'First)'Address;
   begin
      Architecture.Initialize_Dispatcher
        (Dispatcher_Contexts (Core),
         Base + System.Address (Dispatcher_Stack_Size),
         System.Address (Core));
   end Initialize_Dispatcher;

   procedure Prepare_Environment (Core : System.Address) is
   begin
      if Core /= 0 or else Configured = 0 or else Dispatcher_Ready (0) then
         Stop;
      end if;
      Initialize_Dispatcher (0);
      Dispatcher_Ready (0) := True;
      Publish_Ready;
   end Prepare_Environment;

   procedure Prepare_AP (Core : System.Address) is
      Dense : Core_Number;
   begin
      if Core = 0 or else Core >= System.Address (Configured) then
         Stop;
      end if;
      Dense := Core_Number (Core);
      if Dispatcher_Ready (Dense) then
         Stop;
      end if;
      Initialize_Dispatcher (Dense);
      Architecture.Switch
        (Bootstrap_Contexts (Dense)'Access,
         Dispatcher_Contexts (Dense)'Access);
      Stop;
   end Prepare_AP;

   procedure Dispatcher_Start (Core : System.Address) is
      Dense : Core_Number;
      Next  : Task_Id;
      Slot  : Task_Slot;
   begin
      if Core >= System.Address (Configured) then
         Stop;
      end if;
      Dense := Core_Number (Core);
      if Dense /= 0 then
         if Dispatcher_Ready (Dense) then
            Stop;
         end if;
         Dispatcher_Ready (Dense) := True;
         Publish_Ready;
      elsif not Dispatcher_Ready (Dense) then
         Stop;
      end if;
      loop
         Enter_Kernel;
         Next := Dequeue (Dense);
         if Next = null then
            Leave_Kernel;
            Idle;
         else
            Slot := Record_Of (Next);
            if Tasks (Slot).State /= Ready or else Current (Dense) /= null
              or else Tasks (Slot).Assigned_Core /= Dense
            then
               Leave_Kernel;
               Stop;
            end if;
            Tasks (Slot).State := Running;
            Current (Dense) := Next;
            Leave_Kernel;
            Architecture.Switch
              (Dispatcher_Contexts (Dense)'Access,
               Tasks (Slot).Context'Access);
            if Slot /= 0 and then not Canary_Is_Valid (Slot) then
               Stop;
            end if;
         end if;
      end loop;
   end Dispatcher_Start;

   procedure Task_Start (Task_Address : System.Address) is
      Core : constant Core_Number := Core_Of_Current;
      Slot : Task_Slot := 1;
      Wake_Core : Core_Number := 0;
      Wake : Boolean := False;
      Master : Master_Number;
   begin
      while Slot < Task_Slot'Last
        and then Tasks (Slot)'Address /= Task_Address
      loop
         Slot := Task_Slot'Succ (Slot);
      end loop;
      if Tasks (Slot)'Address /= Task_Address
        or else Tasks (Slot).State /= Running
        or else Current (Core) /= Tasks (Slot).Identity
        or else Tasks (Slot).Body_Procedure = null
      then
         Stop;
      end if;
      if not Canary_Is_Valid (Slot) then
         Stop;
      end if;
      Tasks (Slot).Body_Procedure (Tasks (Slot).Discriminants);
      if not Tasks (Slot).Completion_Requested
        or else not Canary_Is_Valid (Slot)
      then
         Stop;
      end if;
      Enter_Kernel;
      if Current (Core) /= Tasks (Slot).Identity
        or else Tasks (Slot).State /= Running
      then
         Leave_Kernel;
         Stop;
      end if;
      Tasks (Slot).State := Terminated;
      Current (Core) := null;
      Master := Master_Number (Tasks (Slot).Master);
      if not Masters (Master).Used or else Masters (Master).Dependents = 0 then
         Leave_Kernel;
         Stop;
      end if;
      Masters (Master).Dependents := Masters (Master).Dependents - 1;
      if not Masters (Master).Open
        and then Masters (Master).Waiting
        and then Masters (Master).Dependents = 0
      then
         Make_Ready (Masters (Master).Owner, Wake_Core);
         Wake := True;
      end if;
      Leave_Kernel;
      if Wake then
         Kick_Core (System.Address (Wake_Core));
      end if;
      Architecture.Switch
        (Tasks (Slot).Context'Access, Dispatcher_Contexts (Core)'Access);
      Stop;
   end Task_Start;

   procedure Environment_Complete is
   begin
      Enter_Kernel;
      if Current (0) /= Tasks (0).Identity
        or else Tasks (0).State /= Running
      then
         Leave_Kernel;
         Stop;
      end if;
      Tasks (0).State := Terminated;
      Current (0) := null;
      Leave_Kernel;
      Architecture.Switch
        (Environment_Context'Access, Dispatcher_Contexts (0)'Access);
      Stop;
   end Environment_Complete;
end Flyology.M3_Runtime;
