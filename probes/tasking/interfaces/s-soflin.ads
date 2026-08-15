package System.Soft_Links is
   pragma Preelaborate;
   type No_Param_Procedure is access procedure;
   type No_Param_Function is access function return Integer;

   Abort_Defer     : No_Param_Procedure;
   Abort_Undefer   : No_Param_Procedure;
   Enter_Master    : No_Param_Procedure;
   Complete_Master : No_Param_Procedure;
   Current_Master  : No_Param_Function;
end System.Soft_Links;
