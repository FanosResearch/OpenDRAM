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

`define     BL          4
`define     tCK         0.83 // not used anywhere
`define     tAL         0
`define     tCL         18
`define     tCWL        12
`define     tRCD        16
`define     tRP         16
`define     tRAS        39
`define     tRC         61
`define     tRFC        313 // not used anywhere
`define     tRFC2       312 // not used anywhere
`define     tRFC4       192 // not used anywhere
`define     tREFI       9363 // not used anywhere
`define     tPRE        1
`define     tWTR_L      10
`define     tFAW        40
`define     tWR         20
`define     tCCD_S      4
`define     tCCD_L      6
`define     tCKE        6
`define     tCKESR      7
`define     tXS         432 // not used anywhere
`define     tXP         8        
`define     tRTRS       0

`ifdef OMIT_TFAW_COUNTER
    `define     tRRD_S      (`tFAW + 1) / 4
    `define     tRRD_L      (`tFAW + 1) / 4
`else
    `define     tRRD_S      7
    `define     tRRD_L      8
`endif // `ifdef OMIT_TFAW_COUNTER

`ifdef USE_SEPARATE_INTER_INTRA_TABLES
    `define     tWTR_S      (`tWTR_L - `tCCD_S)
    `ifdef OMIT_TRAS_COUNTER
        `define     tRTP        (`tRAS - (`tRCD - `tAL))
    `else
        `define     tRTP        10
    `endif // `ifdef OMIT_TRAS_COUNTER
`else
    `define     tWTR_S      4
    `define     tRTP        10
`endif // `ifdef USE_SEPARATE_INTER_INTRA_TABLES
