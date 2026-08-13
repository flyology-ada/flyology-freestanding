--  SPDX-License-Identifier: MIT OR Apache-2.0

package body Flyology.Scheduler_Contract
  with SPARK_Mode => On
is
   function Enqueue
     (Queue : Ready_Queue;
      Candidate : Task_Ref) return Ready_Queue
   is
      Result : Ready_Queue := Queue;
   begin
      Result.Length := Queue.Length + 1;
      Result.Storage (Queue_Index (Result.Length)) := Candidate;
      return Result;
   end Enqueue;

   function Select_Next (Queue : Ready_Queue) return Selection
   is
      Result : Selection := (Selected => No_Task, Remainder => Queue);
   begin
      if Queue.Length = 0 then
         return Result;
      end if;

      Result.Selected := Queue.Storage (Queue_Index'First);
      if Queue.Length > 1 then
         for Index in Queue_Index range
           Queue_Index'First .. Queue_Index (Queue.Length - 1)
         loop
            Result.Remainder.Storage (Index) :=
              Queue.Storage (Queue_Index'Succ (Index));
            pragma Loop_Invariant
              (Result.Remainder.Storage (Queue_Index'First .. Index)
                 = Queue.Storage
                   (Queue_Index'Succ (Queue_Index'First) ..
                    Queue_Index'Succ (Index)));
         end loop;
      end if;
      Result.Remainder.Storage (Queue_Index (Queue.Length)) := No_Task;
      Result.Remainder.Length := Queue.Length - 1;
      return Result;
   end Select_Next;
end Flyology.Scheduler_Contract;
