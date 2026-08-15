with System.Tasking;

package Ada.Task_Identification is
   type Task_Id is private;
   Null_Task_Id : constant Task_Id;
   function Current_Task return Task_Id;
   function Is_Terminated (T : Task_Id) return Boolean;
   function Is_Callable (T : Task_Id) return Boolean;
private
   type Task_Id is new System.Tasking.Task_Id;
   Null_Task_Id : constant Task_Id := null;
end Ada.Task_Identification;
