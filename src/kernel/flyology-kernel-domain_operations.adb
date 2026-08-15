--  SPDX-License-Identifier: MIT OR Apache-2.0

separate (Flyology.Kernel)
package body Domain_Operations is
   procedure Configure_Dispatching
     (Policy : Dispatching_Policy;
      Slice  : Binder_Time_Slice)
   is
      Rate    : constant Frequency := Clock_Frequency;
      Quantum : Preemption.Clock.Tick := 0;
   begin
      if Policy_Configured
        or else not Preemption.Configuration_Is_Valid (Policy, Slice, Rate)
      then
         Stop;
      end if;
      Domain_Policies (System_Domain) := Policy;
      if Policy = Preemption.Round_Robin_Within_Priorities then
         Quantum := Preemption.Quantum_Ticks (Slice, Rate);
      end if;
      for Core in Core_Number loop
         if Natural (Core) < Configured then
            Core_Policies (Core) := Policy;
            Core_Slices (Core) := Slice;
            Core_Quanta (Core) := Quantum;
         end if;
      end loop;
      if Current_Tasks (0) /= No_Task then
         declare
            Slot : constant Task_Slot := Slot_Of (Current_Tasks (0));
            Now  : constant Preemption.Clock.Tick :=
              Preemption.Clock.Tick (Read_Clock);
         begin
            if Policy = Preemption.Round_Robin_Within_Priorities then
               Tasks (Slot).Budget :=
                 Preemption.Start_Budget (Policy, Now, Quantum);
            else
               Tasks (Slot).Budget := Preemption.Empty_Budget;
            end if;
         end;
      end if;
      Policy_Configured := True;
   end Configure_Dispatching;

   function Configuration_Snapshot_Locked return
     Scheduling.Configuration_State
   is
      Result : Scheduling.Configuration_State :=
        (Cores => Scheduling.Core_Count (Configured), others => <>);
   begin
      for Core in Core_Number loop
         if Natural (Core) < Configured then
            Result.Policies (Scheduling.Core_Number (Core)) :=
              Core_Policies (Core);
            Result.Slices (Scheduling.Core_Number (Core)) :=
              Core_Slices (Core);
         end if;
      end loop;
      if not Scheduling.Valid (Result, Clock_Frequency) then
         Stop;
      end if;
      return Result;
   end Configuration_Snapshot_Locked;

   procedure Apply_Policy_Change_Locked
     (Targets  : Core_Set;
      Policy   : Dispatching_Policy;
      Slice    : Binder_Time_Slice;
      Affected : out Core_Set)
   is
      Rate          : constant Frequency := Clock_Frequency;
      Before        : Scheduling.Configuration_State;
      Model_Targets : Scheduling.Core_Set := [others => False];
      Attempt       : Scheduling.Change_Result;
      Quantum       : Preemption.Clock.Tick := 0;
      Now           : Preemption.Clock.Tick;
   begin
      Affected := [others => False];
      if not Policy_Configured then
         Stop;
      end if;
      for Core in Core_Number loop
         Model_Targets (Scheduling.Core_Number (Core)) := Targets (Core);
      end loop;
      Before := Configuration_Snapshot_Locked;
      Attempt := Scheduling.Try_Change
        (Before, Model_Targets, Policy, Slice, Rate);
      if Attempt.Status /= Scheduling.Changed then
         Stop;
      end if;
      if Policy = Preemption.Round_Robin_Within_Priorities then
         Quantum := Preemption.Quantum_Ticks (Slice, Rate);
      end if;
      Now := Preemption.Clock.Tick (Read_Clock);
      for Core in Core_Number loop
         if Targets (Core) then
            Core_Policies (Core) :=
              Attempt.State.Policies (Scheduling.Core_Number (Core));
            Core_Slices (Core) :=
              Attempt.State.Slices (Scheduling.Core_Number (Core));
            Core_Quanta (Core) := Quantum;
            Affected (Core) := True;
         end if;
      end loop;
      for Slot in Task_Slot loop
         if Tasks (Slot).Present
           and then Targets (Tasks (Slot).Assigned_Core)
         then
            if Tasks (Slot).State = Dispatcher.Running
              and then Policy = Preemption.Round_Robin_Within_Priorities
            then
               Tasks (Slot).Budget :=
                 Preemption.Start_Budget (Policy, Now, Quantum);
            else
               Tasks (Slot).Budget := Preemption.Empty_Budget;
            end if;
         end if;
      end loop;
   end Apply_Policy_Change_Locked;

   procedure Change_Global_Policy_Locked
     (Policy   : Dispatching_Policy;
      Slice    : Binder_Time_Slice;
      Affected : out Core_Set)
   is
      Targets : Core_Set := [others => False];
   begin
      for Core in Core_Number loop
         Targets (Core) := Natural (Core) < Configured;
      end loop;
      Apply_Policy_Change_Locked (Targets, Policy, Slice, Affected);
      for Domain in Domain_Number loop
         if Domain_Used (Domain) then
            Domain_Policies (Domain) := Policy;
         end if;
      end loop;
   end Change_Global_Policy_Locked;

   procedure Change_Domain_Policy_Locked
     (Cores    : Core_Set;
      Policy   : Dispatching_Policy;
      Slice    : Binder_Time_Slice;
      Affected : out Core_Set)
   is
      Matched : Boolean := False;
      Selected : Domain_Number := System_Domain;
   begin
      for Domain in Domain_Number loop
         if Domain_Used (Domain) then
            declare
               Same : Boolean := True;
            begin
               for Core in Core_Number loop
                  if Cores (Core) /=
                    (Natural (Core) < Configured
                     and then Core_Domains (Core) = Domain)
                  then
                     Same := False;
                  end if;
               end loop;
               if Same then
                  if Matched then
                     Stop;
                  end if;
                  Matched := True;
                  Selected := Domain;
               end if;
            end;
         end if;
      end loop;
      if not Matched then
         Stop;
      end if;
      Apply_Policy_Change_Locked (Cores, Policy, Slice, Affected);
      Domain_Policies (Selected) := Policy;
   end Change_Domain_Policy_Locked;

   procedure Change_Core_Policy_Locked
     (Core     : Core_Number;
      Policy   : Dispatching_Policy;
      Slice    : Binder_Time_Slice;
      Affected : out Core_Set)
   is
      Targets : Core_Set := [others => False];
   begin
      if Natural (Core) >= Configured then
         Stop;
      end if;
      Targets (Core) := True;
      Apply_Policy_Change_Locked (Targets, Policy, Slice, Affected);
   end Change_Core_Policy_Locked;

   function Policy_Of_Core_Locked
     (Core : Core_Number) return Dispatching_Policy
   is
   begin
      if not Policy_Configured or else Natural (Core) >= Configured then
         Stop;
      end if;
      return Core_Policies (Core);
   end Policy_Of_Core_Locked;

   function Slice_Of_Core_Locked
     (Core : Core_Number) return Binder_Time_Slice
   is
   begin
      if not Policy_Configured or else Natural (Core) >= Configured then
         Stop;
      end if;
      return Core_Slices (Core);
   end Slice_Of_Core_Locked;

   function Domain_Snapshot_Locked return Domains.Domain_State is
      Result : Domains.Domain_State :=
        Domains.Initial (Domains.CPU_Count (Configured));
      Count  : Positive range 1 .. Max_Domains := 1;
   begin
      for Domain in Domain_Number range 1 .. Domain_Number'Last loop
         if Domain_Used (Domain) then
            Count := Count + 1;
         end if;
      end loop;
      Result.Domain_Count := Count;
      for Domain in Domain_Number loop
         Result.Domains (Domains.Domain_Id (Domain)).Used :=
           Domain_Used (Domain);
         Result.Domains (Domains.Domain_Id (Domain)).Policy :=
           (if Domain_Policies (Domain) =
              Preemption.FIFO_Within_Priorities
            then Domains.FIFO_Within_Priorities
            else Domains.Round_Robin_Within_Priorities);
         for Core in Core_Number loop
            Result.Domains (Domains.Domain_Id (Domain)).Cores
              (Domains.Core_Id (Core)) :=
                Natural (Core) < Configured
                and then Core_Domains (Core) = Domain;
         end loop;
      end loop;
      for Core in Core_Number loop
         Result.Owners (Domains.Core_Id (Core)) :=
           (Assigned => Natural (Core) < Configured,
            Domain   => Domains.Domain_Id (Core_Domains (Core)));
      end loop;
      for Slot in Task_Slot loop
         if Tasks (Slot).Present
           and then Tasks (Slot).State /= Dispatcher.Dormant
         then
            Result.Tasks (Domains.Task_Id (Slot)) :=
              (Present       => True,
               Domain        => Domains.Domain_Id (Tasks (Slot).Domain),
               Core          => Domains.Core_Id (Tasks (Slot).Assigned_Core),
               Requested_CPU =>
                 (if Slot = 0 then 1 else Domains.Not_A_Specific_CPU));
         end if;
      end loop;
      return Result;
   end Domain_Snapshot_Locked;

   procedure Try_Create_Domain_Locked
     (Cores   : Core_Set;
      Policy  : Dispatching_Policy;
      Slice   : Binder_Time_Slice;
      Domain  : out Domain_Number;
      Created : out Boolean)
   is
      Before       : Domains.Domain_State;
      Selected_Set : Domains.Core_Set := [others => False];
      Attempt      : Domains.Create_Result;
      Selected     : Domain_Number := Domain_Number'First;
      Rate         : constant Frequency := Clock_Frequency;
      Quantum      : Preemption.Clock.Tick := 0;
   begin
      Domain := System_Domain;
      Created := False;
      if not Policy_Configured
        or else not Preemption.Configuration_Is_Valid (Policy, Slice, Rate)
      then
         Stop;
      end if;
      for Core in Core_Number loop
         if Cores (Core) then
            if Natural (Core) >= Configured
              or else Current_Tasks (Core) /= No_Task
              or else Ready_Queues (Core).Length /= 0
              or else Timer_Tables (Core) /= Timers.Empty_Table
            then
               return;
            end if;
            for Slot in Task_Slot loop
               if Tasks (Slot).Present
                 and then Tasks (Slot).State /= Dispatcher.Dormant
                 and then Tasks (Slot).Assigned_Core = Core
               then
                  return;
               end if;
            end loop;
         end if;
         Selected_Set (Domains.Core_Id (Core)) := Cores (Core);
      end loop;
      Before := Domain_Snapshot_Locked;
      if not Domains.Valid (Before) then
         Stop;
      end if;
      Attempt := Domains.Try_Create
        (Before,
         Selected_Set,
         (if Policy = Preemption.FIFO_Within_Priorities
          then Domains.FIFO_Within_Priorities
          else Domains.Round_Robin_Within_Priorities));
      if Attempt.Status /= Domains.Created then
         return;
      end if;
      Selected := Domain_Number (Attempt.Domain);
      Domain_Used (Selected) := True;
      Domain_Policies (Selected) := Policy;
      if Policy = Preemption.Round_Robin_Within_Priorities then
         Quantum := Preemption.Quantum_Ticks (Slice, Rate);
      end if;
      for Core in Core_Number loop
         Core_Domains (Core) := Domain_Number
           (Attempt.State.Owners (Domains.Core_Id (Core)).Domain);
         if Cores (Core) then
            Core_Policies (Core) := Policy;
            Core_Slices (Core) := Slice;
            Core_Quanta (Core) := Quantum;
         end if;
      end loop;
      Domain := Selected;
      Created := True;
   end Try_Create_Domain_Locked;

   function Domain_Is_Used_Locked (Domain : Domain_Number) return Boolean is
     (Domain_Used (Domain));

   function Domain_Policy_Locked
     (Domain : Domain_Number) return Dispatching_Policy
   is
   begin
      if not Domain_Used (Domain) or else not Policy_Configured then
         Stop;
      end if;
      return Domain_Policies (Domain);
   end Domain_Policy_Locked;

   function Domain_Cores_Locked (Domain : Domain_Number) return Core_Set is
      Result : Core_Set := [others => False];
   begin
      if not Domain_Used (Domain) then
         Stop;
      end if;
      for Core in Core_Number loop
         Result (Core) :=
           Natural (Core) < Configured and then Core_Domains (Core) = Domain;
      end loop;
      return Result;
   end Domain_Cores_Locked;

   function Domain_Of_Core_Locked (Core : Core_Number) return Domain_Number is
   begin
      if Natural (Core) >= Configured then
         Stop;
      end if;
      return Core_Domains (Core);
   end Domain_Of_Core_Locked;

   function Domain_Of_Task_Locked
     (Reference : Task_Ref) return Domain_Number
   is
      Slot : constant Task_Slot := Slot_Of (Reference);
   begin
      if not Known_Locked (Reference)
        or else Tasks (Slot).State = Dispatcher.Dormant
      then
         Stop;
      end if;
      return Tasks (Slot).Domain;
   end Domain_Of_Task_Locked;
end Domain_Operations;
