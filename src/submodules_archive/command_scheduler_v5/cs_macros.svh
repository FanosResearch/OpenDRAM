//-----------------------------------------------------------------------------
// Copyright (C) 2025 McMaster University, University of Waterloo
// Copyright and related rights are licensed under the Solderpad Hardware
// License, Version 0.51 (the "License"); you may not use this file except in
// compliance with the License. You may obtain a copy of the License at
// http://solderpad.org/licenses/SHL-0.51. Unless required by applicable law
// or agreed to in writing, software, hardware and materials distributed under
// this License is distributed on an "AS IS" BASIS, WITHOUT WARRANTIES OR
// CONDITIONS OF ANY KIND, either express or implied. See the License for the
// specific language governing permissions and limitations under the License.
//-----------------------------------------------------------------------------

// by defining the macro below, the tFAW counter will be removed, and the following modification will be applied to the timing constraints:
// tRRD_S = tRRD_L = (tFAW+1)/4 OR ceil(tFAW/4)

`define OMIT_TFAW_COUNTER

// ----------------------------------------
    
// when the intra_bank and inter_bank constraint tables are separated,
// there is no comparison between the calculated constraint and the value already in the table
// there is one corner case in which the new issued command may override the previous value in the table with an smaller number:
// ACT ---(tRCD - tAL)---> RD ---(tRTP)---> PRE
//  |_________________(tRAS)_________________|
// for example, in the memory device Micron MT40A256M16GE-083E 2400 MHz (DDR4-C1 on AMD VCU118 Revision 2.0):
// tRCD - tAL = 16
// tRTP = 10
// tRAS = 39
// to address this corner case, we can either add a separate counter for tRAS constraint of each bank
// or we can increase the value of tRTP as shown in the file "time_constraints.vh"
// by defining the micro below, you can remove tRAS counter and the timing constraints will be modified accordingly

`define OMIT_TRAS_COUNTER

// ----------------------------------------
