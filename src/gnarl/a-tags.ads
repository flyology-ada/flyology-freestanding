--  SPDX-License-Identifier: MIT OR Apache-2.0

with System;
with System.Storage_Elements;

package Ada.Tags is
   pragma Preelaborate;
   pragma Elaborate_Body;

   type Tag is private;
   No_Tag : constant Tag;

   function Expanded_Name (T : Tag) return String;
   function Wide_Expanded_Name (T : Tag) return Wide_String;
   function Wide_Wide_Expanded_Name (T : Tag) return Wide_Wide_String;
   function External_Tag (T : Tag) return String;
   function Internal_Tag (External : String) return Tag;
   function Descendant_Tag (External : String; Ancestor : Tag) return Tag;
   function Is_Descendant_At_Same_Level
     (Descendant : Tag;
      Ancestor   : Tag) return Boolean;
   function Parent_Tag (T : Tag) return Tag;

   type Tag_Array is array (Positive range <>) of Tag;
   function Interface_Ancestor_Tags (T : Tag) return Tag_Array;
   function Is_Abstract (T : Tag) return Boolean;

   Tag_Error : exception;

private
   type Prim_Ptr is access procedure;
   type Address_Array is array (Integer range <>) of Prim_Ptr;
   subtype Dispatch_Table is Address_Array (1 .. 1);

   type Tag is access all Dispatch_Table;
   for Tag'Storage_Size use 0;
   No_Tag : constant Tag := null;

   Max_Predef_Prims : constant Positive := 16;
   subtype Predef_Prims_Table is
     Address_Array (1 .. Max_Predef_Prims);
   type Predef_Prims_Table_Ptr is access all Predef_Prims_Table;
   type Addr_Ptr is access all System.Address;

   subtype Cstring is String;
   type Cstring_Ptr is access all Cstring;
   for Cstring_Ptr'Storage_Size use 0;

   type Tag_Ptr is access all Tag;
   for Tag_Ptr'Storage_Size use 0;
   type Tag_Table is array (Natural range <>) of Tag;

   type Size_Ptr is access function
     (A : System.Address) return Long_Long_Integer;
   for Size_Ptr'Storage_Size use 0;

   type Interface_Data is null record;
   type Interface_Data_Ptr is access all Interface_Data;
   for Interface_Data_Ptr'Storage_Size use 0;

   type Select_Specific_Data is null record;
   type Select_Specific_Data_Ptr is access all Select_Specific_Data;
   for Select_Specific_Data_Ptr'Storage_Size use 0;

   type Type_Specific_Data (Idepth : Natural) is record
      Access_Level       : Natural := 0;
      Alignment          : Natural := 1;
      Expanded_Name      : Cstring_Ptr := null;
      External_Tag       : Cstring_Ptr := null;
      HT_Link            : Tag_Ptr := null;
      Transportable      : Boolean := False;
      Is_Abstract        : Boolean := False;
      Needs_Finalization : Boolean := False;
      Size_Func          : Size_Ptr := null;
      Interfaces_Table   : Interface_Data_Ptr := null;
      SSD                : Select_Specific_Data_Ptr := null;
      Tags_Table         : Tag_Table (0 .. Idepth);
   end record;

   type Type_Specific_Data_Ptr is access all Type_Specific_Data;
   for Type_Specific_Data_Ptr'Storage_Size use 0;

   type Signature_Kind is (Unknown, Primary_DT, Secondary_DT);
   type Tagged_Kind is
     (TK_Abstract_Limited_Tagged, TK_Abstract_Tagged, TK_Limited_Tagged,
      TK_Protected, TK_Tagged, TK_Task);

   type Dispatch_Table_Wrapper (Num_Prims : Natural) is record
      Signature     : Signature_Kind := Unknown;
      Tag_Kind      : Tagged_Kind := TK_Tagged;
      Predef_Prims  : System.Address := System.Null_Address;
      Offset_To_Top : System.Storage_Elements.Storage_Offset := 0;
      TSD           : System.Address := System.Null_Address;
      Prims_Ptr     : aliased Address_Array (1 .. Num_Prims);
   end record;

   DT_Predef_Prims_Offset : constant
     System.Storage_Elements.Storage_Count := 24;
   DT_Offset_To_Top_Offset : constant
     System.Storage_Elements.Storage_Count := 16;
   DT_Typeinfo_Ptr_Size : constant
     System.Storage_Elements.Storage_Count := 8;
   DT_Offset_To_Top_Size : constant
     System.Storage_Elements.Storage_Count := 8;
   DT_Predef_Prims_Size : constant
     System.Storage_Elements.Storage_Count := 8;
end Ada.Tags;
