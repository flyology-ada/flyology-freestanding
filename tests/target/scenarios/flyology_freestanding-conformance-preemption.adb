--  SPDX-License-Identifier: MIT OR Apache-2.0

with Ada.Dynamic_Priorities;
with Ada.Real_Time;
with System.Multiprocessors;
with System;

package body Flyology_Freestanding.Conformance.Preemption is
   use type System.Multiprocessors.CPU_Range;
   use type Ada.Real_Time.Time;
   use type System.Address;

   Spin_Limit : constant := 50_000_000;
   Threshold  : constant := 10_000;

   --  Keep every task body at library level.  A nested task body makes GNAT
   --  materialize an executable trampoline in its master's stack frame;
   --  Flyology_Freestanding task stacks are deliberately non-executable.
   FIFO_Low_Started : Boolean := False with Atomic;
   FIFO_High_Ran    : aliased Boolean := False with Atomic;
   FIFO_Low_Done    : Boolean := False with Atomic;
   FIFO_Low_Count   : Natural := 0 with Atomic;

   RR_First_Count  : Natural := 0 with Atomic;
   RR_Second_Count : Natural := 0 with Atomic;
   RR_First_Done   : Boolean := False with Atomic;
   RR_Second_Done  : Boolean := False with Atomic;

   Remote_Low_Started : Boolean := False with Atomic;
   Remote_High_Ran    : aliased Boolean := False with Atomic;
   Remote_Low_Done    : Boolean := False with Atomic;

   type Core_Flag_Array is array (Positive range 1 .. 4) of Boolean
     with Atomic_Components;
   All_Core_Started : Core_Flag_Array := [others => False];
   All_Core_Done    : Core_Flag_Array := [others => False];
   All_Core_Release : Core_Flag_Array := [others => False];

   FIFO_Equal_First_Started  : Boolean := False with Atomic;
   FIFO_Equal_Second_Started : Boolean := False with Atomic;
   FIFO_Equal_First_Done     : Boolean := False with Atomic;
   FIFO_Equal_Second_Done    : Boolean := False with Atomic;
   FIFO_Equal_Release        : aliased Boolean := False with Atomic;

   Priority_Requeue_Release : Boolean := False with Atomic;
   Priority_Requeue_Order   : Natural := 0 with Atomic;
   Priority_Requeue_A_Order : Natural := 0 with Atomic;
   Priority_Requeue_B_Order : Natural := 0 with Atomic;
   Priority_Requeue_C_Order : Natural := 0 with Atomic;

   Ingress_Holding     : Boolean := False with Atomic;
   Ingress_Release     : Boolean := False with Atomic;
   Ingress_Holder_Done : Boolean := False with Atomic;
   Ingress_Producer_Started : Boolean := False with Atomic;
   Ingress_High_Armed : Boolean := False with Atomic;
   Ingress_High_Ran    : aliased Boolean := False with Atomic;
   Ingress_Producer_Done : Boolean := False with Atomic;
   Ingress_Progress    : Natural := 0 with Atomic;
   Ingress_Retry_Before : System.Address := 0 with Atomic;

   protected Ingress_Lock_Holder is
      procedure Hold_Until_Released;
   end Ingress_Lock_Holder;

   protected body Ingress_Lock_Holder is
      procedure Hold_Until_Released is
      begin
         Ingress_Holding := True;
         while not Ingress_Release loop
            null;
         end loop;
         Ingress_Holder_Done := True;
      end Hold_Until_Released;
   end Ingress_Lock_Holder;

   procedure Report_Failure
   with Import, Convention => C,
        External_Name => "flyology_freestanding_conformance_report_failure";

   procedure Report_FIFO_Pass
   with Import, Convention => C,
        External_Name => "flyology_freestanding_conformance_report_fifo_preemption_pass";

   procedure Report_Round_Robin_Pass
   with Import, Convention => C,
        External_Name => "flyology_freestanding_conformance_report_round_robin_pass";

   procedure Report_Remote_Pass
   with Import, Convention => C,
        External_Name => "flyology_freestanding_conformance_report_remote_preemption_pass";

   procedure Report_All_Core_Pass
   with Import, Convention => C,
        External_Name => "flyology_freestanding_conformance_report_all_core_preemption_pass";

   procedure Report_FIFO_No_Rotation_Pass
   with Import, Convention => C,
        External_Name => "flyology_freestanding_conformance_report_fifo_no_rotation_pass";

   procedure Report_Priority_Requeue_Pass
   with Import, Convention => C,
        External_Name => "flyology_freestanding_conformance_report_priority_requeue_pass";

   procedure Report_Nonblocking_Ingress_Pass
   with Import, Convention => C,
        External_Name => "flyology_freestanding_conformance_report_nonblocking_ingress_pass";

   function Retry_Count return System.Address
   with Import, Convention => C,
        External_Name => "flyology_freestanding_platform_retry_count";

   procedure Check_Full_Context (Completion_Flag : System.Address)
   with Import, Convention => C,
        External_Name => "flyology_freestanding_conformance_preemption_canary";

   task type FIFO_Low_Task with CPU => 1, Priority => 5;
   task type FIFO_High_Task with CPU => 1, Priority => 10;
   task type RR_First_Task with CPU => 1, Priority => 5;
   task type RR_Second_Task with CPU => 1, Priority => 5;
   task type Remote_Low_Task with CPU => 2, Priority => 5;
   task type Remote_High_Task with CPU => 2, Priority => 10 is
      entry Release;
   end Remote_High_Task;
   task type All_Core_Load_Task
     (Assigned_CPU : System.Multiprocessors.CPU_Range)
     with CPU => Assigned_CPU, Priority => 5;
   task type All_Core_Coordinator_Task
     (Assigned_CPU : System.Multiprocessors.CPU_Range)
     with CPU => Assigned_CPU, Priority => 10;
   task type FIFO_Equal_First_Task with CPU => 1, Priority => 5;
   task type FIFO_Equal_Second_Task with CPU => 1, Priority => 5;
   task type FIFO_Equal_Observer_Task with CPU => 1, Priority => 10;
   task type Priority_Requeue_Blocker_Task with CPU => 2, Priority => 10;
   task type Priority_Requeue_A_Task with CPU => 2, Priority => 5;
   task type Priority_Requeue_B_Task with CPU => 2, Priority => 4;
   task type Priority_Requeue_C_Task with CPU => 2, Priority => 4;
   task type Ingress_Holder_Task with CPU => 1, Priority => 5;
   task type Ingress_Producer_Task with CPU => 2, Priority => 5;
   task type Ingress_High_Task with CPU => 2, Priority => 10;

   task body FIFO_Low_Task is
   begin
      FIFO_Low_Started := True;
      Check_Full_Context (FIFO_High_Ran'Address);
      FIFO_Low_Count := 1;
      if not FIFO_High_Ran then
         Report_Failure;
      end if;
      FIFO_Low_Done := True;
   end FIFO_Low_Task;

   task body FIFO_High_Task is
   begin
      --  High runs first and repeatedly blocks until Low has entered its
      --  no-safe-point loop.  Its final delay therefore expires only while
      --  Low is known to be executing application code.
      for Attempt in 1 .. 100 loop
         exit when FIFO_Low_Started;
         delay 0.001;
      end loop;
      if not FIFO_Low_Started then
         Report_Failure;
      end if;
      delay 0.005;
      FIFO_High_Ran := True;
   end FIFO_High_Task;

   task body RR_First_Task is
   begin
      for Iteration in 1 .. Spin_Limit loop
         RR_First_Count := Iteration;
         exit when RR_First_Count >= Threshold
           and then RR_Second_Count >= Threshold;
      end loop;
      if RR_First_Count < Threshold or else RR_Second_Count < Threshold then
         Report_Failure;
      end if;
      RR_First_Done := True;
   end RR_First_Task;

   task body RR_Second_Task is
   begin
      for Iteration in 1 .. Spin_Limit loop
         RR_Second_Count := Iteration;
         exit when RR_First_Count >= Threshold
           and then RR_Second_Count >= Threshold;
      end loop;
      if RR_First_Count < Threshold or else RR_Second_Count < Threshold then
         Report_Failure;
      end if;
      RR_Second_Done := True;
   end RR_Second_Task;

   task body Remote_Low_Task is
   begin
      Remote_Low_Started := True;
      Check_Full_Context (Remote_High_Ran'Address);
      if not Remote_High_Ran then
         Report_Failure;
      end if;
      Remote_Low_Done := True;
   end Remote_Low_Task;

   task body Remote_High_Task is
   begin
      accept Release do
         Remote_High_Ran := True;
      end Release;
   end Remote_High_Task;

   task body All_Core_Load_Task is
      Index : constant Positive := Positive (Assigned_CPU);
   begin
      All_Core_Started (Index) := True;
      Check_Full_Context (All_Core_Release (Index)'Address);
      All_Core_Done (Index) := True;
   end All_Core_Load_Task;

   task body All_Core_Coordinator_Task is
      Index : constant Positive := Positive (Assigned_CPU);
   begin
      for Attempt in 1 .. 1_000 loop
         exit when All_Core_Started (Index);
         delay 0.001;
      end loop;
      if not All_Core_Started (Index) then
         Report_Failure;
      end if;
      --  Each core has its own delayed higher-priority coordinator.  Its
      --  local timer must preempt that core's no-safe-point load task before
      --  the corresponding architecture canary may finish.
      delay 0.005;
      All_Core_Release (Index) := True;
   end All_Core_Coordinator_Task;

   task body FIFO_Equal_First_Task is
   begin
      FIFO_Equal_First_Started := True;
      Check_Full_Context (FIFO_Equal_Release'Address);
      FIFO_Equal_First_Done := True;
   end FIFO_Equal_First_Task;

   task body FIFO_Equal_Second_Task is
   begin
      FIFO_Equal_Second_Started := True;
      FIFO_Equal_Second_Done := True;
   end FIFO_Equal_Second_Task;

   task body FIFO_Equal_Observer_Task is
   begin
      for Attempt in 1 .. 1_000 loop
         exit when FIFO_Equal_First_Started;
         delay 0.001;
      end loop;
      if not FIFO_Equal_First_Started then
         Report_Failure;
      end if;
      delay 0.010;
      if FIFO_Equal_Second_Started then
         Report_Failure;
      end if;
      FIFO_Equal_Release := True;
   end FIFO_Equal_Observer_Task;

   task body Priority_Requeue_Blocker_Task is
   begin
      delay 0.005;
      for Iteration in 1 .. Spin_Limit loop
         exit when Priority_Requeue_Release;
      end loop;
      if not Priority_Requeue_Release then
         Report_Failure;
      end if;
   end Priority_Requeue_Blocker_Task;

   task body Priority_Requeue_A_Task is
   begin
      --  Run first to register the oldest wake, then lower the base priority
      --  before blocking.  The environment later raises this Ready task to
      --  B/C's priority; correct semantics reinsert it behind both peers.
      Ada.Dynamic_Priorities.Set_Priority (3);
      delay 0.010;
      Priority_Requeue_Order := Priority_Requeue_Order + 1;
      Priority_Requeue_A_Order := Priority_Requeue_Order;
   end Priority_Requeue_A_Task;

   task body Priority_Requeue_B_Task is
   begin
      delay 0.015;
      Priority_Requeue_Order := Priority_Requeue_Order + 1;
      Priority_Requeue_B_Order := Priority_Requeue_Order;
   end Priority_Requeue_B_Task;

   task body Priority_Requeue_C_Task is
   begin
      delay 0.015;
      Priority_Requeue_Order := Priority_Requeue_Order + 1;
      Priority_Requeue_C_Order := Priority_Requeue_Order;
   end Priority_Requeue_C_Task;

   task body Ingress_Holder_Task is
   begin
      for Attempt in 1 .. Spin_Limit loop
         exit when Ingress_Producer_Started;
      end loop;
      if not Ingress_Producer_Started then
         Report_Failure;
      end if;
      Ingress_Lock_Holder.Hold_Until_Released;
   end Ingress_Holder_Task;

   task body Ingress_Producer_Task is
      Hold_Until : Ada.Real_Time.Time;
   begin
      Ingress_Producer_Started := True;
      for Attempt in 1 .. Spin_Limit loop
         exit when Ingress_Holding;
      end loop;
      if not Ingress_Holding then
         Report_Failure;
      end if;
      if not Ingress_High_Armed or else Ingress_High_Ran then
         Report_Failure;
      end if;
      --  The CPU-2 timer expires while CPU 1 owns the RTS lock through the
      --  protected action.  Interrupt ingress must return to this task rather
      --  than spin on that remote lock, allowing it to release the owner.
      Hold_Until := Ada.Real_Time.Clock + Ada.Real_Time.Milliseconds (50);
      while Ada.Real_Time.Clock < Hold_Until loop
         Ingress_Progress := 1;
      end loop;
      Ingress_Release := True;
      Check_Full_Context (Ingress_High_Ran'Address);
      Ingress_Producer_Done := True;
   end Ingress_Producer_Task;

   task body Ingress_High_Task is
   begin
      --  This task runs first on CPU 2.  The producer cannot execute until
      --  this deadline has been registered and the task has blocked.
      Ingress_High_Armed := True;
      delay 0.010;
      Ingress_High_Ran := True;
   end Ingress_High_Task;

   procedure Check_FIFO_Preemption is
      procedure Execute is
         Low  : FIFO_Low_Task;
         High : FIFO_High_Task;
      begin
         null;
      end Execute;
   begin
      FIFO_Low_Started := False;
      FIFO_High_Ran := False;
      FIFO_Low_Done := False;
      FIFO_Low_Count := 0;
      Execute;
      if not FIFO_Low_Done
        or else not FIFO_High_Ran
        or else FIFO_Low_Count = 0
      then
         Report_Failure;
      end if;
      Report_FIFO_Pass;
   end Check_FIFO_Preemption;

   procedure Check_Round_Robin is
      procedure Execute is
         First  : RR_First_Task;
         Second : RR_Second_Task;
      begin
         null;
      end Execute;
   begin
      RR_First_Count := 0;
      RR_Second_Count := 0;
      RR_First_Done := False;
      RR_Second_Done := False;
      Execute;
      if not RR_First_Done or else not RR_Second_Done then
         Report_Failure;
      end if;
      Report_Round_Robin_Pass;
   end Check_Round_Robin;

   procedure Check_Remote_Preemption is
      procedure Execute is
         Low  : Remote_Low_Task;
         High : Remote_High_Task;
      begin
         for Attempt in 1 .. Spin_Limit loop
            exit when Remote_Low_Started;
         end loop;
         if not Remote_Low_Started then
            Report_Failure;
         end if;
         --  The environment task runs on CPU 1.  Calling this CPU-2 entry
         --  publishes a higher-priority ready task and sends a remote
         --  reschedule interrupt while Low has no runtime safe point.
         High.Release;
      end Execute;
   begin
      Remote_Low_Started := False;
      Remote_High_Ran := False;
      Remote_Low_Done := False;
      Execute;
      if not Remote_High_Ran or else not Remote_Low_Done then
         Report_Failure;
      end if;
      Report_Remote_Pass;
   end Check_Remote_Preemption;

   procedure Check_All_Core_Preemption is
      procedure Execute is
         Load_1      : All_Core_Load_Task (1);
         Load_2      : All_Core_Load_Task (2);
         Load_3      : All_Core_Load_Task (3);
         Load_4      : All_Core_Load_Task (4);
         Coordinator_1 : All_Core_Coordinator_Task (1);
         Coordinator_2 : All_Core_Coordinator_Task (2);
         Coordinator_3 : All_Core_Coordinator_Task (3);
         Coordinator_4 : All_Core_Coordinator_Task (4);
      begin
         null;
      end Execute;
   begin
      All_Core_Started := [others => False];
      All_Core_Done := [others => False];
      All_Core_Release := [others => False];
      Execute;
      if (for some Done of All_Core_Done => not Done) then
         Report_Failure;
      end if;
      Report_All_Core_Pass;
   end Check_All_Core_Preemption;

   procedure Check_FIFO_No_Rotation is
      procedure Execute is
         First    : FIFO_Equal_First_Task;
         Second   : FIFO_Equal_Second_Task;
         Observer : FIFO_Equal_Observer_Task;
      begin
         null;
      end Execute;
   begin
      FIFO_Equal_First_Started := False;
      FIFO_Equal_Second_Started := False;
      FIFO_Equal_First_Done := False;
      FIFO_Equal_Second_Done := False;
      FIFO_Equal_Release := False;
      Execute;
      if not FIFO_Equal_First_Done or else not FIFO_Equal_Second_Done then
         Report_Failure;
      end if;
      Report_FIFO_No_Rotation_Pass;
   end Check_FIFO_No_Rotation;

   procedure Check_Priority_Requeue is
      procedure Execute is
         Blocker : Priority_Requeue_Blocker_Task;
         A       : Priority_Requeue_A_Task;
         B       : Priority_Requeue_B_Task;
         C       : Priority_Requeue_C_Task;
      begin
         delay 0.050;
         Ada.Dynamic_Priorities.Set_Priority (4, A'Identity);
         Priority_Requeue_Release := True;
      end Execute;
   begin
      Priority_Requeue_Release := False;
      Priority_Requeue_Order := 0;
      Priority_Requeue_A_Order := 0;
      Priority_Requeue_B_Order := 0;
      Priority_Requeue_C_Order := 0;
      Execute;
      if Priority_Requeue_A_Order /= 3
        or else Priority_Requeue_B_Order not in 1 .. 2
        or else Priority_Requeue_C_Order not in 1 .. 2
        or else Priority_Requeue_B_Order = Priority_Requeue_C_Order
      then
         Report_Failure;
      end if;
      Report_Priority_Requeue_Pass;
   end Check_Priority_Requeue;

   procedure Check_Nonblocking_Ingress is
      procedure Execute is
         Holder   : Ingress_Holder_Task;
         Producer : Ingress_Producer_Task;
         High     : Ingress_High_Task;
      begin
         null;
      end Execute;
   begin
      Ingress_Holding := False;
      Ingress_Release := False;
      Ingress_Holder_Done := False;
      Ingress_Producer_Started := False;
      Ingress_High_Armed := False;
      Ingress_High_Ran := False;
      Ingress_Producer_Done := False;
      Ingress_Progress := 0;
      Ingress_Retry_Before := Retry_Count;
      Execute;
      if not Ingress_Holder_Done
        or else not Ingress_High_Ran
        or else not Ingress_Producer_Started
        or else not Ingress_Producer_Done
        or else Ingress_Progress = 0
        or else Retry_Count <= Ingress_Retry_Before
      then
         Report_Failure;
      end if;
      Report_Nonblocking_Ingress_Pass;
   end Check_Nonblocking_Ingress;

   procedure Run (Policy : Character) is
   begin
      if Policy not in 'F' | 'R' then
         Report_Failure;
      end if;
      Check_FIFO_Preemption;
      if Policy = 'R' then
         Check_Round_Robin;
      else
         Check_FIFO_No_Rotation;
      end if;
      if System.Multiprocessors.Number_Of_CPUs > 1 then
         Check_Remote_Preemption;
         Check_Nonblocking_Ingress;
         Check_Priority_Requeue;
      end if;
      if System.Multiprocessors.Number_Of_CPUs = 4 then
         Check_All_Core_Preemption;
      end if;
   end Run;
end Flyology_Freestanding.Conformance.Preemption;
