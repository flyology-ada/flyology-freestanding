--  SPDX-License-Identifier: MIT OR Apache-2.0

with Flyology.M3_Runtime;

package body System.Multiprocessors is
   function Number_Of_CPUs return CPU is
     (CPU (Flyology.M3_Runtime.Number_Of_CPUs));
end System.Multiprocessors;
