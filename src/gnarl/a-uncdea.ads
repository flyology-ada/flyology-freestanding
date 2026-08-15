--  SPDX-License-Identifier: MIT OR Apache-2.0

generic
   type Object (<>) is limited private;
   type Name is access Object;
procedure Ada.Unchecked_Deallocation (X : in out Name) with
  Depends => (X => null, null => X),
  Post => X = null;

pragma Preelaborate (Unchecked_Deallocation);
pragma Import (Intrinsic, Ada.Unchecked_Deallocation);
