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
