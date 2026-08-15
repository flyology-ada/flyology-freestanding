with System.Storage_Elements;

package System.Secondary_Stack is
   pragma Preelaborate;

   type Mark_Id is private;

   function SS_Mark return Mark_Id;
   procedure SS_Release (Mark : Mark_Id);

   procedure SS_Allocate
     (Addr         : out System.Address;
      Storage_Size : System.Storage_Elements.Storage_Count;
      Alignment    : System.Storage_Elements.Storage_Count);

private
   type Mark_Id is new System.Storage_Elements.Storage_Count;
end System.Secondary_Stack;
