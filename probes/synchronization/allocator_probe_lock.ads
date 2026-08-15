--  SPDX-License-Identifier: MIT OR Apache-2.0

package Allocator_Probe_Lock is
   procedure Acquire
   with Export, Convention => C, External_Name => "flyology_rts_lock_acquire";

   procedure Release
   with Export, Convention => C, External_Name => "flyology_rts_lock_release";
end Allocator_Probe_Lock;
