--  SPDX-License-Identifier: MIT OR Apache-2.0

with Ada.Finalization;
with Flyology_Freestanding.Exceptional_Completion_Model;
with Flyology_Freestanding.Task_Primitives;
with Flyology_Freestanding.Wait_Queue_Model;

package System.Tasking.Protected_Objects.Entries is
   pragma Elaborate_Body;

   package Wait_Queues renames Flyology_Freestanding.Wait_Queue_Model;
   Max_Queued_Calls : constant := Wait_Queues.Capacity;

   type Barrier_Function is access function
     (Object : System.Address;
      Index  : Protected_Entry_Index) return Boolean;

   type Action_Procedure is access procedure
     (Object     : System.Address;
      Parameters : System.Address;
      Index      : Protected_Entry_Index);

   type Protected_Entry_Body is record
      Barrier : Barrier_Function;
      Action  : Action_Procedure;
   end record;

   type Protected_Entry_Body_Array is
     array (Protected_Entry_Index range <>) of Protected_Entry_Body;
   type Protected_Entry_Body_Array_Access is
     access constant Protected_Entry_Body_Array;

   type Queue_Limits_Access is access constant Integer;

   type Body_Index_Function is access function
     (Object : System.Address;
      Index  : Protected_Entry_Index) return Protected_Entry_Index;

   subtype Wait_Token is Flyology_Freestanding.Task_Primitives.Wait_Token;

   package Completions renames
     Flyology_Freestanding.Exceptional_Completion_Model;
   subtype Pending_Phase is Completions.Completion_Phase;
   Free : constant Pending_Phase := Completions.Free;
   Queued : constant Pending_Phase := Completions.Queued;
   Completed_Normal : constant Pending_Phase := Completions.Completed_Normal;
   Completed_Exceptional : constant Pending_Phase :=
     Completions.Completed_Exceptional;

   type Pending_Call is record
      Phase       : Pending_Phase := Free;
      Entry_Index : Protected_Entry_Index := 0;
      Parameters  : System.Address := System.Null_Address;
      Token       : Wait_Token;
      Timed       : Boolean := False;
      Exception_Identity : System.Address := System.Null_Address;
   end record;

   type Pending_Call_Array is
     array (Positive range 1 .. Max_Queued_Calls) of Pending_Call;

   type Core_Wake_Array is array (System.Address range 0 .. 3) of Boolean;

   type Protection_Entries
     (Entry_Count : Protected_Entry_Index) is
     new Ada.Finalization.Limited_Controlled with record
      Initialized      : Boolean := False;
      Ceiling          : Integer := System.Tasking.Unspecified_Priority;
      Enclosing_Object : System.Address := System.Null_Address;
      Entry_Bodies     : Protected_Entry_Body_Array_Access := null;
      Find_Body_Index  : Body_Index_Function := null;
      Queue            : Wait_Queues.Wait_Queue;
      Pending          : Pending_Call_Array;
      Servicing        : Boolean := False;
      Executing        : Natural range 0 .. Max_Queued_Calls := 0;
      Wake_Cores       : Core_Wake_Array := [others => False];
   end record;
   type Protection_Entries_Access is access all Protection_Entries;

   procedure Initialize_Protection_Entries
     (Object           : Protection_Entries_Access;
      Ceiling          : Integer;
      Enclosing_Object : System.Address;
      Queue_Limits     : Queue_Limits_Access;
      Entry_Bodies     : Protected_Entry_Body_Array_Access;
      Find_Body_Index  : Body_Index_Function);

   procedure Lock_Entries (Object : Protection_Entries_Access);
   procedure Unlock_Entries (Object : Protection_Entries_Access);

private
   overriding procedure Finalize (Object : in out Protection_Entries);
end System.Tasking.Protected_Objects.Entries;
