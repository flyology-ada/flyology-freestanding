--  SPDX-License-Identifier: MIT OR Apache-2.0
--
--  Exact task/wait identity shared by deterministic models and the kernel.
--  This package declares data only; production operations are typed Ada calls
--  on Flyology_Freestanding.Kernel rather than an unbound imported ABI.

with Flyology_Freestanding.Dispatcher_Model;

package Flyology_Freestanding.Task_Primitives is
   package Model renames Flyology_Freestanding.Dispatcher_Model;

   type Wait_Token is record
      Task_Reference : Model.Task_Ref := Model.No_Task;
      Generation : Model.Generation := Model.Generation'First;
   end record;
end Flyology_Freestanding.Task_Primitives;
