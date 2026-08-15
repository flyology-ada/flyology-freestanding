--  SPDX-License-Identifier: MIT OR Apache-2.0

package body Flyology.Exceptional_Completion_Model
  with SPARK_Mode => On
is
   function Complete
     (Before : Completion_Phase;
      Kind   : Completion_Kind) return Complete_Result
   is
   begin
      if Before in Queued | Accepted then
         return
           (Phase  => (if Kind = Normal
                       then Completed_Normal
                       else Completed_Exceptional),
            Status => Completed);
      end if;
      return (Phase => Before, Status => Not_Active);
   end Complete;

   function Consume (Before : Completion_Phase) return Consume_Result is
   begin
      if Before in Completed_Normal | Completed_Exceptional then
         return (Phase => Free, Status => Consumed);
      end if;
      return (Phase => Before, Status => Not_Completed);
   end Consume;

   function Select_Delivery
     (Has_Exception_Identity : Boolean;
      Abort_Deliverable      : Boolean) return Delivery_Action
   is
   begin
      if Abort_Deliverable then
         return Deliver_Abort;
      elsif Has_Exception_Identity then
         return Raise_Transferred_Exception;
      else
         return Return_Normally;
      end if;
   end Select_Delivery;
end Flyology.Exceptional_Completion_Model;
