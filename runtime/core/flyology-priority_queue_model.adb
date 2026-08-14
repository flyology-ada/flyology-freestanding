--  SPDX-License-Identifier: MIT OR Apache-2.0

package body Flyology.Priority_Queue_Model
  with SPARK_Mode => On
is
   function Best_Index (Queue : Ready_Queue) return Queue_Index
   with Pre => Valid (Queue) and then Queue.Length > 0,
        Post => Best_Index'Result <= Queue.Length
          and then
            (for all Index in Queue_Index =>
               (if Index <= Queue.Length then
                  not Precedes
                    (Queue.Storage (Index),
                     Queue.Storage (Best_Index'Result))));

   function Best_Index (Queue : Ready_Queue) return Queue_Index is
      Best : Queue_Index := Queue_Index'First;
   begin
      for Index in Queue_Index loop
         exit when Index > Queue.Length;
         if Precedes (Queue.Storage (Index), Queue.Storage (Best)) then
            Best := Index;
         end if;
         pragma Loop_Invariant (Best <= Index);
         pragma Loop_Invariant (Best <= Queue.Length);
         pragma Loop_Invariant
           (for all Seen in Queue_Index =>
              (if Seen <= Index then
                 not Precedes
                   (Queue.Storage (Seen), Queue.Storage (Best))));
      end loop;
      return Best;
   end Best_Index;

   procedure Remove_At
     (Queue : in out Ready_Queue;
      Index : Queue_Index)
   with Pre => Valid (Queue) and then Index <= Queue.Length,
        Post => Valid (Queue)
          and then Queue.Length = Queue'Old.Length - 1
          and then not Contains
            (Queue, Queue'Old.Storage (Index).Reference)
          and then
            (for all Cursor in Queue_Index =>
               (if Cursor <= Queue.Length then
                  (for some Previous in Queue_Index =>
                     Previous <= Queue'Old.Length
                       and then Queue.Storage (Cursor) =
                         Queue'Old.Storage (Previous))));

   procedure Remove_At
     (Queue : in out Ready_Queue;
      Index : Queue_Index)
   is
      Previous : constant Ready_Queue := Queue;
   begin
      if Index < Previous.Length then
         for Cursor in Queue_Index range
           Index .. Queue_Index (Previous.Length - 1)
         loop
            Queue.Storage (Cursor) :=
              Previous.Storage (Queue_Index'Succ (Cursor));
            pragma Loop_Invariant
              (Queue.Storage (Index .. Cursor) =
                 Previous.Storage
                   (Queue_Index'Succ (Index) .. Queue_Index'Succ (Cursor)));
         end loop;
      end if;
      Queue.Storage (Queue_Index (Previous.Length)) := Empty_Entry;
      Queue.Length := Previous.Length - 1;
   end Remove_At;

   procedure Append_Tail
     (Queue : in out Ready_Queue;
      Item  : Ready_Entry)
   with Pre => Valid (Queue)
          and then Queue.Length < Capacity
          and then Is_Valid_Task (Item.Reference)
          and then Item.Sequence /= No_Sequence
          and then not Contains (Queue, Item.Reference)
          and then not Contains_Sequence (Queue, Item.Sequence),
        Post => Valid (Queue)
          and then Queue.Length = Queue'Old.Length + 1
          and then Queue.Storage (Queue_Index (Queue.Length)) = Item;

   procedure Append_Tail
     (Queue : in out Ready_Queue;
      Item  : Ready_Entry)
   is
   begin
      Queue.Length := Queue.Length + 1;
      Queue.Storage (Queue_Index (Queue.Length)) := Item;
   end Append_Tail;

   function Enqueue
     (Before : Ready_Queue;
      Item   : Ready_Entry) return Enqueue_Result
   is
      Result : Enqueue_Result := (Queue => Before, Status => Invalid);
   begin
      if not Is_Valid_Task (Item.Reference)
        or else Item.Sequence = No_Sequence
      then
         return Result;
      elsif Contains (Before, Item.Reference)
        or else Contains_Sequence (Before, Item.Sequence)
      then
         Result.Status := Duplicate;
         return Result;
      elsif Before.Length = Capacity then
         Result.Status := Full;
         return Result;
      end if;
      Result.Queue.Length := Before.Length + 1;
      Result.Queue.Storage (Queue_Index (Result.Queue.Length)) := Item;
      Result.Status := Enqueued;
      return Result;
   end Enqueue;

   function Requeue_Priority
     (Before       : Ready_Queue;
      Reference    : Task_Ref;
      New_Priority : Dispatcher_Model.Priority;
      New_Sequence : Arrival_Sequence) return Requeue_Result
   is
      Result : Requeue_Result := (Queue => Before, Status => Missing);
   begin
      for Index in Queue_Index loop
         exit when Index > Before.Length;
         if Before.Storage (Index).Reference = Reference then
            Remove_At (Result.Queue, Index);
            pragma Assert (Is_Valid_Task (Reference));
            pragma Assert (not Contains (Result.Queue, Reference));
            pragma Assert
              (not Contains_Sequence (Result.Queue, New_Sequence));
            Append_Tail
              (Result.Queue,
              (Reference => Reference,
               Priority  => New_Priority,
               Sequence  => New_Sequence,
               Position  => At_Tail));
            Result.Status := Requeued;
            return Result;
         end if;
      end loop;
      return Result;
   end Requeue_Priority;

   function Select_Next (Before : Ready_Queue) return Selection is
      Result : Selection := (Remainder => Before, others => <>);
      Index  : Queue_Index;
   begin
      if Before.Length = 0 then
         return Result;
      end if;
      Index := Best_Index (Before);
      Result.Item := Before.Storage (Index);
      Result.Found := True;
      Remove_At (Result.Remainder, Index);
      return Result;
   end Select_Next;
end Flyology.Priority_Queue_Model;
