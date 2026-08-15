--  SPDX-License-Identifier: MIT OR Apache-2.0

package Flyology_Freestanding.Domain_Model
  with Pure,
       SPARK_Mode => On
is
   Max_Cores   : constant := 4;
   Max_Domains : constant := 4;
   Max_Tasks   : constant := 16;

   subtype CPU_Count is Positive range 1 .. Max_Cores;
   subtype Core_Id is Natural range 0 .. Max_Cores - 1;
   subtype Domain_Id is Natural range 0 .. Max_Domains - 1;
   subtype Task_Id is Natural range 0 .. Max_Tasks - 1;
   type Ada_CPU is range -1 .. Max_Cores;
   Unspecified_CPU     : constant Ada_CPU := -1;
   Not_A_Specific_CPU : constant Ada_CPU := 0;

   type Policy_Kind is (FIFO_Within_Priorities,
                        Round_Robin_Within_Priorities);
   type Core_Set is array (Core_Id) of Boolean;

   type Domain_Record is record
      Used   : Boolean := False;
      Cores  : Core_Set := [others => False];
      Policy : Policy_Kind := FIFO_Within_Priorities;
   end record;
   type Domain_Array is array (Domain_Id) of Domain_Record;

   type Core_Owner is record
      Assigned : Boolean := False;
      Domain   : Domain_Id := Domain_Id'First;
   end record;
   type Core_Owner_Array is array (Core_Id) of Core_Owner;

   type Task_Record is record
      Present      : Boolean := False;
      Domain       : Domain_Id := Domain_Id'First;
      Core         : Core_Id := Core_Id'First;
      Requested_CPU : Ada_CPU := 0;
   end record;
   type Task_Array is array (Task_Id) of Task_Record;

   type Domain_State is record
      CPUs         : CPU_Count := CPU_Count'First;
      Domain_Count : Positive range 1 .. Max_Domains := 1;
      Domains      : Domain_Array := [others => (others => <>)];
      Owners       : Core_Owner_Array := [others => (others => <>)];
      Tasks        : Task_Array := [others => (others => <>)];
   end record;

   function Has_Initial_Shape
     (State : Domain_State;
      CPUs  : CPU_Count) return Boolean
   is
     (State.CPUs = CPUs
      and then State.Domain_Count = 1
      and then
        (for all Domain in Domain_Id =>
           State.Domains (Domain).Used = (Domain = 0)
           and then
             State.Domains (Domain).Policy = FIFO_Within_Priorities
           and then
             (for all Core in Core_Id =>
                State.Domains (Domain).Cores (Core) =
                  (Domain = 0 and then Core < CPUs)))
      and then
        (for all Core in Core_Id =>
           State.Owners (Core) =
             (Assigned => Core < CPUs, Domain => 0))
      and then
        (for all Slot in Task_Id =>
           State.Tasks (Slot) =
             (if Slot = 0
              then
                (Present       => True,
                 Domain        => 0,
                 Core          => 0,
                 Requested_CPU => 1)
              else
                (Present       => False,
                 Domain        => 0,
                 Core          => 0,
                 Requested_CPU => 0))));

   function Domain_Table_Valid (State : Domain_State) return Boolean
   is
     (State.Domains (0).Used
      and then State.Domain_Count <= State.CPUs
      and then
        (for all Domain in Domain_Id =>
           State.Domains (Domain).Used = (Domain < State.Domain_Count)
           and then
             (if State.Domains (Domain).Used
              then
                (for some Core in Core_Id =>
                   State.Domains (Domain).Cores (Core)))));

   function Ownership_Valid (State : Domain_State) return Boolean
   is
     ((for all Core in Core_Id =>
         State.Owners (Core).Assigned = (Core < State.CPUs)
         and then
           (if State.Owners (Core).Assigned
            then State.Domains (State.Owners (Core).Domain).Used)
         and then
           (for all Domain in Domain_Id =>
              State.Domains (Domain).Cores (Core) =
                (Core < State.CPUs
                 and then State.Owners (Core).Assigned
                 and then State.Owners (Core).Domain = Domain))));

   function Task_Table_Valid (State : Domain_State) return Boolean
   is
     ((for all Slot in Task_Id =>
         (if State.Tasks (Slot).Present
          then State.Domains (State.Tasks (Slot).Domain).Used
            and then State.Owners (State.Tasks (Slot).Core).Assigned
            and then State.Owners (State.Tasks (Slot).Core).Domain =
              State.Tasks (Slot).Domain
            and then
              (State.Tasks (Slot).Requested_CPU in
                 Unspecified_CPU | Not_A_Specific_CPU
               or else Ada_CPU (State.Tasks (Slot).Core + 1) =
                 State.Tasks (Slot).Requested_CPU)
          else State.Tasks (Slot) =
            (Present       => False,
             Domain        => 0,
             Core          => 0,
             Requested_CPU => Not_A_Specific_CPU))));

   function Environment_Valid (State : Domain_State) return Boolean
   is
     (State.Tasks (0).Present
      and then State.Tasks (0).Domain = 0
      and then State.Tasks (0).Core = 0);

   function Valid (State : Domain_State) return Boolean
   is
     (Domain_Table_Valid (State)
      and then Ownership_Valid (State)
      and then Task_Table_Valid (State)
      and then Environment_Valid (State))
   with Post =>
     (if Has_Initial_Shape (State, State.CPUs) then Valid'Result);

   function Initial (CPUs : CPU_Count) return Domain_State
   with Post => Has_Initial_Shape (Initial'Result, CPUs)
          and then Valid (Initial'Result)
          and then Initial'Result.CPUs = CPUs
          and then Initial'Result.Domain_Count = 1
          and then Initial'Result.Tasks (0).Present
          and then Initial'Result.Tasks (0).Domain = 0
          and then Initial'Result.Tasks (0).Core = 0;

   function Can_Create
     (Before : Domain_State;
      Cores  : Core_Set) return Boolean
   is
     (Before.Domain_Count < Max_Domains
      and then (for some Core in Core_Id => Cores (Core))
      and then
        (for some Core in Core_Id =>
           Core < Before.CPUs
           and then Before.Owners (Core).Assigned
           and then Before.Owners (Core).Domain = 0
           and then not Cores (Core))
      and then
        (for all Core in Core_Id =>
           (if Cores (Core)
            then Core < Before.CPUs
              and then Before.Owners (Core).Assigned
              and then Before.Owners (Core).Domain = 0
              and then
                (for all Slot in Task_Id =>
                   not Before.Tasks (Slot).Present
                   or else Before.Tasks (Slot).Core /= Core))));

   function Is_Exact_Creation
     (Before     : Domain_State;
      After      : Domain_State;
      Cores      : Core_Set;
      Policy     : Policy_Kind;
      New_Domain : Domain_Id) return Boolean
   is
     (Before.Domain_Count < Max_Domains
      and then New_Domain = Before.Domain_Count
      and then After.CPUs = Before.CPUs
      and then After.Domain_Count = Before.Domain_Count + 1
      and then After.Tasks = Before.Tasks
      and then After.Domains (New_Domain) =
        (Used => True, Cores => Cores, Policy => Policy)
      and then After.Domains (0).Used = Before.Domains (0).Used
      and then After.Domains (0).Policy = Before.Domains (0).Policy
      and then
        (for all Core in Core_Id =>
           After.Domains (0).Cores (Core) =
             (Before.Domains (0).Cores (Core) and then not Cores (Core))
           and then
             After.Owners (Core) =
               (if Cores (Core)
                then
                  (Assigned => Before.Owners (Core).Assigned,
                   Domain   => New_Domain)
                else Before.Owners (Core)))
      and then
        (for all Domain in Domain_Id =>
           (if Domain /= 0 and then Domain /= New_Domain
            then After.Domains (Domain) = Before.Domains (Domain))));

   type Create_Status is
     (Created, Empty_Set, Inactive_Core, Core_Not_In_System,
      Core_Has_Task, Would_Empty_System, Domain_Capacity);
   type Create_Result is record
      State  : Domain_State;
      Status : Create_Status := Domain_Capacity;
      Domain : Domain_Id := Domain_Id'First;
   end record;

   function Try_Create
     (Before : Domain_State;
      Cores  : Core_Set;
      Policy : Policy_Kind) return Create_Result
   with Pre  => Valid (Before),
        Post => Valid (Try_Create'Result.State)
          and then
            (Try_Create'Result.Status = Created) =
              Can_Create (Before, Cores)
          and then
            (if Try_Create'Result.Status = Created
             then Try_Create'Result.State.Domain_Count =
                    Before.Domain_Count + 1
               and then Try_Create'Result.Domain = Before.Domain_Count
               and then Is_Exact_Creation
                 (Before,
                  Try_Create'Result.State,
                  Cores,
                  Policy,
                  Try_Create'Result.Domain)
             else Try_Create'Result.State = Before);

   function Can_Admit
     (Before        : Domain_State;
      Slot          : Task_Id;
      Parent_Domain : Domain_Id;
      Explicit      : Boolean;
      Domain        : Domain_Id;
      Requested_CPU : Ada_CPU;
      Chosen_Core   : Core_Id) return Boolean
   is
     (not Before.Tasks (Slot).Present
      and then Before.Domains (Parent_Domain).Used
      and then Before.Domains
        ((if Explicit then Domain else Parent_Domain)).Used
      and then Chosen_Core < Before.CPUs
      and then Before.Owners (Chosen_Core).Assigned
      and then Before.Owners (Chosen_Core).Domain =
        (if Explicit then Domain else Parent_Domain)
      and then
        (Requested_CPU in Unspecified_CPU | Not_A_Specific_CPU
         or else Requested_CPU = Ada_CPU (Chosen_Core + 1)));

   type Placement_Result is record
      Accepted    : Boolean := False;
      Core        : Core_Id := Core_Id'First;
      Next_Cursor : Core_Id := Core_Id'First;
   end record;

   function Can_Place
     (Before        : Domain_State;
      Domain        : Domain_Id;
      Requested_CPU : Ada_CPU) return Boolean
   is
     (Before.Domains (Domain).Used
      and then
        (Requested_CPU in Unspecified_CPU | Not_A_Specific_CPU
         or else
           (Requested_CPU > 0
            and then Core_Id (Requested_CPU - 1) < Before.CPUs
            and then Before.Owners (Core_Id (Requested_CPU - 1)).Assigned
            and then Before.Owners (Core_Id (Requested_CPU - 1)).Domain =
              Domain)));

   function Place
     (Before        : Domain_State;
      Domain        : Domain_Id;
      Requested_CPU : Ada_CPU;
      Cursor        : Core_Id) return Placement_Result
   with Post =>
     (if Valid (Before)
      then Place'Result.Accepted =
             Can_Place (Before, Domain, Requested_CPU)
        and then
          (if Place'Result.Accepted
           then Before.Owners (Place'Result.Core).Assigned
             and then Before.Owners (Place'Result.Core).Domain = Domain
             and then
               (if Requested_CPU in
                  Unspecified_CPU | Not_A_Specific_CPU
                then True
                else Ada_CPU (Place'Result.Core + 1) = Requested_CPU)
           else Place'Result.Core = Cursor
             and then Place'Result.Next_Cursor = Cursor));

   type Admit_Status is
     (Admitted, Task_Already_Present, Unknown_Parent, Unknown_Domain,
      Core_Outside_Domain, Specific_CPU_Mismatch);
   type Admit_Result is record
      State  : Domain_State;
      Status : Admit_Status := Unknown_Domain;
   end record;

   function Try_Admit
     (Before        : Domain_State;
      Slot          : Task_Id;
      Parent_Domain : Domain_Id;
      Explicit      : Boolean;
      Domain        : Domain_Id;
      Requested_CPU : Ada_CPU;
      Chosen_Core   : Core_Id) return Admit_Result
   with Pre  => Valid (Before),
        Post => Valid (Try_Admit'Result.State)
          and then
            (Try_Admit'Result.Status = Admitted) =
              Can_Admit
                (Before, Slot, Parent_Domain, Explicit, Domain,
                 Requested_CPU, Chosen_Core)
          and then
            (if Try_Admit'Result.Status = Admitted
             then Try_Admit'Result.State.Tasks (Slot).Present
               and then Try_Admit'Result.State.Tasks (Slot).Domain =
                 (if Explicit then Domain else Parent_Domain)
               and then Try_Admit'Result.State.Tasks (Slot).Core = Chosen_Core
             else Try_Admit'Result.State = Before);

private
   function Create_Valid_State
     (Before : Domain_State;
      Cores  : Core_Set;
      Policy : Policy_Kind) return Domain_State
   with Pre  => Valid (Before) and then Can_Create (Before, Cores),
        Post => Is_Exact_Creation
            (Before,
             Create_Valid_State'Result,
             Cores,
             Policy,
             Domain_Id (Before.Domain_Count))
          and then Valid (Create_Valid_State'Result);
end Flyology_Freestanding.Domain_Model;
