--  SPDX-License-Identifier: MIT OR Apache-2.0

package body Ada.Tags is
   function Expanded_Name (T : Tag) return String is
      pragma Unreferenced (T);
   begin
      return "";
   end Expanded_Name;

   function Wide_Expanded_Name (T : Tag) return Wide_String is
      pragma Unreferenced (T);
   begin
      return "";
   end Wide_Expanded_Name;

   function Wide_Wide_Expanded_Name (T : Tag) return Wide_Wide_String is
      pragma Unreferenced (T);
   begin
      return "";
   end Wide_Wide_Expanded_Name;

   function External_Tag (T : Tag) return String is
      pragma Unreferenced (T);
   begin
      return "";
   end External_Tag;

   function Internal_Tag (External : String) return Tag is
      pragma Unreferenced (External);
   begin
      return No_Tag;
   end Internal_Tag;

   function Descendant_Tag (External : String; Ancestor : Tag) return Tag is
      pragma Unreferenced (External, Ancestor);
   begin
      return No_Tag;
   end Descendant_Tag;

   function Is_Descendant_At_Same_Level
     (Descendant : Tag;
      Ancestor   : Tag) return Boolean is
     (Descendant = Ancestor);

   function Parent_Tag (T : Tag) return Tag is
      pragma Unreferenced (T);
   begin
      return No_Tag;
   end Parent_Tag;

   function Interface_Ancestor_Tags (T : Tag) return Tag_Array is
      pragma Unreferenced (T);
   begin
      return [1 .. 0 => No_Tag];
   end Interface_Ancestor_Tags;

   function Is_Abstract (T : Tag) return Boolean is
      pragma Unreferenced (T);
   begin
      return False;
   end Is_Abstract;
end Ada.Tags;
