--  SPDX-License-Identifier: MIT OR Apache-2.0

with Flyology.Clock_Model;
with Flyology.M3_Runtime;
with Flyology.Task_Core;
with Flyology.Wait_Arbitration_Model;
with Flyology.Wait_Queue_Model;

package body System.Tasking.Protected_Objects.Operations is
   package Core renames Flyology.Task_Core;
   package Clock renames Flyology.Clock_Model;
   package Queues renames Flyology.Wait_Queue_Model;
   package Waits renames Flyology.Wait_Arbitration_Model;
   use type Core.Wait_Resolve_Status;
   use type Core.Timer_Cancel_Status;
   use type Entries.Protection_Entries_Access;
   use type Entries.Wait_Token;
   use type Queues.Enqueue_Status;
   use type Queues.Remove_Status;
   use type Waits.Resolution;

   procedure Kick_Core (Core : System.Address)
   with Import, Convention => C, External_Name => "flyology_m3_kick_core";

   procedure Report_Failure
   with Import, Convention => C, External_Name => "flyology_m2_report_failure";

   procedure Stop with No_Return;

   procedure Stop is
   begin
      Report_Failure;
      loop
         null;
      end loop;
   end Stop;

   function Dense_Core return Core.Core_Number is
     (Core.Core_Number (Flyology.M3_Runtime.Current_Core_Number));

   function Body_Index
     (Object : Entries.Protection_Entries_Access;
      Index  : Protected_Entry_Index) return Protected_Entry_Index;

   procedure Kick_Waiters (Object : Entries.Protection_Entries_Access);

   function Body_Index
     (Object : Entries.Protection_Entries_Access;
      Index  : Protected_Entry_Index) return Protected_Entry_Index
   is
      Result : Protected_Entry_Index;
   begin
      Result := Object.Find_Body_Index (Object.Enclosing_Object, Index);
      if Result not in Object.Entry_Bodies'Range then
         Stop;
      end if;
      return Result;
   end Body_Index;

   procedure Kick_Waiters (Object : Entries.Protection_Entries_Access) is
   begin
      for Candidate in Object.Wake_Cores'Range loop
         if Object.Wake_Cores (Candidate) then
            Object.Wake_Cores (Candidate) := False;
            Kick_Core (Candidate);
         end if;
      end loop;
   end Kick_Waiters;

   procedure Complete_Entry_Body
     (Object : Entries.Protection_Entries_Access)
   is
      Status    : Core.Wait_Resolve_Status;
      Wake_Core : Core.Core_Number;
      Slot      : Natural;
      Removal   : Queues.Remove_Result;
      Cancelled : Core.Timer_Cancel_Status;
   begin
      if Object = null or else not Object.Initialized then
         raise Program_Error;
      end if;
      if Object.Executing = 0 then
         Entries.Unlock_Entries (Object);
         return;
      end if;
      Slot := Object.Executing;
      Removal := Queues.Remove_Exact
        (Object.Queue, Object.Pending (Slot).Token);
      if Removal.Status /= Queues.Removed then
         Stop;
      end if;
      Object.Queue := Removal.Queue;
      if Object.Pending (Slot).Timed then
         Core.Cancel_Deadline_Locked
           (Object.Pending (Slot).Token, Cancelled);
         if Cancelled /= Core.Cancelled then
            Stop;
         end if;
      end if;
      Core.Resolve_Exact_Locked
        (Object.Pending (Slot).Token, Waits.Object_Wake, Status, Wake_Core);
      if Status not in Waits.Won_Before_Block | Waits.Made_Ready then
         Stop;
      end if;
      Object.Pending (Slot) := (others => <>);
      Object.Executing := 0;
      Object.Wake_Cores (System.Address (Wake_Core)) := True;
   end Complete_Entry_Body;

   procedure Exceptional_Complete_Entry_Body
     (Object     : Entries.Protection_Entries_Access;
      Occurrence : System.Address)
   is
      pragma Unreferenced (Occurrence);
   begin
      Stop;
   end Exceptional_Complete_Entry_Body;

   procedure Service_Entries (Object : Entries.Protection_Entries_Access) is
      Selected : Natural;
      Mapped   : Protected_Entry_Index;
      Token    : Entries.Wait_Token;
      Slot     : Natural;
      Stale    : Natural;
   begin
      if Object = null or else not Object.Initialized
        or else Object.Servicing or else Object.Executing /= 0
      then
         Stop;
      end if;
      Object.Servicing := True;
      loop
         Selected := 0;
         Stale := 0;
         for Queue_Index in Queues.Queue_Index loop
            exit when Queue_Index > Object.Queue.Length;
            Token := Object.Queue.Storage (Queue_Index);
            Slot := Natural (Token.Task_Reference.Slot) + 1;
            if Slot not in Object.Pending'Range
              or else not Object.Pending (Slot).Present
              or else Object.Pending (Slot).Token /= Token
            then
               Stop;
            end if;
            if not Core.Wait_Is_Pending_Locked (Token) then
               Stale := Slot;
               exit;
            else
               Mapped := Body_Index
                 (Object, Object.Pending (Slot).Entry_Index);
               if Object.Entry_Bodies (Mapped).Barrier
                 (Object.Enclosing_Object, Mapped)
               then
                  Selected := Slot;
                  exit;
               end if;
            end if;
         end loop;
         if Stale /= 0 then
            declare
               Removal : constant Queues.Remove_Result :=
                 Queues.Remove_Exact
                   (Object.Queue, Object.Pending (Stale).Token);
            begin
               if Removal.Status /= Queues.Removed then
                  Stop;
               end if;
               Object.Queue := Removal.Queue;
               Object.Pending (Stale) := (others => <>);
            end;
         end if;
         if Stale = 0 then
            exit when Selected = 0;
            Mapped := Body_Index
              (Object, Object.Pending (Selected).Entry_Index);
            Object.Executing := Selected;
            Object.Entry_Bodies (Mapped).Action
              (Object.Enclosing_Object, Object.Pending (Selected).Parameters,
               Mapped);
            if Object.Executing /= 0 then
               Stop;
            end if;
         end if;
      end loop;
      Object.Servicing := False;
      Entries.Unlock_Entries (Object);
      Kick_Waiters (Object);
   end Service_Entries;

   procedure Protected_Entry_Call
     (Object     : Entries.Protection_Entries_Access;
      Index      : Protected_Entry_Index;
      Parameters : System.Address;
      Mode       : System.Tasking.Call_Modes;
      Block      : in out Communication_Block)
   is
      Mapped    : Protected_Entry_Index;
      Reference : Core.Task_Ref;
      Token     : Core.Wait_Token;
      Outcome   : Waits.Resolution;
      Slot      : Natural;
      Enqueue   : Queues.Enqueue_Result;
   begin
      if Mode not in System.Tasking.Simple_Call |
        System.Tasking.Conditional_Call
      then
         raise Program_Error;
      end if;
      Entries.Lock_Entries (Object);
      Mapped := Body_Index (Object, Index);
      if Object.Entry_Bodies (Mapped).Barrier
        (Object.Enclosing_Object, Mapped)
      then
         Object.Entry_Bodies (Mapped).Action
           (Object.Enclosing_Object, Parameters, Mapped);
         Block.Was_Cancelled := False;
         return;
      elsif Mode = System.Tasking.Conditional_Call then
         Entries.Unlock_Entries (Object);
         Block.Was_Cancelled := True;
         return;
      end if;
      Reference := Core.Current_Locked (Dense_Core);
      Slot := Natural (Reference.Slot) + 1;
      if Slot not in Object.Pending'Range or else Object.Pending (Slot).Present
      then
         Entries.Unlock_Entries (Object);
         raise Program_Error;
      elsif Object.Queue.Length = Queues.Capacity then
         Entries.Unlock_Entries (Object);
         raise Storage_Error;
      elsif Queues.Contains_Task (Object.Queue, Reference) then
         Entries.Unlock_Entries (Object);
         raise Program_Error;
      end if;
      Core.Arm_Wait_Locked (Reference, Waits.Object_Wait, Token);
      Enqueue := Queues.Enqueue (Object.Queue, Token);
      if Enqueue.Status = Queues.Full then
         Stop;
      elsif Enqueue.Status /= Queues.Enqueued then
         Stop;
      end if;
      Object.Queue := Enqueue.Queue;
      Object.Pending (Slot) :=
        (Present => True, Entry_Index => Index, Parameters => Parameters,
         Token => Token, Timed => False);
      Core.Block_Current_And_Release (Dense_Core, Token, Outcome);
      if Outcome = Waits.Abort_Wake then
         raise Program_Error;
      elsif Outcome /= Waits.Object_Wake then
         raise Program_Error;
      end if;
      Block.Was_Cancelled := False;
   end Protected_Entry_Call;

   procedure Timed_Protected_Entry_Call
     (Object     : Entries.Protection_Entries_Access;
      Index      : Protected_Entry_Index;
      Parameters : System.Address;
      Timeout    : Duration;
      Delay_Mode : Integer;
      Accepted   : out Boolean)
   is
      Mapped      : Protected_Entry_Index;
      Reference   : Core.Task_Ref;
      Token       : Core.Wait_Token;
      Outcome     : Waits.Resolution;
      Slot        : Natural;
      Enqueue     : Queues.Enqueue_Result;
      Tick_Count  : Clock.Tick := 0;
      Deadline    : Clock.Tick := 0;
      Rate        : Clock.Frequency;
      Nanoseconds : Long_Long_Integer;
      Removal     : Queues.Remove_Result;
   begin
      Accepted := False;
      if Delay_Mode /= 0 or else Timeout < 0.0 then
         raise Program_Error;
      elsif Timeout > 0.0 then
         if Timeout > Duration (Long_Long_Integer'Last / 1_000_000_000)
         then
            raise Storage_Error;
         end if;
         Nanoseconds := Long_Long_Integer (Timeout * 1_000_000_000) + 1;
         Rate := Clock.Frequency (Core.Clock_Frequency);
         if Nanoseconds <= 0
           or else not Clock.Conversion_Fits
             (Clock.Nanoseconds (Nanoseconds), Rate)
         then
            raise Storage_Error;
         end if;
         Tick_Count := Clock.To_Ticks_Ceiling
           (Clock.Nanoseconds (Nanoseconds), Rate);
         Deadline := Clock.Tick (Core.Read_Clock);
         if not Clock.Deadline_Fits (Deadline, Tick_Count) then
            raise Storage_Error;
         end if;
         Deadline := Clock.Add_Delay (Deadline, Tick_Count);
      end if;

      Entries.Lock_Entries (Object);
      Mapped := Body_Index (Object, Index);
      if Object.Entry_Bodies (Mapped).Barrier
        (Object.Enclosing_Object, Mapped)
      then
         Object.Entry_Bodies (Mapped).Action
           (Object.Enclosing_Object, Parameters, Mapped);
         Accepted := True;
         return;
      elsif Timeout = 0.0 then
         Entries.Unlock_Entries (Object);
         return;
      end if;

      Reference := Core.Current_Locked (Dense_Core);
      Slot := Natural (Reference.Slot) + 1;
      if Slot not in Object.Pending'Range or else Object.Pending (Slot).Present
      then
         Entries.Unlock_Entries (Object);
         raise Program_Error;
      elsif Object.Queue.Length = Queues.Capacity then
         Entries.Unlock_Entries (Object);
         raise Storage_Error;
      elsif Queues.Contains_Task (Object.Queue, Reference) then
         Entries.Unlock_Entries (Object);
         raise Program_Error;
      end if;

      Core.Arm_Wait_Locked (Reference, Waits.Timed_Object_Wait, Token);
      Core.Register_Deadline_Locked (Token, Core.Tick (Deadline));
      Enqueue := Queues.Enqueue (Object.Queue, Token);
      if Enqueue.Status /= Queues.Enqueued then
         Stop;
      end if;
      Object.Queue := Enqueue.Queue;
      Object.Pending (Slot) :=
        (Present => True, Entry_Index => Index, Parameters => Parameters,
         Token => Token, Timed => True);
      Core.Block_Current_And_Release (Dense_Core, Token, Outcome);

      if Outcome = Waits.Object_Wake then
         Accepted := True;
         return;
      elsif Outcome /= Waits.Timer_Expiry then
         Stop;
      end if;

      Entries.Lock_Entries (Object);
      if Object.Pending (Slot).Present
        and then Object.Pending (Slot).Token = Token
      then
         Removal := Queues.Remove_Exact (Object.Queue, Token);
         if Removal.Status /= Queues.Removed then
            Stop;
         end if;
         Object.Queue := Removal.Queue;
         Object.Pending (Slot) := (others => <>);
      end if;
      Entries.Unlock_Entries (Object);
   end Timed_Protected_Entry_Call;

   function Cancelled (Block : Communication_Block) return Boolean is
     (Block.Was_Cancelled);

   function Protected_Count
     (Object : Entries.Protection_Entries;
      Index  : Protected_Entry_Index) return Natural
   is
      Result : Natural := 0;
      Slot   : Natural;
      Token  : Entries.Wait_Token;
   begin
      for Queue_Index in Queues.Queue_Index loop
         exit when Queue_Index > Object.Queue.Length;
         Token := Object.Queue.Storage (Queue_Index);
         Slot := Natural (Token.Task_Reference.Slot) + 1;
         if Slot not in Object.Pending'Range
           or else not Object.Pending (Slot).Present
           or else Object.Pending (Slot).Token /= Token
         then
            Stop;
         elsif Object.Pending (Slot).Entry_Index = Index then
            Result := Result + 1;
         end if;
      end loop;
      return Result;
   end Protected_Count;
end System.Tasking.Protected_Objects.Operations;
