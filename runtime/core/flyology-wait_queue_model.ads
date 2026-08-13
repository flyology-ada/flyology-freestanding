--  SPDX-License-Identifier: MIT OR Apache-2.0

with Flyology.Task_Primitives_Contract;

package Flyology.Wait_Queue_Model
  with SPARK_Mode => On
is
   package Primitives renames Flyology.Task_Primitives_Contract;
   package Dispatcher renames Primitives.Model;
   use type Primitives.Wait_Token;
   use type Dispatcher.Task_Ref;
   use type Dispatcher.Generation;

   Capacity : constant := 16;
   subtype Queue_Index is Positive range 1 .. Capacity;
   subtype Queue_Length is Natural range 0 .. Capacity;
   type Queue_Storage is array (Queue_Index) of Primitives.Wait_Token;

   Empty_Token : constant Primitives.Wait_Token :=
     (Task_Reference => Dispatcher.No_Task,
      Generation     => Dispatcher.Generation'First);

   type Wait_Queue is record
      Storage : Queue_Storage := [others => Empty_Token];
      Length  : Queue_Length := 0;
   end record;

   function Contains
     (Queue : Wait_Queue;
      Token : Primitives.Wait_Token) return Boolean
   is (for some Index in Queue_Index =>
         Index <= Queue.Length and then Queue.Storage (Index) = Token);

   function Contains_Task
     (Queue     : Wait_Queue;
      Reference : Dispatcher.Task_Ref) return Boolean
   is (Reference /= Dispatcher.No_Task
       and then
         (for some Index in Queue_Index =>
            Index <= Queue.Length
              and then Queue.Storage (Index).Task_Reference = Reference));

   function Valid (Queue : Wait_Queue) return Boolean
   is ((for all Index in Queue_Index =>
          (if Index <= Queue.Length
           then Queue.Storage (Index).Task_Reference /= Dispatcher.No_Task
             and then Queue.Storage (Index).Generation /=
               Dispatcher.Generation'First
           else Queue.Storage (Index) = Empty_Token))
       and then
         (for all Left in Queue_Index =>
            (for all Right in Queue_Index =>
               (if Left < Right and then Right <= Queue.Length
                then Queue.Storage (Left).Task_Reference /=
                  Queue.Storage (Right).Task_Reference))));

   type Enqueue_Status is (Enqueued, Duplicate_Task, Full, Invalid);
   type Enqueue_Result is record
      Queue  : Wait_Queue;
      Status : Enqueue_Status := Invalid;
   end record;

   function Enqueue
     (Before : Wait_Queue;
      Token  : Primitives.Wait_Token) return Enqueue_Result
   with Pre => Valid (Before),
        Post => Valid (Enqueue'Result.Queue)
          and then
            (if Enqueue'Result.Status = Enqueued
             then Enqueue'Result.Queue.Length = Before.Length + 1
               and then Contains (Enqueue'Result.Queue, Token)
             else Enqueue'Result.Queue = Before);

   type Remove_Status is (Removed, Not_Found, Stale);
   type Remove_Result is record
      Queue  : Wait_Queue;
      Status : Remove_Status := Not_Found;
   end record;

   function Remove_Exact
     (Before : Wait_Queue;
      Token  : Primitives.Wait_Token) return Remove_Result
   with Pre => Valid (Before),
        Post => Valid (Remove_Exact'Result.Queue)
          and then
            (if Remove_Exact'Result.Status = Removed
             then Remove_Exact'Result.Queue.Length = Before.Length - 1
               and then not Contains (Remove_Exact'Result.Queue, Token)
             else Remove_Exact'Result.Queue = Before);

   type Head_Result is record
      Queue : Wait_Queue;
      Found : Boolean := False;
      Token : Primitives.Wait_Token := Empty_Token;
   end record;

   function Take_Head (Before : Wait_Queue) return Head_Result
   with Pre => Valid (Before),
        Post => Valid (Take_Head'Result.Queue)
          and then
            (if Take_Head'Result.Found
             then Take_Head'Result.Token = Before.Storage (Queue_Index'First)
               and then Take_Head'Result.Queue.Length = Before.Length - 1
             else Take_Head'Result.Queue = Before
               and then Before.Length = 0);
end Flyology.Wait_Queue_Model;
