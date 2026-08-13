--  SPDX-License-Identifier: MIT OR Apache-2.0

package body Flyology.Wait_Queue_Model
  with SPARK_Mode => On
is
   procedure Remove_At
     (Queue : in out Wait_Queue;
      Index : Queue_Index)
   with Pre => Valid (Queue) and then Index <= Queue.Length,
        Post => Valid (Queue)
          and then Queue.Length = Queue'Old.Length - 1
          and then not Contains (Queue, Queue'Old.Storage (Index));

   procedure Remove_At
     (Queue : in out Wait_Queue;
      Index : Queue_Index)
   is
      Previous : constant Wait_Queue := Queue;
   begin
      if Index < Previous.Length then
         Queue.Storage
           (Index .. Queue_Index (Previous.Length - 1)) :=
             Previous.Storage
               (Queue_Index'Succ (Index) .. Queue_Index (Previous.Length));
      end if;
      Queue.Storage (Queue_Index (Previous.Length)) := Empty_Token;
      Queue.Length := Previous.Length - 1;
   end Remove_At;

   function Enqueue
     (Before : Wait_Queue;
      Token  : Primitives.Wait_Token) return Enqueue_Result
   is
      Result : Enqueue_Result := (Queue => Before, Status => Invalid);
   begin
      if Token.Task_Reference = Dispatcher.No_Task
        or else Token.Generation = Dispatcher.Generation'First
      then
         return Result;
      elsif Contains_Task (Before, Token.Task_Reference) then
         Result.Status := Duplicate_Task;
         return Result;
      elsif Before.Length = Capacity then
         Result.Status := Full;
         return Result;
      end if;
      Result.Queue.Length := Before.Length + 1;
      Result.Queue.Storage (Queue_Index (Result.Queue.Length)) := Token;
      Result.Status := Enqueued;
      return Result;
   end Enqueue;

   function Remove_Exact
     (Before : Wait_Queue;
      Token  : Primitives.Wait_Token) return Remove_Result
   is
      Result : Remove_Result := (Queue => Before, Status => Not_Found);
   begin
      for Index in Queue_Index loop
         exit when Index > Before.Length;
         if Before.Storage (Index) = Token then
            Remove_At (Result.Queue, Index);
            Result.Status := Removed;
            return Result;
         elsif Before.Storage (Index).Task_Reference = Token.Task_Reference then
            Result.Status := Stale;
            return Result;
         end if;
      end loop;
      return Result;
   end Remove_Exact;

   function Take_Head (Before : Wait_Queue) return Head_Result is
      Result : Head_Result := (Queue => Before, others => <>);
   begin
      if Before.Length = 0 then
         return Result;
      end if;
      Result.Found := True;
      Result.Token := Before.Storage (Queue_Index'First);
      Remove_At (Result.Queue, Queue_Index'First);
      return Result;
   end Take_Head;
end Flyology.Wait_Queue_Model;
