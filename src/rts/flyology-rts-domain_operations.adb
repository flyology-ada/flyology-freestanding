--  SPDX-License-Identifier: MIT OR Apache-2.0

separate (Flyology.RTS)
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
           (if Domain = Core.System_Domain
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
      if not Flyology.Domain_Configuration.Enabled or else Domains_Frozen
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
end Domain_Operations;
