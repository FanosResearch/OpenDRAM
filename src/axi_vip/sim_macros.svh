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

/** Enable the use of AXI VIP instead of MIG TG to generate custom trace-based traffic */
// `define USE_AXI_VIP

/** Define if using Linux OS */
//`define LINUX_OS

/** Number of cores/traces to simulate */
`define NUM_CORES 1

/** Number of bits required to index cores. Will be used to manipulate trasnaction ID MSB bits */
/** Must be log2(NUM_CORES) */
`define CORE_INDEX_WIDTH 1

/** Custom debug messages enablement */
`define CUSTUM_DEBUG_MESSAGE_ENABLE 0

/** XACT order report enablement */
`define XACT_GEN_REPORT_ENABLE 1
`ifndef LINUX_OS
    `define XACT_GEN_ORDER_PATH "..\\..\\..\\..\\..\\..\\results\\synthetic_x16"
`else
    `define XACT_GEN_ORDER_PATH "../../../../../../results/synthetic_x16"
`endif

/** Base path to the memory trace files
 * exact paths are set as follows based on the NUM_CORES:
 * "[MEM_TRACE_BASE_PATH]/[BENCHMARK_NAME]/trace_C0.txt",
 * "[MEM_TRACE_BASE_PATH]/[BENCHMARK_NAME]/trace_C1.txt",
 * "[MEM_TRACE_BASE_PATH]/[BENCHMARK_NAME]/trace_C2.txt",... */
`ifndef LINUX_OS
    `define MEM_TRACE_BASE_PATH "..\\..\\..\\..\\..\\..\\benchmarks\\synthetic_x16"
`else
    `define MEM_TRACE_BASE_PATH "../../../../../../benchmarks/synthetic_x16"
`endif
`define BENCHMARK_NAME "SEQ1R"

/** Indicate input trace format
"FORMAT1": [addr_decimal]   [type] [arrival_cycle]
"FORMAT2": [  addr_hex  ] 0 [type] [arrival_cycle] */
`define INPUT_TRC_FORMAT "FORMAT1"

/** Number of bits to mask from address LSB */
`define ADDR_OFFSET_LENGTH 5

/** Enable address MSB manipulation with trace ID */
/* Caution: in the default address mapping used,
   MSB bits in the address are assigned to row.
   Since the simulation infrastructure employes
   a Round-Robin fashion among cores, enabling
   this macro will result in generating all-closed
   memory requests. */
`define MANIPULATE_ADDR_WITH_TRACE_ID 0

/** Maximum number of outstanding transactions for each core */
`define OUT_OF_ORDER_STAGES 8

/** Transaction type keyword used in the trace */
`define WRITE "W"
`define READ "R"

/** AXI Port configurations */
`define AXI_ID_WIDTH 16
`define AXI_ADDR_WIDTH 30
`define AXI_DATA_WIDTH 512
`define WSTRB_WIDTH `AXI_DATA_WIDTH/8
`define AXI_BURST_LENGTH 1

