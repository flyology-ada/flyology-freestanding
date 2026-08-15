--  SPDX-License-Identifier: MIT OR Apache-2.0
--
--  Exact task/wait identity shared by deterministic models and the kernel.
--  This package declares data only; production operations are typed Ada calls
--  on Flyology.Kernel rather than an unbound imported ABI.

with Flyology.Dispatcher_Model;

package Flyology.Task_Primitives is
   package Model renames Flyology.Dispatcher_Model;

   type Wait_Token is record
      Task_Reference : Model.Task_Ref := Model.No_Task;
      Generation : Model.Generation := Model.Generation'First;
   end record;
end Flyology.Task_Primitives;
