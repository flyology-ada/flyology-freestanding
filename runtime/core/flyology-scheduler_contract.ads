--  SPDX-License-Identifier: MIT OR Apache-2.0

with Flyology.Dispatcher_Model;

package Flyology.Scheduler_Contract
  with Pure,
       SPARK_Mode => On
is
   use Flyology.Dispatcher_Model;

   Queue_Capacity : constant := 64;
   subtype Queue_Index is Positive range 1 .. Queue_Capacity;
   subtype Queue_Length is Natural range 0 .. Queue_Capacity;

   type Queue_Storage is array (Queue_Index) of Task_Ref;

   type Ready_Queue is record
      Storage : Queue_Storage := [others => No_Task];
      Length  : Queue_Length := 0;
   end record;

   function Contains
     (Queue : Ready_Queue;
      Candidate : Task_Ref) return Boolean
   is (Is_Valid_Task (Candidate)
       and then
         (for some Index in Queue_Index =>
            Index <= Queue.Length
            and then Queue.Storage (Index) = Candidate));

   function Is_Valid (Queue : Ready_Queue) return Boolean
   is ((for all Index in Queue_Index =>
          (if Index <= Queue.Length
           then Is_Valid_Task (Queue.Storage (Index))
           else Queue.Storage (Index) = No_Task))
       and then
         (for all Left in Queue_Index =>
            (for all Right in Queue_Index =>
               (if Left <= Queue.Length
                  and then Right <= Queue.Length
                  and then Left /= Right
                then Queue.Storage (Left) /= Queue.Storage (Right)))));

   function Can_Enqueue
     (Queue : Ready_Queue;
      Candidate : Task_Ref) return Boolean
   is (Is_Valid (Queue)
       and then Queue.Length < Queue_Capacity
       and then Is_Valid_Task (Candidate)
       and then not Contains (Queue, Candidate));

   function Enqueue
     (Queue : Ready_Queue;
      Candidate : Task_Ref) return Ready_Queue
   with Pre  => Can_Enqueue (Queue, Candidate),
        Post => Is_Valid (Enqueue'Result)
          and then Enqueue'Result.Length = Queue.Length + 1
          and then Contains (Enqueue'Result, Candidate);

   type Selection is record
      Selected  : Task_Ref := No_Task;
      Remainder : Ready_Queue;
   end record;

   function Select_Next (Queue : Ready_Queue) return Selection
   with Pre  => Is_Valid (Queue),
        Post => Is_Valid (Select_Next'Result.Remainder)
          and then
            (if Queue.Length = 0
             then Select_Next'Result.Selected = No_Task
               and then Select_Next'Result.Remainder = Queue
             else Select_Next'Result.Selected
               = Queue.Storage (Queue_Index'First)
               and then Select_Next'Result.Remainder.Length
                 = Queue.Length - 1);
end Flyology.Scheduler_Contract;
