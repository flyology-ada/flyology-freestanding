--  SPDX-License-Identifier: MIT OR Apache-2.0

with Ada.Dynamic_Priorities;
with Ada.Real_Time;
with Ada.Task_Identification;
with Flyology.M3_Runtime;
with System.Multiprocessors;

package body Flyology.M3_Demo is
   use type Ada.Task_Identification.Task_Id;
   use type System.Any_Priority;

   type Done_Array is array (Positive range 1 .. 4) of Boolean
     with Atomic_Components;
   type Identity_Array is array (Positive range 1 .. 4) of
     Ada.Task_Identification.Task_Id with Atomic_Components;
   type Core_Array is array (Positive range 1 .. 4) of Natural
     with Atomic_Components;
   type Stack_Probe_Array is array (Natural range 0 .. 255) of Character;
   type Counter_Pair is array (Positive range 1 .. 2) of Natural;

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

   protected Protected_Gate is
      procedure Open;
      entry Wait (Index : Positive);
      function Service_Order (Index : Positive) return Natural;
      function Waiting return Natural;
   private
      Opened        : Boolean := False;
      Service_Count : Natural := 0;
      Service_Log   : Counter_Pair := [others => 0];
   end Protected_Gate;

   protected body Protected_Gate is
      procedure Open is
      begin
         Opened := True;
      end Open;

      entry Wait (Index : Positive) when Opened is
      begin
         Service_Count := Service_Count + 1;
         Service_Log (Service_Count) := Index;
      end Wait;

      function Service_Order (Index : Positive) return Natural is
        (Service_Log (Index));

      function Waiting return Natural is (Wait'Count);
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
   Selective_Done : Boolean := False with Atomic;
   Abort_Started : Boolean := False with Atomic;
   Abort_Continued : Boolean := False with Atomic;
   Abort_Id : Ada.Task_Identification.Task_Id :=
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

   task type Dynamic_Worker_Type;
   type Dynamic_Worker_Access is access Dynamic_Worker_Type;

   task type Selective_Server_Type is
      entry Ping;
   end Selective_Server_Type;

   task type Abort_Worker_Type
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

   task body Selective_Server_Type is
   begin
      select
         accept Ping;
      or
         terminate;
      end select;
      Selective_Done := True;
   end Selective_Server_Type;

   task body Abort_Worker_Type is
   begin
      Abort_Id := Ada.Task_Identification.Current_Task;
      Abort_Started := True;
      delay 1.0;
      Abort_Continued := True;
   end Abort_Worker_Type;

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
      Protected_Gate.Wait (Index);
      Protected_Entry_Done (Index) := True;
   end Protected_Entry_Worker_Type;

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

   procedure Report_Priority_Pass
   with Import, Convention => C,
        External_Name => "flyology_m4_report_priority_pass";

   procedure Report_Conditional_Pass
   with Import, Convention => C,
        External_Name => "flyology_m4_report_conditional_pass";

   procedure Report_Timed_Entry_Pass
   with Import, Convention => C,
        External_Name => "flyology_m4_report_timed_entry_pass";

   procedure Report_Dynamic_Task_Pass
   with Import, Convention => C,
        External_Name => "flyology_m4_report_dynamic_task_pass";

   procedure Report_Selective_Wait_Pass
   with Import, Convention => C,
        External_Name => "flyology_m4_report_selective_wait_pass";

   procedure Report_Abort_Pass
   with Import, Convention => C,
        External_Name => "flyology_m4_report_abort_pass";

   procedure Report_Abort_Rendezvous_Pass
   with Import, Convention => C,
        External_Name => "flyology_m4_report_abort_rendezvous_pass";

   procedure Report_Abort_Timeout_Pass
   with Import, Convention => C,
        External_Name => "flyology_m4_report_abort_timeout_pass";

   procedure Report_Abort_Accepted_Pass
   with Import, Convention => C,
        External_Name => "flyology_m4_report_abort_accepted_pass";

   procedure Report_Master_Pass
   with Import, Convention => C,
        External_Name => "flyology_m3_report_master_pass";

   procedure Report_Stack_Pass
   with Import, Convention => C,
        External_Name => "flyology_m3_report_stack_pass";

   procedure Report_Failure
   with Import, Convention => C,
        External_Name => "flyology_m2_report_failure";

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
         Rejected  : Boolean := False;
         Timed_Out : Boolean := False;
      begin
         select
            Protected_Gate.Wait (1);
         else
            Rejected := True;
         end select;
         select
            Protected_Gate.Wait (2);
         or
            delay 0.001;
            Timed_Out := True;
         end select;
         if not Rejected or else not Timed_Out
           or else Protected_Gate.Waiting /= 0
         then
            Report_Failure;
         end if;
      end;

      declare
         Worker_1 : Protected_Entry_Worker_Type
           (System.Multiprocessors.CPU_Range (CPU_Count), 1);
         Worker_2 : Protected_Entry_Worker_Type
           (System.Multiprocessors.CPU_Range (CPU_Count), 2);
      begin
         delay 0.001;
         if Protected_Entry_Done (1) or else Protected_Entry_Done (2) then
            Report_Failure;
         end if;
         Protected_Gate.Open;
      end;
      if not Protected_Entry_Done (1) or else not Protected_Entry_Done (2)
        or else Protected_Gate.Service_Order (1) /= 1
        or else Protected_Gate.Service_Order (2) /= 2
      then
         Report_Failure;
      end if;
      Report_Protected_Entry_Pass;

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
      if not Dynamic_Done
        or else Dynamic_Id = Ada.Task_Identification.Null_Task_Id
        or else not Ada.Task_Identification.Is_Terminated (Dynamic_Id)
        or else Ada.Task_Identification.Is_Callable (Dynamic_Id)
      then
         Report_Failure;
      end if;
      Report_Dynamic_Task_Pass;

      declare
         Server : Selective_Server_Type;
      begin
         Server.Ping;
      end;
      if not Selective_Done then
         Report_Failure;
      end if;
      Report_Selective_Wait_Pass;

      declare
         Worker : Abort_Worker_Type
           (System.Multiprocessors.CPU_Range (CPU_Count));
         Worker_Id : constant Ada.Task_Identification.Task_Id :=
           Worker'Identity;
      begin
         delay 0.001;
         if not Abort_Started or else Abort_Id /= Worker_Id then
            Report_Failure;
         end if;
         abort Worker;
      end;
      if Abort_Continued
        or else Abort_Id = Ada.Task_Identification.Null_Task_Id
        or else not Ada.Task_Identification.Is_Terminated (Abort_Id)
        or else Ada.Task_Identification.Is_Callable (Abort_Id)
      then
         Report_Failure;
      end if;
      Report_Abort_Pass;

      declare
         Server : aliased Abort_Rendezvous_Server_Type
           (System.Multiprocessors.CPU_Range (CPU_Count), True);
         Client : Abort_Rendezvous_Client_Type
           (System.Multiprocessors.CPU_Range (CPU_Count), Server'Access);
         Client_Id : constant Ada.Task_Identification.Task_Id :=
           Client'Identity;
      begin
         delay 0.001;
         if not Abort_Call_Started or else Abort_Call_Id /= Client_Id then
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
         delay 0.001;
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
         delay 0.001;
         if not Abort_Timed_Started or else Abort_Timed_Id /= Client_Id then
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
