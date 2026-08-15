--  SPDX-License-Identifier: MIT OR Apache-2.0

separate (Flyology_Freestanding.RTS)
package body Domain_Operations is
   procedure Register_Domain_Alias_Locked
     (Domain         : Core.Domain_Number;
      Object_Address : System.Address)
   is
   begin
      if Object_Address = System.Null_Address
        or else not Core.Domain_Is_Used_Locked (Domain)
      then
         Stop;
      end if;
      for Alias of Domain_Aliases loop
         if Alias.Used and then Alias.Address = Object_Address then
            if Alias.Domain /= Domain then
               Stop;
            end if;
            return;
         end if;
      end loop;
      for Alias of Domain_Aliases loop
         if not Alias.Used then
            Alias :=
              (Used => True, Address => Object_Address, Domain => Domain);
            return;
         end if;
      end loop;
      Stop;
   end Register_Domain_Alias_Locked;

   function Domain_For_Address_Locked
     (Object_Address : System.Address;
      Found          : out Boolean) return Core.Domain_Number
   is
   begin
      Found := False;
      if Object_Address = System.Null_Address then
         return Core.System_Domain;
      end if;
      for Alias of Domain_Aliases loop
         if Alias.Used and then Alias.Address = Object_Address then
            if not Core.Domain_Is_Used_Locked (Alias.Domain) then
               Stop;
            end if;
            Found := True;
            return Alias.Domain;
         end if;
      end loop;
      return Core.System_Domain;
   end Domain_For_Address_Locked;

   function Domain_Snapshot_Locked return Domains.Domain_State is
      Result : Domains.Domain_State :=
        Domains.Initial (Domains.CPU_Count (Core.CPU_Count));
      Count  : Positive range 1 .. Core.Max_Domains := 1;
      Cores  : Core.Core_Set;
   begin
      for Domain in Core.Domain_Number range 1 .. Core.Domain_Number'Last loop
         if Core.Domain_Is_Used_Locked (Domain) then
            Count := Count + 1;
         end if;
      end loop;
      Result.Domain_Count := Count;
      for Domain in Core.Domain_Number loop
         Result.Domains (Domains.Domain_Id (Domain)).Used :=
           Core.Domain_Is_Used_Locked (Domain);
         Result.Domains (Domains.Domain_Id (Domain)).Policy :=
           (if not Core.Domain_Is_Used_Locked (Domain)
            or else Core.Domain_Policy_Locked (Domain) =
              Core.FIFO_Within_Priorities
            then Domains.FIFO_Within_Priorities
            else Domains.Round_Robin_Within_Priorities);
         if Core.Domain_Is_Used_Locked (Domain) then
            Cores := Core.Domain_Cores_Locked (Domain);
            for Dense in Core_Number loop
               Result.Domains (Domains.Domain_Id (Domain)).Cores
                 (Domains.Core_Id (Dense)) := Cores (Dense);
            end loop;
         end if;
      end loop;
      for Dense in Core_Number loop
         Result.Owners (Domains.Core_Id (Dense)) :=
           (Assigned => Natural (Dense) < Core.CPU_Count,
            Domain   =>
              (if Natural (Dense) < Core.CPU_Count
               then Domains.Domain_Id (Core.Domain_Of_Core_Locked (Dense))
               else 0));
      end loop;
      if not Domains.Valid (Result) then
         Stop;
      end if;
      return Result;
   end Domain_Snapshot_Locked;

   procedure Register_Domain_Alias
     (Identifier     : Natural;
      Object_Address : System.Address)
   is
   begin
      if Identifier > Natural (Core.Domain_Number'Last) then
         Stop;
      end if;
      Enter_Kernel;
      Register_Domain_Alias_Locked
        (Core.Domain_Number (Identifier), Object_Address);
      Leave_Kernel;
   end Register_Domain_Alias;

   procedure Create_Domain
     (Set            : Domain_CPU_Set;
      Identifier     : out Natural;
      Created        : out Boolean)
   is
      Cores  : Core.Core_Set := [others => False];
      Domain : Core.Domain_Number;
   begin
      Identifier := 0;
      Created := False;
      if not Flyology_Freestanding.Domain_Configuration.Enabled or else Domains_Frozen
      then
         Stop;
      end if;
      for CPU in Domain_CPU loop
         if Set (CPU) then
            if CPU > Core.CPU_Count then
               Stop;
            end if;
            Cores (Core.Core_Number (CPU - 1)) := True;
         end if;
      end loop;
      Enter_Kernel;
      Core.Try_Create_Domain_Locked
        (Cores, Core.Round_Robin_Within_Priorities, 10_000, Domain, Created);
      Leave_Kernel;
      if Created then
         Identifier := Natural (Domain);
      end if;
   end Create_Domain;

   procedure Freeze_Domains is
   begin
      Enter_Kernel;
      if Domains_Frozen then
         Leave_Kernel;
         Stop;
      end if;
      Domains_Frozen := True;
      Leave_Kernel;
   end Freeze_Domains;

   function Domain_CPUs (Identifier : Natural) return Domain_CPU_Set is
      Result : Domain_CPU_Set := [others => False];
      Cores  : Core.Core_Set;
   begin
      if Identifier > Natural (Core.Domain_Number'Last) then
         Stop;
      end if;
      Enter_Kernel;
      Cores := Core.Domain_Cores_Locked (Core.Domain_Number (Identifier));
      for CPU in Domain_CPU loop
         Result (CPU) :=
           CPU <= Core.CPU_Count
           and then Cores (Core.Core_Number (CPU - 1));
      end loop;
      Leave_Kernel;
      return Result;
   end Domain_CPUs;

   function Task_Domain (Item : Task_Id) return Natural is
      Slot      : Task_Slot;
      Reference : Dispatcher.Task_Ref;
      Result    : Core.Domain_Number;
   begin
      Enter_Kernel;
      Slot := Record_Of (Item);
      Reference := To_Reference (Tasks (Slot).Identity);
      Result := Core.Domain_Of_Task_Locked (Reference);
      Leave_Kernel;
      return Natural (Result);
   end Task_Domain;

   function Assigned_CPU (Item : Task_Id) return Natural is
      Slot      : Task_Slot;
      Reference : Dispatcher.Task_Ref;
      Result    : Core_Number;
   begin
      Enter_Kernel;
      Slot := Record_Of (Item);
      Reference := To_Reference (Tasks (Slot).Identity);
      if Core.State_Locked (Reference) = Dispatcher.Dormant then
         Leave_Kernel;
         Stop;
      end if;
      Result := Core.Assigned_Core_Locked (Reference);
      Leave_Kernel;
      return Natural (Result) + 1;
   end Assigned_CPU;

   function Core_Policy (Policy : Scheduling_Policy) return
     Core.Dispatching_Policy
   is
     (case Policy is
         when FIFO_Within_Priorities => Core.FIFO_Within_Priorities,
         when Round_Robin_Within_Priorities =>
           Core.Round_Robin_Within_Priorities);

   procedure Validate_Quantum
     (Policy  : Scheduling_Policy;
      Quantum : Scheduling_Quantum_Microseconds)
   is
   begin
      if (Policy = FIFO_Within_Priorities and then Quantum /= 0)
        or else
          (Policy = Round_Robin_Within_Priorities and then Quantum = 0)
      then
         Stop;
      end if;
   end Validate_Quantum;

   procedure Kick_Affected (Affected : Core.Core_Set) is
   begin
      for Dense in Core_Number loop
         if Affected (Dense) then
            Kick_Core (System.Address (Dense));
         end if;
      end loop;
   end Kick_Affected;

   procedure Set_Global_Scheduling_Policy
     (Policy  : Scheduling_Policy;
      Quantum : Scheduling_Quantum_Microseconds)
   is
      Affected : Core.Core_Set;
   begin
      Validate_Quantum (Policy, Quantum);
      Enter_Kernel;
      Core.Change_Global_Policy_Locked
        (Core_Policy (Policy), Core.Binder_Time_Slice (Quantum), Affected);
      Leave_Kernel;
      Kick_Affected (Affected);
   end Set_Global_Scheduling_Policy;

   procedure Set_Domain_Scheduling_Policy
     (Set     : Domain_CPU_Set;
      Policy  : Scheduling_Policy;
      Quantum : Scheduling_Quantum_Microseconds)
   is
      Cores    : Core.Core_Set := [others => False];
      Affected : Core.Core_Set;
   begin
      Validate_Quantum (Policy, Quantum);
      for CPU in Domain_CPU loop
         if Set (CPU) then
            if CPU > Core.CPU_Count then
               Stop;
            end if;
            Cores (Core.Core_Number (CPU - 1)) := True;
         end if;
      end loop;
      Enter_Kernel;
      Core.Change_Domain_Policy_Locked
        (Cores, Core_Policy (Policy), Core.Binder_Time_Slice (Quantum),
         Affected);
      Leave_Kernel;
      Kick_Affected (Affected);
   end Set_Domain_Scheduling_Policy;

   procedure Set_CPU_Scheduling_Policy
     (CPU     : Domain_CPU;
      Policy  : Scheduling_Policy;
      Quantum : Scheduling_Quantum_Microseconds)
   is
      Affected : Core.Core_Set;
   begin
      Validate_Quantum (Policy, Quantum);
      if CPU > Core.CPU_Count then
         Stop;
      end if;
      Enter_Kernel;
      Core.Change_Core_Policy_Locked
        (Core.Core_Number (CPU - 1), Core_Policy (Policy),
         Core.Binder_Time_Slice (Quantum), Affected);
      Leave_Kernel;
      Kick_Affected (Affected);
   end Set_CPU_Scheduling_Policy;

   procedure Get_CPU_Scheduling_Configuration
     (CPU     : Domain_CPU;
      Policy  : out Scheduling_Policy;
      Quantum : out Scheduling_Quantum_Microseconds)
   is
      Core_Policy_Value : Core.Dispatching_Policy;
      Core_Slice_Value  : Core.Binder_Time_Slice;
   begin
      if CPU > Core.CPU_Count then
         Stop;
      end if;
      Enter_Kernel;
      Core_Policy_Value :=
        Core.Policy_Of_Core_Locked (Core.Core_Number (CPU - 1));
      Core_Slice_Value :=
        Core.Slice_Of_Core_Locked (Core.Core_Number (CPU - 1));
      Leave_Kernel;
      Policy :=
        (if Core_Policy_Value = Core.FIFO_Within_Priorities
         then FIFO_Within_Priorities
         else Round_Robin_Within_Priorities);
      Quantum := Scheduling_Quantum_Microseconds (Core_Slice_Value);
   end Get_CPU_Scheduling_Configuration;
end Domain_Operations;
