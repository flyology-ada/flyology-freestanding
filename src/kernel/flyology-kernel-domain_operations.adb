--  SPDX-License-Identifier: MIT OR Apache-2.0

separate (Flyology.Kernel)
package body Domain_Operations is
   procedure Configure_Dispatching
     (Policy : Dispatching_Policy;
      Slice  : Binder_Time_Slice)
   is
      Rate : constant Frequency := Clock_Frequency;
   begin
      if Policy_Configured
        or else not Preemption.Configuration_Is_Valid (Policy, Slice, Rate)
      then
         Stop;
      end if;
      Domain_Policies (System_Domain) := Policy;
      if Policy = Preemption.Round_Robin_Within_Priorities then
         Domain_Quanta (System_Domain) :=
           Preemption.Quantum_Ticks (Slice, Rate);
      else
         Domain_Quanta (System_Domain) := 0;
      end if;
      if Current_Tasks (0) /= No_Task then
         declare
            Slot : constant Task_Slot := Slot_Of (Current_Tasks (0));
            Now  : constant Preemption.Clock.Tick :=
              Preemption.Clock.Tick (Read_Clock);
         begin
            if Policy = Preemption.Round_Robin_Within_Priorities then
               Tasks (Slot).Budget :=
                 Preemption.Start_Budget
                   (Policy, Now, Domain_Quanta (System_Domain));
            else
               Tasks (Slot).Budget := Preemption.Empty_Budget;
            end if;
         end;
      end if;
      Policy_Configured := True;
   end Configure_Dispatching;

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
      Domain_Quanta (Selected) :=
        (if Policy = Preemption.Round_Robin_Within_Priorities
         then Preemption.Quantum_Ticks (Slice, Rate)
         else 0);
      for Core in Core_Number loop
         Core_Domains (Core) := Domain_Number
           (Attempt.State.Owners (Domains.Core_Id (Core)).Domain);
      end loop;
      Domain := Selected;
      Created := True;
   end Try_Create_Domain_Locked;

   function Domain_Is_Used_Locked (Domain : Domain_Number) return Boolean is
     (Domain_Used (Domain));

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
