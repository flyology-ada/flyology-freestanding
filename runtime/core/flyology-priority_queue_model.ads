--  SPDX-License-Identifier: MIT OR Apache-2.0

with Flyology.Dispatcher_Model;

package Flyology.Priority_Queue_Model
  with SPARK_Mode => On
is
   use Flyology.Dispatcher_Model;

   Capacity : constant := 16;
   subtype Queue_Index is Positive range 1 .. Capacity;
   subtype Queue_Length is Natural range 0 .. Capacity;
   type Arrival_Sequence is range 0 .. 2 ** 63 - 1;
   No_Sequence : constant Arrival_Sequence := Arrival_Sequence'First;

   type Queue_Position is (At_Head, At_Tail);

   type Ready_Entry is record
      Reference : Task_Ref := No_Task;
      Priority  : Dispatcher_Model.Priority :=
        Dispatcher_Model.Priority'First;
      Sequence  : Arrival_Sequence := No_Sequence;
      Position  : Queue_Position := At_Tail;
   end record;

   Empty_Entry : constant Ready_Entry :=
     (Reference => No_Task,
      Priority  => Dispatcher_Model.Priority'First,
      Sequence  => No_Sequence,
      Position  => At_Tail);

   type Queue_Storage is array (Queue_Index) of Ready_Entry;

   type Ready_Queue is record
      Storage : Queue_Storage := [others => Empty_Entry];
      Length  : Queue_Length := 0;
   end record;

   function Precedes (Left, Right : Ready_Entry) return Boolean
   is (Left.Priority > Right.Priority
       or else
         (Left.Priority = Right.Priority
          and then
            ((Left.Position = At_Head and then Right.Position = At_Tail)
             or else
               (Left.Position = Right.Position
                and then
                  (if Left.Position = At_Head
                   then Left.Sequence > Right.Sequence
                   else Left.Sequence < Right.Sequence)))));

   function Contains
     (Queue     : Ready_Queue;
      Reference : Task_Ref) return Boolean
   is (Is_Valid_Task (Reference)
       and then
         (for some Index in Queue_Index =>
            Index <= Queue.Length
              and then Queue.Storage (Index).Reference = Reference));

   function Contains_Sequence
     (Queue    : Ready_Queue;
      Sequence : Arrival_Sequence) return Boolean
   is (Sequence /= No_Sequence
       and then
         (for some Index in Queue_Index =>
            Index <= Queue.Length
              and then Queue.Storage (Index).Sequence = Sequence));

   function Valid (Queue : Ready_Queue) return Boolean
   is ((for all Index in Queue_Index =>
          (if Index <= Queue.Length
           then Is_Valid_Task (Queue.Storage (Index).Reference)
             and then Queue.Storage (Index).Sequence /= No_Sequence
           else Queue.Storage (Index) = Empty_Entry))
       and then
         (for all Left in Queue_Index =>
            (for all Right in Queue_Index =>
               (if Left < Right and then Right <= Queue.Length
                then Queue.Storage (Left).Reference /=
                  Queue.Storage (Right).Reference
                  and then Queue.Storage (Left).Sequence /=
                    Queue.Storage (Right).Sequence))));

   type Enqueue_Status is (Enqueued, Duplicate, Full, Invalid);
   type Enqueue_Result is record
      Queue  : Ready_Queue;
      Status : Enqueue_Status := Invalid;
   end record;

   function Enqueue
     (Before : Ready_Queue;
      Item   : Ready_Entry) return Enqueue_Result
   with Pre => Valid (Before),
        Post => Valid (Enqueue'Result.Queue)
          and then
            (if Enqueue'Result.Status = Enqueued
             then Enqueue'Result.Queue.Length = Before.Length + 1
               and then Contains
                 (Enqueue'Result.Queue, Item.Reference)
             else Enqueue'Result.Queue = Before);

   type Change_Status is (Changed, Missing);
   type Change_Result is record
      Queue  : Ready_Queue;
      Status : Change_Status := Missing;
   end record;

   function Change_Priority
     (Before       : Ready_Queue;
      Reference    : Task_Ref;
      New_Priority : Dispatcher_Model.Priority) return Change_Result
   with Pre => Valid (Before),
        Post => Valid (Change_Priority'Result.Queue)
          and then Change_Priority'Result.Queue.Length = Before.Length
          and then
            (if Change_Priority'Result.Status = Missing
             then Change_Priority'Result.Queue = Before
             else Contains
               (Change_Priority'Result.Queue, Reference));

   type Selection is record
      Item      : Ready_Entry := Empty_Entry;
      Remainder : Ready_Queue;
      Found     : Boolean := False;
   end record;

   function Select_Next (Before : Ready_Queue) return Selection
   with Pre => Valid (Before),
        Post => Valid (Select_Next'Result.Remainder)
          and then
            (if Select_Next'Result.Found
             then Before.Length > 0
               and then Select_Next'Result.Remainder.Length =
                 Before.Length - 1
               and then not Contains
                 (Select_Next'Result.Remainder,
                  Select_Next'Result.Item.Reference)
               and then
                 (for all Index in Queue_Index =>
                    (if Index <= Before.Length then
                       not Precedes
                         (Before.Storage (Index),
                          Select_Next'Result.Item)))
             else Before.Length = 0
               and then Select_Next'Result.Remainder = Before);
end Flyology.Priority_Queue_Model;
