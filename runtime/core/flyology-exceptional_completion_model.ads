--  SPDX-License-Identifier: MIT OR Apache-2.0

package Flyology.Exceptional_Completion_Model
  with Pure,
       SPARK_Mode => On
is
   type Completion_Phase is
     (Free, Queued, Accepted, Completed_Normal, Completed_Exceptional);
   type Completion_Kind is (Normal, Exceptional);

   function Stored_Is_Valid
     (Phase : Completion_Phase;
      Has_Exception_Identity : Boolean) return Boolean
   is (Has_Exception_Identity = (Phase = Completed_Exceptional));

   type Complete_Status is (Completed, Not_Active);
   type Complete_Result is record
      Phase  : Completion_Phase := Free;
      Status : Complete_Status := Not_Active;
   end record;

   function Complete
     (Before : Completion_Phase;
      Kind   : Completion_Kind) return Complete_Result
   with Post =>
     (if Before in Queued | Accepted
      then Complete'Result.Status = Completed
        and then Complete'Result.Phase =
          (if Kind = Normal then Completed_Normal
           else Completed_Exceptional)
      else Complete'Result.Status = Not_Active
        and then Complete'Result.Phase = Before);

   type Consume_Status is (Consumed, Not_Completed);
   type Consume_Result is record
      Phase  : Completion_Phase := Free;
      Status : Consume_Status := Not_Completed;
   end record;

   function Consume (Before : Completion_Phase) return Consume_Result
   with Post =>
     (if Before in Completed_Normal | Completed_Exceptional
      then Consume'Result.Status = Consumed
        and then Consume'Result.Phase = Free
      else Consume'Result.Status = Not_Completed
        and then Consume'Result.Phase = Before);
end Flyology.Exceptional_Completion_Model;
