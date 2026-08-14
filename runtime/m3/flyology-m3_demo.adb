--  SPDX-License-Identifier: MIT OR Apache-2.0

with Ada.Dynamic_Priorities;
with Ada.Real_Time;
with Ada.Task_Identification;
with Ada.Unchecked_Deallocation;
with Flyology.M3_Runtime;
with System.Multiprocessors;

package body Flyology.M3_Demo is
   use type Ada.Task_Identification.Task_Id;

   type Abort_Query_Count is mod 2 ** 64 with Convention => C;

   function Abort_Cleanup_Query_Count return Abort_Query_Count
   with Import, Convention => C,
        External_Name => "flyology_abort_cleanup_query_count";

   procedure Report_Failure
   with Import, Convention => C,
        External_Name => "flyology_m2_report_failure";

   procedure Report_Free_Wait_Pass
   with Import, Convention => C,
        External_Name => "flyology_m4_report_free_wait_pass";

   procedure Report_Free_Abort_Race_Pass
   with Import, Convention => C,
        External_Name => "flyology_m4_report_free_abort_race_pass";

   type Done_Array is array (Positive range 1 .. 4) of Boolean
     with Atomic_Components;
   type Identity_Array is array (Positive range 1 .. 4) of
     Ada.Task_Identification.Task_Id with Atomic_Components;
   type Core_Array is array (Positive range 1 .. 4) of Natural
     with Atomic_Components;
   type Stack_Probe_Array is array (Natural range 0 .. 255) of Character;
   type Counter_Pair is array (Positive range 1 .. 2) of Natural;
   type Service_Log_Array is array (Positive range 1 .. 64) of Natural;

   Ceiling_Body_Ran : Boolean := False with Atomic;
   Ceiling_Check_Failed : Boolean := False with Atomic;

   protected Nested_Ceiling_Probe with Priority => 10 is
      procedure Observe;
   end Nested_Ceiling_Probe;

   protected body Nested_Ceiling_Probe is
      procedure Observe is
      begin
         if Flyology.M3_Runtime.Current_Active_Priority /= 10 then
            Ceiling_Check_Failed := True;
         end if;
      end Observe;
   end Nested_Ceiling_Probe;

   protected Ceiling_Probe with Priority => 8 is
      procedure Change_Base;
   end Ceiling_Probe;

   protected body Ceiling_Probe is
      procedure Change_Base is
      begin
         Ceiling_Body_Ran := True;
         if Flyology.M3_Runtime.Current_Active_Priority /= 8 then
            Ceiling_Check_Failed := True;
         end if;
         Ada.Dynamic_Priorities.Set_Priority (3);
         if Ada.Dynamic_Priorities.Get_Priority /= 3
           or else Flyology.M3_Runtime.Current_Active_Priority /= 8
         then
            Ceiling_Check_Failed := True;
         end if;
         Nested_Ceiling_Probe.Observe;
         if Flyology.M3_Runtime.Current_Active_Priority /= 8 then
            Ceiling_Check_Failed := True;
         end if;
      end Change_Base;
   end Ceiling_Probe;

   protected Priority_Run_Log is
      procedure Note (Index : Positive);
      function Order (Position : Positive) return Natural;
   private
      Count : Natural := 0;
      Log   : Service_Log_Array := [others => 0];
   end Priority_Run_Log;

   protected body Priority_Run_Log is
      procedure Note (Index : Positive) is
      begin
         Count := Count + 1;
         Log (Count) := Index;
      end Note;

      function Order (Position : Positive) return Natural is
        (Log (Position));
   end Priority_Run_Log;

   protected Shared_Counter is
      procedure Increment;
      function Value return Natural;
   private
      Counts : Counter_Pair := [others => 0];
   end Shared_Counter;

   protected body Shared_Counter is
      procedure Increment is
      begin
         Counts (1) := Counts (1) + 1;
         Counts (2) := Counts (2) + 1;
      end Increment;

      function Value return Natural is (Counts (1) + Counts (2));
   end Shared_Counter;

   Protected_Entry_Done : Done_Array := [others => False];
   Priority_Worker_Id : Identity_Array :=
     [others => Ada.Task_Identification.Null_Task_Id];

   protected Protected_Gate is
      procedure Open;
      procedure Close;
      entry Wait (Index : Positive);
      entry Fail;
      function Service_Order (Index : Positive) return Natural;
      function Services return Natural;
      function Waiting return Natural;
      function Failing return Natural;
   private
      Opened        : Boolean := False;
      Service_Count : Natural := 0;
      Service_Log   : Service_Log_Array := [others => 0];
   end Protected_Gate;

   protected body Protected_Gate is
      procedure Open is
      begin
         Opened := True;
      end Open;

      procedure Close is
      begin
         Opened := False;
      end Close;

      entry Wait (Index : Positive) when Opened is
      begin
         Service_Count := Service_Count + 1;
         Service_Log (Service_Count) := Index;
      end Wait;

      entry Fail when Opened is
      begin
         raise Program_Error;
      end Fail;

      function Service_Order (Index : Positive) return Natural is
        (Service_Log (Index));

      function Services return Natural is (Service_Count);

      function Waiting return Natural is (Wait'Count);
      function Failing return Natural is (Fail'Count);
   end Protected_Gate;

   Auto_Done     : Done_Array := [others => False];
   Specific_Done : Done_Array := [others => False];
   Auto_Id       : Identity_Array :=
     [others => Ada.Task_Identification.Null_Task_Id];
   Specific_Id   : Identity_Array :=
     [others => Ada.Task_Identification.Null_Task_Id];
   Auto_Core     : Core_Array := [others => Natural'Last];
   Specific_Core : Core_Array := [others => Natural'Last];
   Reclaim_Done   : Done_Array := [others => False];
   Reclaim_Id     : Identity_Array :=
     [others => Ada.Task_Identification.Null_Task_Id];
   Nested_Parent_Done : Boolean := False with Atomic;
   Nested_Child_Done  : Boolean := False with Atomic;
   Nested_Parent_Id : Ada.Task_Identification.Task_Id :=
     Ada.Task_Identification.Null_Task_Id with Atomic;
   Nested_Child_Id : Ada.Task_Identification.Task_Id :=
     Ada.Task_Identification.Null_Task_Id with Atomic;
   Nested_Child_Object_Id : Ada.Task_Identification.Task_Id :=
     Ada.Task_Identification.Null_Task_Id with Atomic;
   Dynamic_Done : Boolean := False with Atomic;
   Dynamic_Id : Ada.Task_Identification.Task_Id :=
     Ada.Task_Identification.Null_Task_Id with Atomic;
   Free_Started : Boolean := False with Atomic;
   Free_Release : Boolean := False with Atomic;
   Free_Target_Continued : Boolean := False with Atomic;
   Free_Race_Nulled : Boolean := False with Atomic;
   Free_Race_Continued : Boolean := False with Atomic;
   Free_Id : Ada.Task_Identification.Task_Id :=
     Ada.Task_Identification.Null_Task_Id with Atomic;
   Free_Race_Id : Ada.Task_Identification.Task_Id :=
     Ada.Task_Identification.Null_Task_Id with Atomic;
   Selective_Done : Boolean := False with Atomic;
   Terminate_Started : Done_Array := [others => False];
   Terminate_Continued : Done_Array := [others => False];
   Terminate_User_Handler_Ran : Done_Array := [others => False];
   Terminate_Selected_Early : Boolean := False with Atomic;
   Terminate_Ids : Identity_Array :=
     [others => Ada.Task_Identification.Null_Task_Id];
   Abort_Started : Boolean := False with Atomic;
   Abort_Continued : Boolean := False with Atomic;
   Abort_User_Handler_Ran : Boolean := False with Atomic;
   Abort_Id : Ada.Task_Identification.Task_Id :=
     Ada.Task_Identification.Null_Task_Id with Atomic;
   Multi_Abort_Started : Done_Array := [others => False];
   Multi_Abort_Continued : Done_Array := [others => False];
   Multi_Abort_Ids : Identity_Array :=
     [others => Ada.Task_Identification.Null_Task_Id];
   Dependent_Abort_Parent_Started : Boolean := False with Atomic;
   Dependent_Abort_Child_Started : Boolean := False with Atomic;
   Dependent_Abort_Parent_Continued : Boolean := False with Atomic;
   Dependent_Abort_Child_Continued : Boolean := False with Atomic;
   Dependent_Abort_Parent_Id : Ada.Task_Identification.Task_Id :=
     Ada.Task_Identification.Null_Task_Id with Atomic;
   Dependent_Abort_Child_Id : Ada.Task_Identification.Task_Id :=
     Ada.Task_Identification.Null_Task_Id with Atomic;
   Abort_Call_Started : Boolean := False with Atomic;
   Abort_Call_Continued : Boolean := False with Atomic;
   Abort_Call_Id : Ada.Task_Identification.Task_Id :=
     Ada.Task_Identification.Null_Task_Id with Atomic;
   Abort_Accept_Entered : Boolean := False with Atomic;
   Abort_Timed_Started : Boolean := False with Atomic;
   Abort_Timed_Accepted : Boolean := False with Atomic;
   Abort_Timed_Out : Boolean := False with Atomic;
   Abort_Timed_Continued : Boolean := False with Atomic;
   Abort_Timed_Id : Ada.Task_Identification.Task_Id :=
     Ada.Task_Identification.Null_Task_Id with Atomic;
   Abort_Protected_Started : Boolean := False with Atomic;
   Abort_Protected_Continued : Boolean := False with Atomic;
   Abort_Protected_Id : Ada.Task_Identification.Task_Id :=
     Ada.Task_Identification.Null_Task_Id with Atomic;
   Abort_Timed_Protected_Started : Boolean := False with Atomic;
   Abort_Timed_Protected_Accepted : Boolean := False with Atomic;
   Abort_Timed_Protected_Timed_Out : Boolean := False with Atomic;
   Abort_Timed_Protected_Continued : Boolean := False with Atomic;
   Abort_Timed_Protected_Id : Ada.Task_Identification.Task_Id :=
     Ada.Task_Identification.Null_Task_Id with Atomic;
   Collision_Call_Started : Boolean := False with Atomic;
   Collision_Call_Accepted : Boolean := False with Atomic;
   Collision_Call_Timed_Out : Boolean := False with Atomic;
   Collision_Call_Continued : Boolean := False with Atomic;
   Collision_Call_Id : Ada.Task_Identification.Task_Id :=
     Ada.Task_Identification.Null_Task_Id with Atomic;
   Collision_Server_Accepted : Boolean := False with Atomic;
   Collision_Server_Completed : Boolean := False with Atomic;
   Collision_Server_Accept_Count : Natural := 0 with Atomic;
   Exceptional_Protected_Caught : Boolean := False with Atomic;
   Exceptional_Rendezvous_Caller_Caught : Boolean := False with Atomic;
   Exceptional_Rendezvous_Server_Caught : Boolean := False with Atomic;
   Exception_Abort_Accepted : Boolean := False with Atomic;
   Exception_Abort_Release : Boolean := False with Atomic;
   Exception_Abort_Caller_Started : Boolean := False with Atomic;
   Exception_Abort_Caller_Caught : Boolean := False with Atomic;
   Exception_Abort_Caller_Continued : Boolean := False with Atomic;
   Exception_Abort_Server_Caught : Boolean := False with Atomic;
   Exception_Abort_Caller_Id : Ada.Task_Identification.Task_Id :=
     Ada.Task_Identification.Null_Task_Id with Atomic;
   Exception_Abort_Protected_Started : Boolean := False with Atomic;
   Exception_Abort_Protected_Caught : Boolean := False with Atomic;
   Exception_Abort_Protected_Continued : Boolean := False with Atomic;
   Exception_Abort_Protected_Id : Ada.Task_Identification.Task_Id :=
     Ada.Task_Identification.Null_Task_Id with Atomic;
   Unactivated_Ran : Boolean := False with Atomic;
   Activation_Sibling_Ran : Boolean := False with Atomic;
   Activation_Failed_Body_Ran : Boolean := False with Atomic;

   task type Specific_Worker_Type
     (CPU_Number : System.Multiprocessors.CPU_Range;
      Index      : Positive)
     with CPU => CPU_Number;

   task type Auto_Worker_Type (Index : Positive);
   task type Reclaim_Worker_Type (Index : Positive);
   task type Nested_Child_Type;
   task type Nested_Parent_Type;
   task type Rendezvous_Server_Type
     (CPU_Number : System.Multiprocessors.CPU_Range)
     with CPU => CPU_Number
   is
      entry Ping (Value : in out Integer);
   end Rendezvous_Server_Type;

   task type Delayed_Rendezvous_Server_Type is
      entry Ping;
   end Delayed_Rendezvous_Server_Type;

   task type Timed_Rendezvous_Server_Type is
      entry Ping (Value : in out Integer);
   end Timed_Rendezvous_Server_Type;

   task type Exceptional_Rendezvous_Server_Type
     (CPU_Number : System.Multiprocessors.CPU_Range)
     with CPU => CPU_Number
   is
      entry Ping;
   end Exceptional_Rendezvous_Server_Type;

   task type Exception_Abort_Server_Type
     (CPU_Number : System.Multiprocessors.CPU_Range)
     with CPU => CPU_Number
   is
      entry Ping;
   end Exception_Abort_Server_Type;

   task type Exception_Abort_Client_Type
     (CPU_Number : System.Multiprocessors.CPU_Range;
      Server     : not null access Exception_Abort_Server_Type)
     with CPU => CPU_Number;

   task type Dynamic_Worker_Type;
   type Dynamic_Worker_Access is access Dynamic_Worker_Type;

   task type Free_Hold_Server_Type is
      entry Hold;
   end Free_Hold_Server_Type;

   task type Free_Worker_Type
     (CPU_Number : System.Multiprocessors.CPU_Range;
      Server     : not null access Free_Hold_Server_Type)
     with CPU => CPU_Number;
   type Free_Worker_Access is access Free_Worker_Type;
   procedure Free_Worker is new Ada.Unchecked_Deallocation
     (Free_Worker_Type, Free_Worker_Access);
   Race_Target : Free_Worker_Access := null;

   task type Free_Release_Type;
   task type Free_Race_Client_Type
     (CPU_Number : System.Multiprocessors.CPU_Range)
     with CPU => CPU_Number;

   task type Selective_Server_Type is
      entry Ping;
   end Selective_Server_Type;

   task type Terminate_Server_Type
     (CPU_Number : System.Multiprocessors.CPU_Range;
      Index      : Positive)
     with CPU => CPU_Number
   is
      entry Ping;
      pragma Unreferenced (Ping);
   end Terminate_Server_Type;

   task type Abort_Worker_Type
     (CPU_Number : System.Multiprocessors.CPU_Range)
     with CPU => CPU_Number;

   task type Multi_Abort_Worker_Type
     (CPU_Number : System.Multiprocessors.CPU_Range;
      Index      : Positive)
     with CPU => CPU_Number;

   task type Dependent_Abort_Parent_Type
     (CPU_Number : System.Multiprocessors.CPU_Range)
     with CPU => CPU_Number;

   task type Dependent_Abort_Child_Type
     (CPU_Number : System.Multiprocessors.CPU_Range)
     with CPU => CPU_Number;

   task type Abort_Rendezvous_Server_Type
     (CPU_Number         : System.Multiprocessors.CPU_Range;
      Delay_Before_Accept : Boolean)
     with CPU => CPU_Number
   is
      entry Ping;
   end Abort_Rendezvous_Server_Type;

   task type Abort_Rendezvous_Client_Type
     (CPU_Number : System.Multiprocessors.CPU_Range;
      Server     : not null access Abort_Rendezvous_Server_Type)
     with CPU => CPU_Number;

   task type Abort_Timed_Client_Type
     (CPU_Number : System.Multiprocessors.CPU_Range;
      Server     : not null access Abort_Rendezvous_Server_Type)
     with CPU => CPU_Number;

   task type Protected_Entry_Worker_Type
     (CPU_Number : System.Multiprocessors.CPU_Range;
      Index      : Positive)
     with CPU => CPU_Number;

   task type Abort_Protected_Worker_Type
     (CPU_Number : System.Multiprocessors.CPU_Range)
     with CPU => CPU_Number;

   task type Abort_Timed_Protected_Worker_Type
     (CPU_Number : System.Multiprocessors.CPU_Range;
      Timeout_Milliseconds : Positive)
     with CPU => CPU_Number;

   task type Collision_Rendezvous_Server_Type
     (CPU_Number  : System.Multiprocessors.CPU_Range;
      Accept_Delay_Milliseconds : Natural;
      Hold_Milliseconds         : Natural)
     with CPU => CPU_Number
   is
      entry Ping;
   end Collision_Rendezvous_Server_Type;

   task type Collision_Rendezvous_Client_Type
     (CPU_Number : System.Multiprocessors.CPU_Range;
      Server     : not null access Collision_Rendezvous_Server_Type;
      Timeout_Milliseconds : Positive)
     with CPU => CPU_Number;

   task type Exceptional_Protected_Worker_Type
     (CPU_Number : System.Multiprocessors.CPU_Range)
     with CPU => CPU_Number;

   task type Exception_Abort_Protected_Worker_Type
     (CPU_Number : System.Multiprocessors.CPU_Range)
     with CPU => CPU_Number;

   task type Unactivated_Worker_Type;
   task type Failed_Activation_Worker_Type;
   task type Activation_Sibling_Worker_Type;

   function Fail_Before_Activation return Integer;

   task body Specific_Worker_Type is
      Self : constant Ada.Task_Identification.Task_Id :=
        Ada.Task_Identification.Current_Task;
      Core : constant Natural := Flyology.M3_Runtime.Current_Core_Number;
      Stack_Probe : aliased Stack_Probe_Array := [others => 'S'];
   begin
      if Self = Ada.Task_Identification.Null_Task_Id
        or else not Ada.Task_Identification.Is_Callable (Self)
        or else Ada.Task_Identification.Is_Terminated (Self)
        or else Core + 1 /= Natural (CPU_Number)
        or else not Flyology.M3_Runtime.Validate_Current_Stack
          (Stack_Probe'Address)
      then
         raise Program_Error;
      end if;
      Specific_Id (Index) := Self;
      Specific_Core (Index) := Core;
      Flyology.M3_Runtime.Demo_Parallel_Barrier (1);
      Specific_Done (Index) := True;
   end Specific_Worker_Type;

   task body Auto_Worker_Type is
      Self : constant Ada.Task_Identification.Task_Id :=
        Ada.Task_Identification.Current_Task;
      Stack_Probe : aliased Stack_Probe_Array := [others => 'A'];
   begin
      if Self = Ada.Task_Identification.Null_Task_Id
        or else not Ada.Task_Identification.Is_Callable (Self)
        or else Ada.Task_Identification.Is_Terminated (Self)
        or else not Flyology.M3_Runtime.Validate_Current_Stack
          (Stack_Probe'Address)
      then
         raise Program_Error;
      end if;
      Auto_Id (Index) := Self;
      Auto_Core (Index) := Flyology.M3_Runtime.Current_Core_Number;
      Flyology.M3_Runtime.Demo_Parallel_Barrier (2);
      delay 0.001;
      Shared_Counter.Increment;
      Auto_Done (Index) := True;
   end Auto_Worker_Type;

   task body Reclaim_Worker_Type is
      Self : constant Ada.Task_Identification.Task_Id :=
        Ada.Task_Identification.Current_Task;
      Stack_Probe : aliased Stack_Probe_Array := [others => 'R'];
   begin
      if Self = Ada.Task_Identification.Null_Task_Id
        or else not Flyology.M3_Runtime.Validate_Current_Stack
          (Stack_Probe'Address)
      then
         raise Program_Error;
      end if;
      Reclaim_Id (Index) := Self;
      Reclaim_Done (Index) := True;
   end Reclaim_Worker_Type;

   task body Nested_Child_Type is
      Self : constant Ada.Task_Identification.Task_Id :=
        Ada.Task_Identification.Current_Task;
      Stack_Probe : aliased Stack_Probe_Array := [others => 'C'];
   begin
      if not Flyology.M3_Runtime.Validate_Current_Stack (Stack_Probe'Address)
      then
         raise Program_Error;
      end if;
      Nested_Child_Id := Self;
      Nested_Child_Done := True;
   end Nested_Child_Type;

   task body Nested_Parent_Type is
      Self : constant Ada.Task_Identification.Task_Id :=
        Ada.Task_Identification.Current_Task;
      Stack_Probe : aliased Stack_Probe_Array := [others => 'P'];
   begin
      if not Flyology.M3_Runtime.Validate_Current_Stack (Stack_Probe'Address)
      then
         raise Program_Error;
      end if;
      Nested_Parent_Id := Self;
      declare
         Child : Nested_Child_Type;
      begin
         Nested_Child_Object_Id := Child'Identity;
      end;
      if not Nested_Child_Done then
         raise Program_Error;
      end if;
      Nested_Parent_Done := True;
   end Nested_Parent_Type;

   task body Rendezvous_Server_Type is
   begin
      accept Ping (Value : in out Integer) do
         Value := Value + 1 +
           Integer (Ada.Dynamic_Priorities.Get_Priority);
      end Ping;
   end Rendezvous_Server_Type;

   task body Delayed_Rendezvous_Server_Type is
   begin
      delay 0.100;
      accept Ping;
   end Delayed_Rendezvous_Server_Type;

   task body Timed_Rendezvous_Server_Type is
   begin
      accept Ping (Value : in out Integer) do
         Value := Value + 2;
      end Ping;
   end Timed_Rendezvous_Server_Type;

   task body Exceptional_Rendezvous_Server_Type is
   begin
      begin
         accept Ping do
            raise Program_Error;
         end Ping;
      exception
         when Program_Error =>
            Exceptional_Rendezvous_Server_Caught := True;
      end;
   end Exceptional_Rendezvous_Server_Type;

   task body Exception_Abort_Server_Type is
   begin
      begin
         accept Ping do
            Exception_Abort_Accepted := True;
            while not Exception_Abort_Release loop
               delay 0.001;
            end loop;
            raise Program_Error;
         end Ping;
      exception
         when Program_Error =>
            Exception_Abort_Server_Caught := True;
      end;
   end Exception_Abort_Server_Type;

   task body Exception_Abort_Client_Type is
   begin
      Exception_Abort_Caller_Id :=
        Ada.Task_Identification.Current_Task;
      Exception_Abort_Caller_Started := True;
      begin
         Server.Ping;
      exception
         when Program_Error =>
            Exception_Abort_Caller_Caught := True;
            delay 0.001;
      end;
      Exception_Abort_Caller_Continued := True;
   end Exception_Abort_Client_Type;

   task body Dynamic_Worker_Type is
   begin
      Dynamic_Id := Ada.Task_Identification.Current_Task;
      Dynamic_Done := True;
   end Dynamic_Worker_Type;

   procedure Run_Dynamic_Worker is
      Worker : constant Dynamic_Worker_Access := new Dynamic_Worker_Type;
   begin
      if Worker.all'Identity = Ada.Task_Identification.Null_Task_Id then
         raise Program_Error;
      end if;
   end Run_Dynamic_Worker;

   task body Free_Hold_Server_Type is
   begin
      --  One accepted call for the abort-vs-free race, followed by one for
      --  each systematic execution-slot reclamation iteration.
      for Iteration in 1 .. 17 loop
         accept Hold do
            while not Free_Release loop
               delay 0.001;
            end loop;
         end Hold;
      end loop;
   end Free_Hold_Server_Type;

   task body Free_Worker_Type is
   begin
      Free_Id := Ada.Task_Identification.Current_Task;
      Free_Started := True;
      Server.Hold;
      Free_Target_Continued := True;
   end Free_Worker_Type;

   task body Free_Release_Type is
   begin
      delay 0.002;
      Free_Release := True;
   end Free_Release_Type;

   task body Free_Race_Client_Type is
   begin
      Free_Race_Id := Ada.Task_Identification.Current_Task;
      Free_Worker (Race_Target);
      Free_Race_Nulled := Race_Target = null;
      delay 0.001;
      Free_Race_Continued := True;
   end Free_Race_Client_Type;

   procedure Run_Free_Worker is
      use type Ada.Real_Time.Time;
      Previous : Ada.Task_Identification.Task_Id :=
        Ada.Task_Identification.Null_Task_Id;
      Server : aliased Free_Hold_Server_Type;
   begin
      --  Abort the task performing deallocation while it is waiting for a
      --  target held in an accepted abort-deferred rendezvous.  The target's
      --  natural retirement wake must finish raw free and access nulling
      --  before the client's pending abort is delivered at its next delay.
      Free_Started := False;
      Free_Release := False;
      Free_Target_Continued := False;
      Free_Race_Nulled := False;
      Free_Race_Continued := False;
      Free_Race_Id := Ada.Task_Identification.Null_Task_Id;
      Race_Target := new Free_Worker_Type
        (System.Multiprocessors.Number_Of_CPUs, Server'Unchecked_Access);
      declare
         Target_Id : constant Ada.Task_Identification.Task_Id :=
           Race_Target.all'Identity;
         Start_Deadline : constant Ada.Real_Time.Time :=
           Ada.Real_Time.Clock + Ada.Real_Time.Milliseconds (100);
      begin
         while not Free_Started loop
            if not (Ada.Real_Time.Clock < Start_Deadline) then
               Report_Failure;
            end if;
            delay 0.001;
         end loop;
         declare
            Client : Free_Race_Client_Type
              (System.Multiprocessors.Number_Of_CPUs);
            Wait_Deadline : constant Ada.Real_Time.Time :=
              Ada.Real_Time.Clock + Ada.Real_Time.Milliseconds (100);
         begin
            while not Flyology.M3_Runtime.Any_Free_Wait_Is_Active
            loop
               if not (Ada.Real_Time.Clock < Wait_Deadline) then
                  Report_Failure;
               end if;
               delay 0.001;
            end loop;
            Report_Free_Wait_Pass;
            abort Client;
            Free_Release := True;
         end;
         if Race_Target /= null
           or else not Free_Race_Nulled
           or else Free_Race_Continued
           or else Free_Target_Continued
           or else Free_Race_Id = Ada.Task_Identification.Null_Task_Id
           or else not Ada.Task_Identification.Is_Terminated (Free_Race_Id)
           or else Ada.Task_Identification.Is_Callable (Free_Race_Id)
           or else not Ada.Task_Identification.Is_Terminated (Target_Id)
           or else Ada.Task_Identification.Is_Callable (Target_Id)
         then
            Report_Failure;
         end if;
         Report_Free_Abort_Race_Pass;
      end;

      --  More iterations than the bounded execution-slot pool prove that
      --  Free_Task waits for off-stack retirement and releases each slot.
      for Iteration in 1 .. 16 loop
         declare
            Worker : Free_Worker_Access := null;
            Saved  : Ada.Task_Identification.Task_Id;
            Start_Deadline : constant Ada.Real_Time.Time :=
              Ada.Real_Time.Clock + Ada.Real_Time.Milliseconds (100);
         begin
            Free_Started := False;
            Free_Release := False;
            Free_Target_Continued := False;
            Free_Id := Ada.Task_Identification.Null_Task_Id;
            Worker := new Free_Worker_Type
              (System.Multiprocessors.Number_Of_CPUs,
               Server'Unchecked_Access);
            Saved := Worker.all'Identity;
            while not Free_Started loop
               if not (Ada.Real_Time.Clock < Start_Deadline) then
                  Report_Failure;
               end if;
               delay 0.001;
            end loop;
            if Saved = Ada.Task_Identification.Null_Task_Id
              or else Free_Id /= Saved
              or else Saved = Previous
            then
               Report_Failure;
            end if;
            declare
               Releaser : Free_Release_Type;
               pragma Unreferenced (Releaser);
            begin
               Free_Worker (Worker);
            end;
            if Worker /= null
              or else Free_Target_Continued
              or else not Ada.Task_Identification.Is_Terminated (Saved)
              or else Ada.Task_Identification.Is_Callable (Saved)
            then
               Report_Failure;
            end if;
            Previous := Saved;
         end;
      end loop;
   end Run_Free_Worker;

   task body Selective_Server_Type is
   begin
      select
         accept Ping;
      or
         terminate;
      end select;
      Selective_Done := True;
   end Selective_Server_Type;

   task body Terminate_Server_Type is
   begin
      Terminate_Ids (Index) := Ada.Task_Identification.Current_Task;
      Terminate_Started (Index) := True;
      if Index = 2 then
         while not Terminate_Started (1) loop
            delay 0.001;
         end loop;
         delay 0.005;
         Terminate_Selected_Early :=
           Ada.Task_Identification.Is_Terminated (Terminate_Ids (1));
      end if;
      begin
         select
            accept Ping;
         or
            terminate;
         end select;
      exception
         when others =>
            Terminate_User_Handler_Ran (Index) := True;
      end;
      Terminate_Continued (Index) := True;
   end Terminate_Server_Type;

   procedure Run_Terminate_Alternative is
      First_Id  : Ada.Task_Identification.Task_Id;
      Second_Id : Ada.Task_Identification.Task_Id;
   begin
      Terminate_Started := [others => False];
      Terminate_Continued := [others => False];
      Terminate_User_Handler_Ran := [others => False];
      Terminate_Selected_Early := False;
      Terminate_Ids := [others => Ada.Task_Identification.Null_Task_Id];
      declare
         First : Terminate_Server_Type (1, 1);
         Second : Terminate_Server_Type
           (System.Multiprocessors.Number_Of_CPUs, 2);
      begin
         First_Id := First'Identity;
         Second_Id := Second'Identity;
      end;
      if not Terminate_Started (1) or else not Terminate_Started (2)
        or else Terminate_Continued (1) or else Terminate_Continued (2)
        or else Terminate_User_Handler_Ran (1)
        or else Terminate_User_Handler_Ran (2)
        or else Terminate_Selected_Early
        or else Terminate_Ids (1) /= First_Id
        or else Terminate_Ids (2) /= Second_Id
        or else not Ada.Task_Identification.Is_Terminated (First_Id)
        or else not Ada.Task_Identification.Is_Terminated (Second_Id)
        or else Ada.Task_Identification.Is_Callable (First_Id)
        or else Ada.Task_Identification.Is_Callable (Second_Id)
      then
         Report_Failure;
      end if;
   end Run_Terminate_Alternative;

   task body Abort_Worker_Type is
   begin
      Abort_Id := Ada.Task_Identification.Current_Task;
      Abort_Started := True;
      begin
         delay 1.0;
      exception
         when others =>
            Abort_User_Handler_Ran := True;
      end;
      Abort_Continued := True;
   end Abort_Worker_Type;

   task body Multi_Abort_Worker_Type is
   begin
      Multi_Abort_Ids (Index) := Ada.Task_Identification.Current_Task;
      Multi_Abort_Started (Index) := True;
      delay 10.0;
      Multi_Abort_Continued (Index) := True;
   end Multi_Abort_Worker_Type;

   task body Dependent_Abort_Child_Type is
   begin
      Dependent_Abort_Child_Id := Ada.Task_Identification.Current_Task;
      Dependent_Abort_Child_Started := True;
      delay 10.0;
      Dependent_Abort_Child_Continued := True;
   end Dependent_Abort_Child_Type;

   task body Dependent_Abort_Parent_Type is
   begin
      Dependent_Abort_Parent_Id := Ada.Task_Identification.Current_Task;
      declare
         Child : Dependent_Abort_Child_Type (1);
         pragma Unreferenced (Child);
      begin
         for Attempt in 1 .. 1_000 loop
            exit when Dependent_Abort_Child_Started;
            delay 0.001;
         end loop;
         if not Dependent_Abort_Child_Started then
            Report_Failure;
         end if;
         Dependent_Abort_Parent_Started := True;
         delay 10.0;
         Dependent_Abort_Parent_Continued := True;
      end;
   end Dependent_Abort_Parent_Type;

   task body Abort_Rendezvous_Server_Type is
   begin
      if Delay_Before_Accept then
         delay 0.100;
         accept Ping;
      else
         accept Ping do
            Abort_Accept_Entered := True;
            delay 0.100;
         end Ping;
      end if;
   end Abort_Rendezvous_Server_Type;

   task body Abort_Rendezvous_Client_Type is
   begin
      Abort_Call_Id := Ada.Task_Identification.Current_Task;
      Abort_Call_Started := True;
      Server.Ping;
      Abort_Call_Continued := True;
   end Abort_Rendezvous_Client_Type;

   task body Abort_Timed_Client_Type is
   begin
      Abort_Timed_Id := Ada.Task_Identification.Current_Task;
      Abort_Timed_Started := True;
      select
         Server.Ping;
         Abort_Timed_Accepted := True;
      or
         delay 1.0;
         Abort_Timed_Out := True;
      end select;
      Abort_Timed_Continued := True;
   end Abort_Timed_Client_Type;

   task body Protected_Entry_Worker_Type is
   begin
      Priority_Worker_Id (Index) :=
        Ada.Task_Identification.Current_Task;
      if Index = 2 then
         --  Make the FIFO arrival order causal rather than relying on the
         --  relative first dispatch of two simultaneously activated tasks.
         for Attempt in 1 .. 1_000 loop
            exit when Protected_Gate.Waiting = 1;
            delay 0.001;
         end loop;
         if Protected_Gate.Waiting /= 1 then
            Report_Failure;
         end if;
      end if;
      Protected_Gate.Wait (Index);
      Priority_Run_Log.Note (Index);
      Protected_Entry_Done (Index) := True;
   end Protected_Entry_Worker_Type;

   task body Abort_Protected_Worker_Type is
   begin
      Abort_Protected_Id := Ada.Task_Identification.Current_Task;
      Abort_Protected_Started := True;
      Protected_Gate.Wait (1);
      Abort_Protected_Continued := True;
   end Abort_Protected_Worker_Type;

   task body Abort_Timed_Protected_Worker_Type is
   begin
      Abort_Timed_Protected_Id := Ada.Task_Identification.Current_Task;
      Abort_Timed_Protected_Started := True;
      select
         Protected_Gate.Wait (2);
         Abort_Timed_Protected_Accepted := True;
      or
         delay 0.001 * Timeout_Milliseconds;
         Abort_Timed_Protected_Timed_Out := True;
      end select;
      Abort_Timed_Protected_Continued := True;
   end Abort_Timed_Protected_Worker_Type;

   task body Collision_Rendezvous_Server_Type is
   begin
      delay 0.001 * Accept_Delay_Milliseconds;
      accept Ping do
         Collision_Server_Accept_Count :=
           Collision_Server_Accept_Count + 1;
         Collision_Server_Accepted := True;
         if Hold_Milliseconds > 0 then
            delay 0.001 * Hold_Milliseconds;
         end if;
      end Ping;
      Collision_Server_Completed := True;
   end Collision_Rendezvous_Server_Type;

   task body Collision_Rendezvous_Client_Type is
   begin
      Collision_Call_Id := Ada.Task_Identification.Current_Task;
      Collision_Call_Started := True;
      select
         Server.Ping;
         Collision_Call_Accepted := True;
      or
         delay 0.001 * Timeout_Milliseconds;
         Collision_Call_Timed_Out := True;
      end select;
      Collision_Call_Continued := True;
   end Collision_Rendezvous_Client_Type;

   task body Exceptional_Protected_Worker_Type is
   begin
      begin
         Protected_Gate.Fail;
      exception
         when Program_Error =>
            Exceptional_Protected_Caught := True;
      end;
   end Exceptional_Protected_Worker_Type;

   task body Exception_Abort_Protected_Worker_Type is
   begin
      Exception_Abort_Protected_Id :=
        Ada.Task_Identification.Current_Task;
      Exception_Abort_Protected_Started := True;
      begin
         Protected_Gate.Fail;
      exception
         when Program_Error =>
            Exception_Abort_Protected_Caught := True;
            delay 0.001;
      end;
      Exception_Abort_Protected_Continued := True;
   end Exception_Abort_Protected_Worker_Type;

   task body Unactivated_Worker_Type is
   begin
      Unactivated_Ran := True;
   end Unactivated_Worker_Type;

   task body Failed_Activation_Worker_Type is
      Value : constant Integer := Fail_Before_Activation;
      pragma Unreferenced (Value);
   begin
      Activation_Failed_Body_Ran := True;
   end Failed_Activation_Worker_Type;

   task body Activation_Sibling_Worker_Type is
   begin
      Activation_Sibling_Ran := True;
   end Activation_Sibling_Worker_Type;

   function Fail_Before_Activation return Integer is
   begin
      raise Program_Error;
      return 0;
   end Fail_Before_Activation;

   procedure Run_Protected_Collision_Campaign is
      CPU_Count : constant Positive :=
        Positive (System.Multiprocessors.Number_Of_CPUs);
   begin
      for Scenario in Positive range 1 .. 6 loop
         Abort_Timed_Protected_Started := False;
         Abort_Timed_Protected_Accepted := False;
         Abort_Timed_Protected_Timed_Out := False;
         Abort_Timed_Protected_Continued := False;
         Abort_Timed_Protected_Id :=
           Ada.Task_Identification.Null_Task_Id;
         Protected_Gate.Close;
         declare
            Timeout_Milliseconds : constant Positive :=
              (case Scenario is
                 when 1 | 3 | 6 => 100,
                 when 2         => 20,
                 when 4         => 30,
                 when 5         => 40);
            Worker : Abort_Timed_Protected_Worker_Type
              (System.Multiprocessors.CPU_Range (CPU_Count),
               Timeout_Milliseconds);
            Worker_Id : constant Ada.Task_Identification.Task_Id :=
              Worker'Identity;
         begin
            for Attempt in 1 .. 1_000 loop
               exit when Abort_Timed_Protected_Started
                 and then Abort_Timed_Protected_Id = Worker_Id
                 and then Protected_Gate.Waiting = 1;
               delay 0.001;
            end loop;
            if not Abort_Timed_Protected_Started
              or else Abort_Timed_Protected_Id /= Worker_Id
              or else Protected_Gate.Waiting /= 1
            then
               Report_Failure;
            end if;
            case Scenario is
               when 1 =>
                  Protected_Gate.Open;
                  Protected_Gate.Close;
               when 2 =>
                  delay 0.030;
               when 3 =>
                  abort Worker;
                  Protected_Gate.Open;
                  Protected_Gate.Close;
               when 4 =>
                  delay 0.030;
                  Protected_Gate.Open;
                  Protected_Gate.Close;
               when 5 =>
                  delay 0.030;
                  abort Worker;
                  Protected_Gate.Open;
                  Protected_Gate.Close;
               when 6 =>
                  delay 0.030;
                  Protected_Gate.Open;
                  abort Worker;
                  Protected_Gate.Close;
            end case;
         end;

         if Protected_Gate.Waiting /= 0
           or else Abort_Timed_Protected_Id =
             Ada.Task_Identification.Null_Task_Id
           or else not Ada.Task_Identification.Is_Terminated
             (Abort_Timed_Protected_Id)
           or else Ada.Task_Identification.Is_Callable
             (Abort_Timed_Protected_Id)
         then
            Report_Failure;
         end if;
         if Scenario = 3 then
            if Abort_Timed_Protected_Accepted
              or else Abort_Timed_Protected_Timed_Out
              or else Abort_Timed_Protected_Continued
            then
               Report_Failure;
            end if;
         elsif Scenario in 5 | 6 then
            --  These are deliberately scheduling-sensitive cases.  TCG may
            --  resume the remote caller before or after the environment's
            --  abort statement.  Accept either abort (no user continuation)
            --  or exactly one normal winner, but never a double or partial
            --  outcome.
            if Abort_Timed_Protected_Accepted
              and then Abort_Timed_Protected_Timed_Out
            then
               Report_Failure;
            elsif Abort_Timed_Protected_Continued /=
              (Abort_Timed_Protected_Accepted
               or else Abort_Timed_Protected_Timed_Out)
            then
               Report_Failure;
            end if;
         elsif Abort_Timed_Protected_Accepted =
             Abort_Timed_Protected_Timed_Out
           or else not Abort_Timed_Protected_Continued
         then
            Report_Failure;
         end if;

         --  A fresh immediate call after every collision proves that no stale
         --  protected queue/parameter record prevents subsequent service.
         declare
            Services_Before : constant Natural := Protected_Gate.Services;
         begin
            Protected_Gate.Open;
            Protected_Gate.Wait (4);
            Protected_Gate.Close;
            if Protected_Gate.Services /= Services_Before + 1
              or else Protected_Gate.Waiting /= 0
            then
               Report_Failure;
            end if;
         end;
      end loop;
   end Run_Protected_Collision_Campaign;

   procedure Run_Rendezvous_Collision_Campaign is
      CPU_Count : constant Positive :=
        Positive (System.Multiprocessors.Number_Of_CPUs);
   begin
      for Scenario in Positive range 1 .. 6 loop
         Collision_Call_Started := False;
         Collision_Call_Accepted := False;
         Collision_Call_Timed_Out := False;
         Collision_Call_Continued := False;
         Collision_Call_Id := Ada.Task_Identification.Null_Task_Id;
         Collision_Server_Accepted := False;
         Collision_Server_Completed := False;
         Collision_Server_Accept_Count := 0;
         declare
            Accept_Delay_Milliseconds : constant Natural :=
              (case Scenario is
                 when 1         => 200,
                 when 2 | 3     => 1_000,
                 when 4         => 200,
                 when 5         => 300,
                 when 6         => 200);
            Hold_Milliseconds : constant Natural :=
              (if Scenario = 6 then 200 else 0);
            Timeout_Milliseconds : constant Positive :=
              (case Scenario is
                 when 1 | 3 | 6 => 1_000,
                 when 2         => 300,
                 when 4         => 200,
                 when 5         => 300);
            Server : aliased Collision_Rendezvous_Server_Type
              (System.Multiprocessors.CPU_Range (CPU_Count),
               Accept_Delay_Milliseconds, Hold_Milliseconds);
         begin
            --  Activate the server in its own compiler activation chain, then
            --  create the timed caller.  This keeps the test's activation
            --  handshake distinct from the rendezvous race being exercised.
            declare
               Client : Collision_Rendezvous_Client_Type
                 (1, Server'Access, Timeout_Milliseconds);
               Client_Id : constant Ada.Task_Identification.Task_Id :=
                 Client'Identity;
            begin
               for Attempt in 1 .. 1_000 loop
                  exit when Collision_Call_Started
                    and then Collision_Call_Id = Client_Id
                    and then Flyology.M3_Runtime.Demo_Queued_Call_Count = 1;
                  delay 0.001;
               end loop;
               if not Collision_Call_Started
                 or else Collision_Call_Id /= Client_Id
                 or else Flyology.M3_Runtime.Demo_Queued_Call_Count /= 1
               then
                  Report_Failure;
               end if;

               case Scenario is
                  when 1 =>
                     null;
                  when 2 =>
                     delay 0.400;
                     Server.Ping;
                  when 3 =>
                     abort Client;
                     Server.Ping;
                  when 4 =>
                     for Attempt in 1 .. 1_000 loop
                        exit when Collision_Call_Accepted
                          or else Collision_Call_Timed_Out;
                        delay 0.001;
                     end loop;
                     if Collision_Call_Timed_Out then
                        Server.Ping;
                     elsif not Collision_Call_Accepted then
                        Report_Failure;
                     end if;
                  when 5 =>
                     delay 0.250;
                     abort Client;
                     Server.Ping;
                  when 6 =>
                     for Attempt in 1 .. 1_000 loop
                        exit when Collision_Server_Accepted;
                        delay 0.001;
                     end loop;
                     if not Collision_Server_Accepted then
                        Report_Failure;
                     end if;
                     abort Client;
               end case;
            end;
         end;
         if Collision_Server_Accept_Count /= 1
           or else not Collision_Server_Completed
           or else Flyology.M3_Runtime.Demo_Queued_Call_Count /= 0
           or else Collision_Call_Id = Ada.Task_Identification.Null_Task_Id
           or else not Ada.Task_Identification.Is_Terminated
             (Collision_Call_Id)
           or else Ada.Task_Identification.Is_Callable (Collision_Call_Id)
         then
            Report_Failure;
         end if;
         if Scenario in 3 | 6 then
            if Collision_Call_Accepted or else Collision_Call_Timed_Out
              or else Collision_Call_Continued
            then
               Report_Failure;
            end if;
         elsif Scenario = 5 then
            if Collision_Call_Accepted and then Collision_Call_Timed_Out then
               Report_Failure;
            elsif Collision_Call_Continued /=
              (Collision_Call_Accepted or else Collision_Call_Timed_Out)
            then
               Report_Failure;
            end if;
         elsif Collision_Call_Accepted = Collision_Call_Timed_Out
           or else not Collision_Call_Continued
         then
            Report_Failure;
         end if;
      end loop;
   end Run_Rendezvous_Collision_Campaign;

   procedure Report_Ordinary_Pass
   with Import, Convention => C,
        External_Name => "flyology_m3_report_ordinary_pass";

   procedure Report_Specific_Pass
   with Import, Convention => C,
        External_Name => "flyology_m3_report_specific_pass";

   procedure Report_Parallel_Pass
   with Import, Convention => C,
        External_Name => "flyology_m3_report_parallel_pass";

   procedure Report_Auto_Master_Pass
   with Import, Convention => C,
        External_Name => "flyology_m3_report_auto_master_pass";

   procedure Report_Reclamation_Pass
   with Import, Convention => C,
        External_Name => "flyology_m4_report_reclamation_pass";

   procedure Report_Delay_Pass
   with Import, Convention => C,
        External_Name => "flyology_m4_report_delay_pass";

   procedure Report_Absolute_Delay_Pass
   with Import, Convention => C,
        External_Name => "flyology_m4_report_absolute_delay_pass";

   procedure Report_Protected_Pass
   with Import, Convention => C,
        External_Name => "flyology_m4_report_protected_pass";

   procedure Report_Protected_Entry_Pass
   with Import, Convention => C,
        External_Name => "flyology_m4_report_protected_entry_pass";

   procedure Report_Rendezvous_Pass
   with Import, Convention => C,
        External_Name => "flyology_m4_report_rendezvous_pass";

   procedure Report_Exceptional_Sync_Pass
   with Import, Convention => C,
        External_Name => "flyology_m4_report_exceptional_sync_pass";

   procedure Report_Exceptional_Protected_Immediate_Pass
   with Import, Convention => C,
        External_Name =>
          "flyology_m4_report_exceptional_protected_immediate_pass";

   procedure Report_Exceptional_Protected_Queued_Pass
   with Import, Convention => C,
        External_Name =>
          "flyology_m4_report_exceptional_protected_queued_pass";

   procedure Report_Exception_Abort_Protected_Pass
   with Import, Convention => C,
        External_Name =>
          "flyology_m4_report_exception_abort_protected_pass";

   procedure Report_Exceptional_Rendezvous_Pass
   with Import, Convention => C,
        External_Name => "flyology_m4_report_exceptional_rendezvous_pass";

   procedure Report_Exception_Abort_Pass
   with Import, Convention => C,
        External_Name => "flyology_m4_report_exception_abort_pass";

   procedure Report_Unactivated_Cleanup_Pass
   with Import, Convention => C,
        External_Name => "flyology_m4_report_unactivated_cleanup_pass";

   procedure Report_Allocator_Pass
   with Import, Convention => C,
        External_Name => "flyology_m4_report_allocator_pass";

   procedure Report_Priority_Pass
   with Import, Convention => C,
        External_Name => "flyology_m4_report_priority_pass";

   procedure Report_Ceiling_Pass
   with Import, Convention => C,
        External_Name => "flyology_m4_report_ceiling_pass";

   procedure Report_Conditional_Pass
   with Import, Convention => C,
        External_Name => "flyology_m4_report_conditional_pass";

   procedure Report_Timed_Entry_Pass
   with Import, Convention => C,
        External_Name => "flyology_m4_report_timed_entry_pass";

   procedure Report_Dynamic_Task_Pass
   with Import, Convention => C,
        External_Name => "flyology_m4_report_dynamic_task_pass";

   procedure Report_Free_Task_Pass
   with Import, Convention => C,
        External_Name => "flyology_m4_report_free_task_pass";

   procedure Report_Selective_Wait_Pass
   with Import, Convention => C,
        External_Name => "flyology_m4_report_selective_wait_pass";

   procedure Report_Terminate_Alternative_Pass
   with Import, Convention => C,
        External_Name => "flyology_m4_report_terminate_alternative_pass";

   procedure Report_Abort_Pass
   with Import, Convention => C,
        External_Name => "flyology_m4_report_abort_pass";

   procedure Report_Multi_Abort_Pass
   with Import, Convention => C,
        External_Name => "flyology_m4_report_multi_abort_pass";

   procedure Report_Dependent_Abort_Pass
   with Import, Convention => C,
        External_Name => "flyology_m4_report_dependent_abort_pass";

   procedure Report_Abort_Rendezvous_Pass
   with Import, Convention => C,
        External_Name => "flyology_m4_report_abort_rendezvous_pass";

   procedure Report_Abort_Timeout_Pass
   with Import, Convention => C,
        External_Name => "flyology_m4_report_abort_timeout_pass";

   procedure Report_Abort_Accepted_Pass
   with Import, Convention => C,
        External_Name => "flyology_m4_report_abort_accepted_pass";

   procedure Report_Abort_Protected_Pass
   with Import, Convention => C,
        External_Name => "flyology_m4_report_abort_protected_pass";

   procedure Report_Collision_Stress_Pass
   with Import, Convention => C,
        External_Name => "flyology_m4_report_collision_stress_pass";

   procedure Report_Master_Pass
   with Import, Convention => C,
        External_Name => "flyology_m3_report_master_pass";

   procedure Report_Stack_Pass
   with Import, Convention => C,
        External_Name => "flyology_m3_report_stack_pass";

   procedure Check_Identity
     (Observed : Ada.Task_Identification.Task_Id;
      Expected : Ada.Task_Identification.Task_Id;
      Environment : Ada.Task_Identification.Task_Id)
   is
   begin
      if Observed = Ada.Task_Identification.Null_Task_Id
        or else Observed /= Expected
        or else Observed = Environment
        or else not Ada.Task_Identification.Is_Terminated (Observed)
        or else Ada.Task_Identification.Is_Callable (Observed)
      then
         Report_Failure;
      end if;
   end Check_Identity;

   procedure Run is
      CPU_Count : constant Natural := Natural
        (System.Multiprocessors.Number_Of_CPUs);
      Environment : constant Ada.Task_Identification.Task_Id :=
        Ada.Task_Identification.Current_Task;
      Specific_Object_Id : Identity_Array :=
        [others => Ada.Task_Identification.Null_Task_Id];
      Auto_Object_Id : Identity_Array :=
        [others => Ada.Task_Identification.Null_Task_Id];
      Parent_Object_Id : Ada.Task_Identification.Task_Id :=
        Ada.Task_Identification.Null_Task_Id;
      Cleanup_Queries_Before : Abort_Query_Count;
   begin
      if CPU_Count not in 1 | 4
        or else Environment = Ada.Task_Identification.Null_Task_Id
      then
         Report_Failure;
      end if;

      if CPU_Count = 4 then
         declare
            Worker_1 : Specific_Worker_Type (1, 1);
            Worker_2 : Specific_Worker_Type (2, 2);
            Worker_3 : Specific_Worker_Type (3, 3);
            Worker_4 : Specific_Worker_Type (4, 4);
         begin
            Specific_Object_Id (1) := Worker_1'Identity;
            Specific_Object_Id (2) := Worker_2'Identity;
            Specific_Object_Id (3) := Worker_3'Identity;
            Specific_Object_Id (4) := Worker_4'Identity;
         end;
      else
         declare
            Worker_1 : Specific_Worker_Type (1, 1);
         begin
            Specific_Object_Id (1) := Worker_1'Identity;
         end;
      end if;

      for Index in 1 .. CPU_Count loop
         if not Specific_Done (Index)
           or else Specific_Core (Index) /= Index - 1
         then
            Report_Failure;
         end if;
         Check_Identity
           (Specific_Id (Index), Specific_Object_Id (Index), Environment);
         for Other in 1 .. CPU_Count loop
            if Index /= Other
              and then Specific_Id (Index) = Specific_Id (Other)
            then
               Report_Failure;
            end if;
         end loop;
      end loop;
      Report_Specific_Pass;

      declare
         Worker_1 : Auto_Worker_Type (1);
         Worker_2 : Auto_Worker_Type (2);
         Worker_3 : Auto_Worker_Type (3);
         Worker_4 : Auto_Worker_Type (4);
      begin
         Auto_Object_Id (1) := Worker_1'Identity;
         Auto_Object_Id (2) := Worker_2'Identity;
         Auto_Object_Id (3) := Worker_3'Identity;
         Auto_Object_Id (4) := Worker_4'Identity;
      end;
      Report_Auto_Master_Pass;

      declare
         Worker_1 : Reclaim_Worker_Type (1);
         Worker_2 : Reclaim_Worker_Type (2);
         Worker_3 : Reclaim_Worker_Type (3);
         Worker_4 : Reclaim_Worker_Type (4);
      begin
         null;
      end;
      for Index in Reclaim_Id'Range loop
         if not Reclaim_Done (Index)
           or else Reclaim_Id (Index) =
             Ada.Task_Identification.Null_Task_Id
           or else not Ada.Task_Identification.Is_Terminated
             (Reclaim_Id (Index))
           or else Ada.Task_Identification.Is_Callable (Reclaim_Id (Index))
         then
            Report_Failure;
         end if;
         for Other in Specific_Id'Range loop
            if Reclaim_Id (Index) = Specific_Id (Other)
              or else Reclaim_Id (Index) = Auto_Id (Other)
            then
               Report_Failure;
            end if;
         end loop;
      end loop;
      Report_Reclamation_Pass;
      declare
         Caught : Boolean := False;
      begin
         begin
            declare
               Worker : Unactivated_Worker_Type;
               Value  : constant Integer := Fail_Before_Activation;
               pragma Unreferenced (Worker, Value);
            begin
               null;
            end;
         exception
            when Program_Error =>
               Caught := True;
         end;
         if not Caught or else Unactivated_Ran then
            Report_Failure;
         end if;
      end;
      declare
         Caught : Boolean := False;
      begin
         begin
            declare
               Failed  : Failed_Activation_Worker_Type;
               Sibling : Activation_Sibling_Worker_Type;
               pragma Unreferenced (Failed, Sibling);
            begin
               Report_Failure;
            end;
         exception
            when Tasking_Error =>
               Caught := True;
         end;
         if not Caught
           or else not Activation_Sibling_Ran
           or else Activation_Failed_Body_Ran
         then
            Report_Failure;
         end if;
      end;
      Report_Unactivated_Cleanup_Pass;
      declare
         type Byte_Array is array (Positive range <>) of Character;
         type Byte_Array_Access is access Byte_Array;
         procedure Free_Bytes is new Ada.Unchecked_Deallocation
           (Byte_Array, Byte_Array_Access);
         Huge   : Byte_Array_Access := null;
         Small  : Byte_Array_Access := null;
         Caught : Boolean := False;
      begin
         begin
            Huge := new Byte_Array (1 .. 65_537);
         exception
            when Storage_Error =>
               Caught := True;
         end;
         if not Caught or else Huge /= null then
            Report_Failure;
         end if;
         Small := new Byte_Array (1 .. 16);
         Small (1) := 'A';
         if Small (1) /= 'A' then
            Report_Failure;
         end if;
         Free_Bytes (Small);
         if Small /= null then
            Report_Failure;
         end if;
         --  The cumulative request exceeds the complete 64-KiB pool twice.
         --  Every iteration must therefore reclaim the same bounded storage
         --  through the compiler-lowered raw-free path.
         for Iteration in Positive range 1 .. 40 loop
            declare
               Reused : Byte_Array_Access := new Byte_Array (1 .. 4_096);
            begin
               Reused (1) := Character'Val (Iteration mod 256);
               Reused (Reused'Last) := 'R';
               if Reused (1) /= Character'Val (Iteration mod 256)
                 or else Reused (Reused'Last) /= 'R'
               then
                  Report_Failure;
               end if;
               Free_Bytes (Reused);
               if Reused /= null then
                  Report_Failure;
               end if;
            end;
         end loop;
      end;
      Report_Allocator_Pass;
      Report_Delay_Pass;
      declare
         use type Ada.Real_Time.Time;
         Deadline : constant Ada.Real_Time.Time :=
           Ada.Real_Time.Clock + Ada.Real_Time.Milliseconds (2);
      begin
         delay until Deadline;
         if Ada.Real_Time.Clock < Deadline then
            Report_Failure;
         end if;
         delay until Deadline;
      end;
      Report_Absolute_Delay_Pass;
      if Shared_Counter.Value /= 8 then
         Report_Failure;
      end if;
      Report_Protected_Pass;

      declare
         Original_Priority : constant System.Any_Priority :=
           Ada.Dynamic_Priorities.Get_Priority;
         Violation_Caught : Boolean := False;
      begin
         Ceiling_Body_Ran := False;
         Ceiling_Check_Failed := False;
         Ada.Dynamic_Priorities.Set_Priority (9);
         begin
            Ceiling_Probe.Change_Base;
         exception
            when Program_Error =>
               Violation_Caught := True;
         end;
         if not Violation_Caught or else Ceiling_Body_Ran
           or else Ada.Dynamic_Priorities.Get_Priority /= 9
           or else Flyology.M3_Runtime.Current_Active_Priority /= 9
         then
            Report_Failure;
         end if;
         Ada.Dynamic_Priorities.Set_Priority (2);
         Ceiling_Body_Ran := False;
         Ceiling_Probe.Change_Base;
         if not Ceiling_Body_Ran or else Ceiling_Check_Failed
           or else Ada.Dynamic_Priorities.Get_Priority /= 3
           or else Flyology.M3_Runtime.Current_Active_Priority /= 3
         then
            Report_Failure;
         end if;
         Ada.Dynamic_Priorities.Set_Priority (Original_Priority);
      end;
      Report_Ceiling_Pass;

      declare
         Rejected : Boolean := False;
      begin
         select
            Protected_Gate.Wait (1);
         else
            Rejected := True;
         end select;
         if not Rejected then
            Report_Failure;
         end if;
         --  Exercise more queued timed calls than the bounded ceiling stack
         --  can hold.  Every block publication must pop its protected-action
         --  ceiling before sleeping; retaining even one frame per call fails
         --  closed before this loop completes.
         for Iteration in 1 .. 10 loop
            declare
               Timed_Out : Boolean := False;
            begin
               select
                  Protected_Gate.Wait (2);
               or
                  delay 0.001;
                  Timed_Out := True;
               end select;
               if not Timed_Out or else Protected_Gate.Waiting /= 0 then
                  Report_Failure;
               end if;
            end;
         end loop;
      end;

      declare
         Worker : Abort_Protected_Worker_Type
           (System.Multiprocessors.CPU_Range (CPU_Count));
         Worker_Id : constant Ada.Task_Identification.Task_Id :=
           Worker'Identity;
      begin
         for Attempt in 1 .. 1_000 loop
            exit when Abort_Protected_Started
              and then Abort_Protected_Id = Worker_Id
              and then Protected_Gate.Waiting = 1;
            delay 0.001;
         end loop;
         if not Abort_Protected_Started
           or else Abort_Protected_Id /= Worker_Id
           or else Protected_Gate.Waiting /= 1
         then
            Report_Failure;
         end if;
         abort Worker;
         Protected_Gate.Open;
         Protected_Gate.Close;
      end;
      if Abort_Protected_Continued
        or else Abort_Protected_Id = Ada.Task_Identification.Null_Task_Id
        or else not Ada.Task_Identification.Is_Terminated
          (Abort_Protected_Id)
        or else Ada.Task_Identification.Is_Callable (Abort_Protected_Id)
        or else Protected_Gate.Waiting /= 0
      then
         Report_Failure;
      end if;
      declare
         Worker : Abort_Timed_Protected_Worker_Type
           (System.Multiprocessors.CPU_Range (CPU_Count), 1_000);
         Worker_Id : constant Ada.Task_Identification.Task_Id :=
           Worker'Identity;
      begin
         for Attempt in 1 .. 1_000 loop
            exit when Abort_Timed_Protected_Started
              and then Abort_Timed_Protected_Id = Worker_Id
              and then Protected_Gate.Waiting = 1;
            delay 0.001;
         end loop;
         if not Abort_Timed_Protected_Started
           or else Abort_Timed_Protected_Id /= Worker_Id
           or else Protected_Gate.Waiting /= 1
         then
            Report_Failure;
         end if;
         abort Worker;
      end;
      if Abort_Timed_Protected_Accepted
        or else Abort_Timed_Protected_Timed_Out
        or else Abort_Timed_Protected_Continued
        or else Abort_Timed_Protected_Id =
          Ada.Task_Identification.Null_Task_Id
        or else not Ada.Task_Identification.Is_Terminated
          (Abort_Timed_Protected_Id)
        or else Ada.Task_Identification.Is_Callable
          (Abort_Timed_Protected_Id)
        or else Protected_Gate.Waiting /= 0
      then
         Report_Failure;
      end if;
      Report_Abort_Protected_Pass;

      declare
         Worker_1 : Protected_Entry_Worker_Type
           (System.Multiprocessors.CPU_Range (CPU_Count), 1);
         Worker_2 : Protected_Entry_Worker_Type
           (System.Multiprocessors.CPU_Range (CPU_Count), 2);
      begin
         for Attempt in 1 .. 1_000 loop
            exit when Protected_Gate.Waiting = 2
              and then Priority_Worker_Id (1) /=
                Ada.Task_Identification.Null_Task_Id
              and then Priority_Worker_Id (2) /=
                Ada.Task_Identification.Null_Task_Id;
            delay 0.001;
         end loop;
         if Protected_Entry_Done (1) or else Protected_Entry_Done (2)
           or else Protected_Gate.Waiting /= 2
           or else Priority_Worker_Id (1) =
             Ada.Task_Identification.Null_Task_Id
           or else Priority_Worker_Id (2) =
             Ada.Task_Identification.Null_Task_Id
         then
            Report_Failure;
         end if;
         Ada.Dynamic_Priorities.Set_Priority
           (3, Priority_Worker_Id (1));
         Ada.Dynamic_Priorities.Set_Priority
           (9, Priority_Worker_Id (2));
         Protected_Gate.Open;
      end;
      if not Protected_Entry_Done (1) or else not Protected_Entry_Done (2)
        or else Protected_Gate.Service_Order (1) /= 1
        or else Protected_Gate.Service_Order (2) /= 2
        or else Priority_Run_Log.Order (1) /= 2
        or else Priority_Run_Log.Order (2) /= 1
      then
         Report_Failure;
      end if;
      Report_Protected_Entry_Pass;

      declare
         Immediate_Caught : Boolean := False;
      begin
         begin
            Protected_Gate.Fail;
         exception
            when Program_Error =>
               Immediate_Caught := True;
         end;
         Protected_Gate.Close;
         if not Immediate_Caught then
            Report_Failure;
         end if;
      end;
      Report_Exceptional_Protected_Immediate_Pass;
      declare
         Worker : Exceptional_Protected_Worker_Type
           (System.Multiprocessors.CPU_Range (CPU_Count));
      begin
         for Attempt in 1 .. 1_000 loop
            exit when Protected_Gate.Failing = 1
              or else Exceptional_Protected_Caught;
            delay 0.001;
         end loop;
         if Exceptional_Protected_Caught or else Protected_Gate.Failing /= 1
         then
            Report_Failure;
         end if;
         Protected_Gate.Open;
      end;
      Protected_Gate.Close;
      if not Exceptional_Protected_Caught or else Protected_Gate.Failing /= 0
      then
         Report_Failure;
      end if;
      declare
         Worker : Protected_Entry_Worker_Type
           (System.Multiprocessors.CPU_Range (CPU_Count), 3);
      begin
         for Attempt in 1 .. 1_000 loop
            exit when Protected_Gate.Waiting = 1
              or else Protected_Entry_Done (3);
            delay 0.001;
         end loop;
         if Protected_Entry_Done (3) or else Protected_Gate.Waiting /= 1 then
            Report_Failure;
         end if;
         Protected_Gate.Open;
      end;
      Protected_Gate.Close;
      if not Protected_Entry_Done (3)
        or else Protected_Gate.Waiting /= 0
        or else Protected_Gate.Service_Order (3) /= 3
      then
         Report_Failure;
      end if;
      Report_Exceptional_Protected_Queued_Pass;

      Exception_Abort_Protected_Started := False;
      Exception_Abort_Protected_Caught := False;
      Exception_Abort_Protected_Continued := False;
      Exception_Abort_Protected_Id :=
        Ada.Task_Identification.Null_Task_Id;
      declare
         Worker : Exception_Abort_Protected_Worker_Type (1);
         Worker_Id : constant Ada.Task_Identification.Task_Id :=
           Worker'Identity;
      begin
         for Attempt in 1 .. 1_000 loop
            exit when Exception_Abort_Protected_Started
              and then Exception_Abort_Protected_Id = Worker_Id
              and then Protected_Gate.Failing = 1;
            delay 0.001;
         end loop;
         if not Exception_Abort_Protected_Started
           or else Exception_Abort_Protected_Id /= Worker_Id
           or else Protected_Gate.Failing /= 1
         then
            Report_Failure;
         end if;
         --  Worker is pinned to the environment core. Open completes and
         --  wakes its failing call, but cooperative M4 cannot resume Worker
         --  on that core before this ordinary Ada abort is published.
         Protected_Gate.Open;
         abort Worker;
      end;
      Protected_Gate.Close;
      if Exception_Abort_Protected_Caught
        or else Exception_Abort_Protected_Continued
        or else Protected_Gate.Failing /= 0
        or else not Ada.Task_Identification.Is_Terminated
          (Exception_Abort_Protected_Id)
        or else Ada.Task_Identification.Is_Callable
          (Exception_Abort_Protected_Id)
      then
         Report_Failure;
      end if;
      Report_Exception_Abort_Protected_Pass;
      Run_Protected_Collision_Campaign;

      declare
         Server : Rendezvous_Server_Type
           (System.Multiprocessors.CPU_Range (CPU_Count));
         Value : Integer := 41;
         Accepted : Boolean := False;
      begin
         Ada.Dynamic_Priorities.Set_Priority (7, Server'Identity);
         if Ada.Dynamic_Priorities.Get_Priority (Server'Identity) /= 7 then
            Report_Failure;
         end if;
         select
            Server.Ping (Value);
            Accepted := True;
         else
            null;
         end select;
         if not Accepted then
            Report_Failure;
         end if;
         if Value /= 49 then
            Report_Failure;
         end if;
      end;
      Report_Rendezvous_Pass;
      Report_Priority_Pass;

      declare
         Server : Exceptional_Rendezvous_Server_Type
           (System.Multiprocessors.CPU_Range (CPU_Count));
      begin
         begin
            Server.Ping;
         exception
            when Program_Error =>
               Exceptional_Rendezvous_Caller_Caught := True;
         end;
      end;
      if not Exceptional_Rendezvous_Caller_Caught
        or else not Exceptional_Rendezvous_Server_Caught
      then
         Report_Failure;
      end if;
      Report_Exceptional_Rendezvous_Pass;
      Report_Exceptional_Sync_Pass;

      Exception_Abort_Accepted := False;
      Exception_Abort_Release := False;
      Exception_Abort_Caller_Started := False;
      Exception_Abort_Caller_Caught := False;
      Exception_Abort_Caller_Continued := False;
      Exception_Abort_Server_Caught := False;
      Exception_Abort_Caller_Id :=
        Ada.Task_Identification.Null_Task_Id;
      declare
         Server : aliased Exception_Abort_Server_Type
           (System.Multiprocessors.CPU_Range (CPU_Count));
         Client : Exception_Abort_Client_Type (1, Server'Access);
         Client_Id : constant Ada.Task_Identification.Task_Id :=
           Client'Identity;
      begin
         for Attempt in 1 .. 1_000 loop
            exit when Exception_Abort_Caller_Started
              and then Exception_Abort_Accepted
              and then Exception_Abort_Caller_Id = Client_Id;
            delay 0.001;
         end loop;
         if not Exception_Abort_Caller_Started
           or else not Exception_Abort_Accepted
           or else Exception_Abort_Caller_Id /= Client_Id
         then
            Report_Failure;
         end if;
         abort Client;
         Exception_Abort_Release := True;
      end;
      if not Exception_Abort_Server_Caught
        or else Exception_Abort_Caller_Caught
        or else Exception_Abort_Caller_Continued
        or else not Ada.Task_Identification.Is_Terminated
          (Exception_Abort_Caller_Id)
        or else Ada.Task_Identification.Is_Callable
          (Exception_Abort_Caller_Id)
      then
         Report_Failure;
      end if;
      Report_Exception_Abort_Pass;

      declare
         Server : Delayed_Rendezvous_Server_Type;
         Rejected : Boolean := False;
         Timed_Out : Boolean := False;
      begin
         select
            Server.Ping;
         else
            Rejected := True;
         end select;
         if not Rejected then
            Report_Failure;
         end if;
         select
            Server.Ping;
         or
            delay 0.010;
            Timed_Out := True;
         end select;
         if not Timed_Out then
            Report_Failure;
         end if;
         Server.Ping;
      end;
      Report_Conditional_Pass;

      declare
         Server : Timed_Rendezvous_Server_Type;
         Value : Integer := 20;
         Accepted : Boolean := False;
      begin
         select
            Server.Ping (Value);
            Accepted := True;
         or
            delay 0.100;
         end select;
         if not Accepted or else Value /= 22 then
            Report_Failure;
         end if;
      end;
      Report_Timed_Entry_Pass;

      Run_Dynamic_Worker;
      declare
         use type Ada.Real_Time.Time;
         Completion_Deadline : constant Ada.Real_Time.Time :=
           Ada.Real_Time.Clock + Ada.Real_Time.Milliseconds (100);
      begin
         while Dynamic_Id = Ada.Task_Identification.Null_Task_Id
           or else not Ada.Task_Identification.Is_Terminated (Dynamic_Id)
         loop
            if not (Ada.Real_Time.Clock < Completion_Deadline) then
               Report_Failure;
            end if;
            delay 0.001;
         end loop;
      end;
      if not Dynamic_Done
        or else Dynamic_Id = Ada.Task_Identification.Null_Task_Id
        or else not Ada.Task_Identification.Is_Terminated (Dynamic_Id)
        or else Ada.Task_Identification.Is_Callable (Dynamic_Id)
      then
         Report_Failure;
      end if;
      Report_Dynamic_Task_Pass;

      Run_Free_Worker;
      Report_Free_Task_Pass;

      declare
         Server : Selective_Server_Type;
      begin
         Server.Ping;
      end;
      if not Selective_Done then
         Report_Failure;
      end if;
      Report_Selective_Wait_Pass;

      Run_Terminate_Alternative;
      Report_Terminate_Alternative_Pass;

      Cleanup_Queries_Before := Abort_Cleanup_Query_Count;
      declare
         Worker : Abort_Worker_Type
           (System.Multiprocessors.CPU_Range (CPU_Count));
         Worker_Id : constant Ada.Task_Identification.Task_Id :=
           Worker'Identity;
      begin
         for Attempt in 1 .. 1_000 loop
            exit when Abort_Started and then Abort_Id = Worker_Id;
            delay 0.001;
         end loop;
         if not Abort_Started or else Abort_Id /= Worker_Id then
            Report_Failure;
         end if;
         abort Worker;
      end;
      if Abort_Cleanup_Query_Count <= Cleanup_Queries_Before then
         Report_Failure;
      end if;
      if Abort_Continued or else Abort_User_Handler_Ran
        or else Abort_Id = Ada.Task_Identification.Null_Task_Id
        or else not Ada.Task_Identification.Is_Terminated (Abort_Id)
        or else Ada.Task_Identification.Is_Callable (Abort_Id)
      then
         Report_Failure;
      end if;
      Report_Abort_Pass;

      for Iteration in 1 .. 4 loop
         Multi_Abort_Started := [others => False];
         Multi_Abort_Continued := [others => False];
         Multi_Abort_Ids :=
           [others => Ada.Task_Identification.Null_Task_Id];
         declare
            First : Multi_Abort_Worker_Type (1, 1);
            Second : Multi_Abort_Worker_Type
              (System.Multiprocessors.CPU_Range (CPU_Count), 2);
            First_Id : constant Ada.Task_Identification.Task_Id :=
              First'Identity;
            Second_Id : constant Ada.Task_Identification.Task_Id :=
              Second'Identity;
         begin
            for Attempt in 1 .. 1_000 loop
               exit when Multi_Abort_Started (1)
                 and then Multi_Abort_Started (2);
               delay 0.001;
            end loop;
            if not Multi_Abort_Started (1)
              or else not Multi_Abort_Started (2)
              or else Multi_Abort_Ids (1) /= First_Id
              or else Multi_Abort_Ids (2) /= Second_Id
            then
               Report_Failure;
            end if;
            abort First, Second;
         end;
         if Multi_Abort_Continued (1) or else Multi_Abort_Continued (2)
           or else not Ada.Task_Identification.Is_Terminated
             (Multi_Abort_Ids (1))
           or else not Ada.Task_Identification.Is_Terminated
             (Multi_Abort_Ids (2))
           or else Ada.Task_Identification.Is_Callable (Multi_Abort_Ids (1))
           or else Ada.Task_Identification.Is_Callable (Multi_Abort_Ids (2))
         then
            Report_Failure;
         end if;
      end loop;
      Report_Multi_Abort_Pass;

      Dependent_Abort_Parent_Started := False;
      Dependent_Abort_Child_Started := False;
      Dependent_Abort_Parent_Continued := False;
      Dependent_Abort_Child_Continued := False;
      Dependent_Abort_Parent_Id := Ada.Task_Identification.Null_Task_Id;
      Dependent_Abort_Child_Id := Ada.Task_Identification.Null_Task_Id;
      declare
         Parent : Dependent_Abort_Parent_Type
           (System.Multiprocessors.CPU_Range (CPU_Count));
         Parent_Id : constant Ada.Task_Identification.Task_Id :=
           Parent'Identity;
      begin
         for Attempt in 1 .. 1_000 loop
            exit when Dependent_Abort_Parent_Started
              and then Dependent_Abort_Child_Started;
            delay 0.001;
         end loop;
         if not Dependent_Abort_Parent_Started
           or else not Dependent_Abort_Child_Started
           or else Dependent_Abort_Parent_Id /= Parent_Id
           or else Dependent_Abort_Child_Id =
             Ada.Task_Identification.Null_Task_Id
           or else Dependent_Abort_Child_Id = Parent_Id
         then
            Report_Failure;
         end if;
         abort Parent;
      end;
      if Dependent_Abort_Parent_Continued
        or else Dependent_Abort_Child_Continued
        or else not Ada.Task_Identification.Is_Terminated
          (Dependent_Abort_Parent_Id)
        or else not Ada.Task_Identification.Is_Terminated
          (Dependent_Abort_Child_Id)
        or else Ada.Task_Identification.Is_Callable
          (Dependent_Abort_Parent_Id)
        or else Ada.Task_Identification.Is_Callable
          (Dependent_Abort_Child_Id)
      then
         Report_Failure;
      end if;
      Report_Dependent_Abort_Pass;

      declare
         Server : aliased Abort_Rendezvous_Server_Type
           (System.Multiprocessors.CPU_Range (CPU_Count), True);
         Client : Abort_Rendezvous_Client_Type
           (System.Multiprocessors.CPU_Range (CPU_Count), Server'Access);
         Client_Id : constant Ada.Task_Identification.Task_Id :=
           Client'Identity;
      begin
         for Attempt in 1 .. 1_000 loop
            exit when Abort_Call_Started
              and then Abort_Call_Id = Client_Id
              and then Flyology.M3_Runtime.Demo_Queued_Call_Count = 1;
            delay 0.001;
         end loop;
         if not Abort_Call_Started or else Abort_Call_Id /= Client_Id
           or else Flyology.M3_Runtime.Demo_Queued_Call_Count /= 1
         then
            Report_Failure;
         end if;
         abort Client;
         Server.Ping;
      end;
      if Abort_Call_Continued
        or else Abort_Call_Id = Ada.Task_Identification.Null_Task_Id
        or else not Ada.Task_Identification.Is_Terminated (Abort_Call_Id)
        or else Ada.Task_Identification.Is_Callable (Abort_Call_Id)
      then
         Report_Failure;
      end if;
      Report_Abort_Rendezvous_Pass;

      Abort_Call_Started := False;
      Abort_Call_Continued := False;
      Abort_Call_Id := Ada.Task_Identification.Null_Task_Id;
      Abort_Accept_Entered := False;
      declare
         Server : aliased Abort_Rendezvous_Server_Type
           (System.Multiprocessors.CPU_Range (CPU_Count), False);
         Client : Abort_Rendezvous_Client_Type
           (System.Multiprocessors.CPU_Range (CPU_Count), Server'Access);
         Client_Id : constant Ada.Task_Identification.Task_Id :=
           Client'Identity;
      begin
         for Attempt in 1 .. 1_000 loop
            exit when Abort_Call_Started
              and then Abort_Accept_Entered
              and then Abort_Call_Id = Client_Id;
            delay 0.001;
         end loop;
         if not Abort_Call_Started or else not Abort_Accept_Entered
           or else Abort_Call_Id /= Client_Id
         then
            Report_Failure;
         end if;
         abort Client;
      end;
      if Abort_Call_Continued
        or else Abort_Call_Id = Ada.Task_Identification.Null_Task_Id
        or else not Ada.Task_Identification.Is_Terminated (Abort_Call_Id)
        or else Ada.Task_Identification.Is_Callable (Abort_Call_Id)
      then
         Report_Failure;
      end if;
      Report_Abort_Accepted_Pass;

      declare
         Server : aliased Abort_Rendezvous_Server_Type
           (System.Multiprocessors.CPU_Range (CPU_Count), True);
         Client : Abort_Timed_Client_Type
           (System.Multiprocessors.CPU_Range (CPU_Count), Server'Access);
         Client_Id : constant Ada.Task_Identification.Task_Id :=
           Client'Identity;
      begin
         for Attempt in 1 .. 1_000 loop
            exit when Abort_Timed_Started
              and then Abort_Timed_Id = Client_Id
              and then Flyology.M3_Runtime.Demo_Queued_Call_Count = 1;
            delay 0.001;
         end loop;
         if not Abort_Timed_Started or else Abort_Timed_Id /= Client_Id
           or else Flyology.M3_Runtime.Demo_Queued_Call_Count /= 1
         then
            Report_Failure;
         end if;
         abort Client;
         Server.Ping;
      end;
      if Abort_Timed_Accepted or else Abort_Timed_Out
        or else Abort_Timed_Continued
        or else Abort_Timed_Id = Ada.Task_Identification.Null_Task_Id
        or else not Ada.Task_Identification.Is_Terminated (Abort_Timed_Id)
        or else Ada.Task_Identification.Is_Callable (Abort_Timed_Id)
      then
         Report_Failure;
      end if;
      Report_Abort_Timeout_Pass;
      Run_Rendezvous_Collision_Campaign;
      Report_Collision_Stress_Pass;

      for Index in Auto_Id'Range loop
         if not Auto_Done (Index)
           or else
             (if CPU_Count = 1
              then Auto_Core (Index) /= 0
              else Auto_Core (Index) /= Index - 1)
         then
            Report_Failure;
         end if;
         Check_Identity (Auto_Id (Index), Auto_Object_Id (Index), Environment);
         for Other in Auto_Id'Range loop
            if Index /= Other and then Auto_Id (Index) = Auto_Id (Other) then
               Report_Failure;
            end if;
         end loop;
         for Other in 1 .. CPU_Count loop
            if Auto_Id (Index) = Specific_Id (Other) then
               Report_Failure;
            end if;
         end loop;
      end loop;

      if CPU_Count = 4 then
         Report_Parallel_Pass;
      end if;

      declare
         Parent : Nested_Parent_Type;
      begin
         Parent_Object_Id := Parent'Identity;
      end;
      if not Nested_Parent_Done or else not Nested_Child_Done then
         Report_Failure;
      end if;
      Check_Identity (Nested_Parent_Id, Parent_Object_Id, Environment);
      Check_Identity
        (Nested_Child_Id, Nested_Child_Object_Id, Environment);
      if Nested_Parent_Id = Nested_Child_Id then
         Report_Failure;
      end if;
      Report_Master_Pass;
      Report_Stack_Pass;
      Report_Ordinary_Pass;
   end Run;
end Flyology.M3_Demo;
