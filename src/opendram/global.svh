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

// DDR4 command type definitions

`define NOP 3'b000
`define PRE 3'b001
`define ACT 3'b010
`define CASRD 3'b011
`define CASRDA 3'b101
`define CASWR 3'b100
`define CASWRA 3'b110

// ----------------------------------------

// when trying to integrate this memory controller with Xilinx MIG DDR4 IP,
// it is required to include all files used within a source file with their relative path
// otherwise, the Vivado will raise the error for not being able to locate modules
// define the macro below during integration

`define USE_RELATIVE_PATH_INCLUDES

// ----------------------------------------