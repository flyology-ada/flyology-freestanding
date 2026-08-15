--  SPDX-License-Identifier: MIT OR Apache-2.0

with Flyology.Task_Primitives;

package Flyology.Timer_Model
  with SPARK_Mode
is
   package Primitives renames Flyology.Task_Primitives;
   package Dispatcher renames Primitives.Model;
   use type Dispatcher.Task_Ref;
   use type Dispatcher.Generation;
   use type Primitives.Wait_Token;

   Max_Timers : constant := 16;
   subtype Timer_Slot is Natural range 0 .. Max_Timers - 1;
   subtype Timer_Count is Natural range 0 .. Max_Timers;
   type Tick is range 0 .. 2 ** 63 - 1;

   type Timer_Record is record
      Active   : Boolean := False;
      Token    : Primitives.Wait_Token;
      Deadline : Tick := Tick'First;
   end record;
   type Timer_Table is array (Timer_Slot) of Timer_Record;
   Empty_Table : constant Timer_Table := [others => (others => <>)];

   function Valid (Table : Timer_Table) return Boolean
   is ((for all Left in Timer_Slot =>
          (for all Right in Timer_Slot =>
             (if Left /= Right and then Table (Left).Active
                and then Table (Right).Active
              then Table (Left).Token.Task_Reference /=
                Table (Right).Token.Task_Reference)))
       and then
         (for all Slot in Timer_Slot =>
            (if Table (Slot).Active
             then Table (Slot).Token.Task_Reference /= Dispatcher.No_Task
               and then Table (Slot).Token.Generation /=
                 Dispatcher.Generation'First)));

   function Contains
     (Table : Timer_Table;
      Token : Primitives.Wait_Token) return Boolean
   is (for some Slot in Timer_Slot =>
         Table (Slot).Active and then Table (Slot).Token = Token);

   function Contains_Task
     (Table     : Timer_Table;
      Reference : Dispatcher.Task_Ref) return Boolean
   is (Reference /= Dispatcher.No_Task
       and then
         (for some Slot in Timer_Slot =>
            Table (Slot).Active
            and then Table (Slot).Token.Task_Reference = Reference));

   type Register_Status is (Registered, Duplicate_Task, Full, Invalid);
   type Register_Result is record
      Table  : Timer_Table;
      Status : Register_Status := Invalid;
      Slot   : Timer_Slot := Timer_Slot'First;
   end record;

   function Register
     (Table    : Timer_Table;
      Token    : Primitives.Wait_Token;
      Deadline : Tick) return Register_Result
   with Pre => Valid (Table),
        Post => Valid (Register'Result.Table)
          and then
            (if Register'Result.Status = Registered
             then Contains (Register'Result.Table, Token)
               and then not Contains (Table, Token)
               and then Register'Result.Table
                 (Register'Result.Slot).Deadline = Deadline
             else Register'Result.Table = Table);

   type Cancel_Status is (Cancelled, Not_Found, Stale);
   type Cancel_Result is record
      Table  : Timer_Table;
      Status : Cancel_Status := Not_Found;
   end record;

   function Cancel
     (Table : Timer_Table;
      Token : Primitives.Wait_Token) return Cancel_Result
   with Pre => Valid (Table),
        Post => Valid (Cancel'Result.Table)
          and then
            (if Cancel'Result.Status = Cancelled
             then not Contains (Cancel'Result.Table, Token)
             else Cancel'Result.Table = Table);

   type Expiry_Result is record
      Table : Timer_Table;
      Found : Boolean := False;
      Token : Primitives.Wait_Token;
   end record;

   function Take_Due
     (Table : Timer_Table;
      Now   : Tick) return Expiry_Result
   with Pre => Valid (Table),
        Post => Valid (Take_Due'Result.Table)
          and then
            (if Take_Due'Result.Found
             then Take_Due'Result.Token.Task_Reference /= Dispatcher.No_Task
               and then not Contains
                 (Take_Due'Result.Table, Take_Due'Result.Token)
             else Take_Due'Result.Table = Table);

   type Deadline_Result is record
      Found    : Boolean := False;
      Deadline : Tick := Tick'Last;
   end record;

   function Earliest (Table : Timer_Table) return Deadline_Result
   with Pre => Valid (Table),
        Post =>
          (if Earliest'Result.Found
           then
             (for some Slot in Timer_Slot =>
                Table (Slot).Active
                and then Table (Slot).Deadline = Earliest'Result.Deadline)
             and then
               (for all Slot in Timer_Slot =>
                  (if Table (Slot).Active
                   then Earliest'Result.Deadline <= Table (Slot).Deadline)));
end Flyology.Timer_Model;
