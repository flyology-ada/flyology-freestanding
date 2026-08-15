--  SPDX-License-Identifier: MIT OR Apache-2.0

with Flyology.RTS;

package body System.Multiprocessors is
   function Number_Of_CPUs return CPU is
     (CPU (Flyology.RTS.Number_Of_CPUs));
end System.Multiprocessors;
