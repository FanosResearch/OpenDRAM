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

`timescale 1ps / 1ps

`include "../global.svh"

`ifdef USE_RELATIVE_PATH_INCLUDES
    `include "./command_generator_b.sv"
    `include "./frfcfs_b.sv"
`endif // `ifdef USE_RELATIVE_PATH_INCLUDES


module request_scheduler_b#(

    parameter CH_WIDTH = 1,
    parameter RNK_WIDTH = 1,
    parameter BG_WIDTH = 1,
    parameter BNK_WIDTH = 2,
    parameter COL_WIDTH = 10,
    parameter ROW_WIDTH = 18,
    parameter ADDR_WIDTH = (RNK_WIDTH + BG_WIDTH + BNK_WIDTH + COL_WIDTH + ROW_WIDTH),

    parameter DPTR_WIDTH = 5,
    parameter PTR_WIDTH = DPTR_WIDTH + 1,
    
    parameter REQ_WIDTH = 3,
    parameter CMD_TYPE_WIDTH = 3,

    parameter BANK_ID = 0,

    parameter GFIFO_SIZE = 6,
    parameter QUEUE_SIZE = 6,
    parameter QUEUE_SIZE_WIDTH = $clog2(QUEUE_SIZE),

    parameter TCQ       = 100

    )(

    input wire rst_n,
    input wire clk,
    
    input wire [RNK_WIDTH-1:0]   rank,
    input wire [BG_WIDTH-1:0]    group,
    input wire [BNK_WIDTH-1:0]   bank,
    input wire [COL_WIDTH-1:0]   col,
    input wire [ROW_WIDTH-1:0]   row,
    input wire [REQ_WIDTH-1:0]   req_type,
    input wire                   use_addr,
    input wire                   ap,
    input wire [DPTR_WIDTH-1:0]  dptr_ni2rq,
    
    input wire                   idle_flag,
    input wire  [ROW_WIDTH-1:0]  open_row,
     
    input   wire                 per_rd_req, 
    input   wire                 inject_select,
    input   wire                 inject_open,
    output  wire                 per_rd_accept,

    input wire                   request_scheduler_select,
    output reg                   accept_from_ni_r,
    output wire                  accept_from_ni,

    input wire                   init_data_rd,
    input wire                   init_data_wr,
    input wire  [DPTR_WIDTH-1:0] done_rd_dptr,
    input wire  [DPTR_WIDTH-1:0] done_wr_dptr,
    
    // Command Queue Interface

    output wire [CH_WIDTH-1:0]  o_channel,
    output wire [RNK_WIDTH-1:0] o_rank,  
    output wire [BG_WIDTH-1:0]  o_group, 
    output wire [BNK_WIDTH-1:0] o_bank,  
    output wire [ROW_WIDTH-1:0] o_row,  
    output wire [COL_WIDTH-1:0] o_column, 
    output wire [PTR_WIDTH-1:0] o_ptr,

    output wire                      pre_bundle_valid,
    output wire [CMD_TYPE_WIDTH-1:0] pre_bundle_cmd, 
    
    output wire                      act_bundle_valid,
    output wire [CMD_TYPE_WIDTH-1:0] act_bundle_cmd,
    
    output wire                      cas_bundle_valid,
    output reg [CMD_TYPE_WIDTH-1:0]  cas_bundle_cmd,

    output wire is_full,

    input wire open_request_allowed,
    input wire close_request_allowed,

    input wire stall,
    input wire block_from_mc_refresh
    );
    
    localparam ADDR_WDITH = (CH_WIDTH + RNK_WIDTH + BG_WIDTH + BNK_WIDTH + COL_WIDTH + ROW_WIDTH);

    wire [ADDR_WIDTH-1:0]       won_addr;
    wire                        won_ap;
    wire [QUEUE_SIZE_WIDTH-1:0] won_qptr;
    wire [DPTR_WIDTH-1:0]       won_dptr;
    wire [2-1:0]                won_cmd;
    wire                        won;
    wire                        won_open;
    wire                        won_inject;
    wire                        request_queue_is_full;
    wire                        global_fifo_is_full;
    wire                        block_from_command_generator;

    wire    accept_from_ni_comb;

    reg     per_rd_req_r1;
    wire    per_rd_block;

    assign accept_from_ni_comb = (~is_full & ~per_rd_block);
    assign accept_from_ni = accept_from_ni_comb;

    assign per_rd_block = per_rd_req & ~per_rd_req_r1 & inject_select;

    always @(posedge clk) begin
        per_rd_req_r1 <= #TCQ per_rd_req;
        accept_from_ni_r <= #TCQ accept_from_ni_comb;
    end

    command_generator_b#(

        .CH_WIDTH           (CH_WIDTH),
        .RNK_WIDTH          (RNK_WIDTH),
        .BG_WIDTH           (BG_WIDTH),
        .BNK_WIDTH          (BNK_WIDTH),
        .COL_WIDTH          (COL_WIDTH),
        .ROW_WIDTH          (ROW_WIDTH),
        .ADDR_WIDTH         (ADDR_WIDTH),

        .DPTR_WIDTH         (DPTR_WIDTH),
        .CMD_TYPE_WIDTH     (CMD_TYPE_WIDTH),

        .QUEUE_SIZE_WIDTH   (QUEUE_SIZE_WIDTH),
        .PTR_WIDTH          (PTR_WIDTH),

        .BANK_ID            (BANK_ID),

        .TCQ                (TCQ)

        ) command_generator_b_inst (
    
        .clk            (clk), 
        .rst_n          (rst_n),

        .won_addr       (won_addr),
        .won_ap         (won_ap),
        .won_qptr       (won_qptr),
        .won_dptr       (won_dptr),
        .won_cmd        (won_cmd),
        .won            (won),
        .won_open       (won_open),
        .won_inject     (won_inject),

        // Periodic Read
        .inject_select  (inject_select),
        .inject_open    (inject_open),
        .per_rd_req     (per_rd_req),
        .inject_row     (open_row),
        .per_rd_accept  (per_rd_accept),

        // Command Queue Interface

        .o_channel      (o_channel),
        .o_rank         (o_rank),  
        .o_group        (o_group), 
        .o_bank         (o_bank),  
        .o_row          (o_row),  
        .o_column       (o_column), 
        .o_ptr          (o_ptr),

        .pre_bundle_valid   (pre_bundle_valid),
        .pre_bundle_cmd     (pre_bundle_cmd), 
    
        .act_bundle_valid   (act_bundle_valid),
        .act_bundle_cmd     (act_bundle_cmd),
    
        .cas_bundle_valid   (cas_bundle_valid),
        .cas_bundle_cmd     (cas_bundle_cmd),

        .block                  (block_from_command_generator), 
        .block_from_mc_refresh  (block_from_mc_refresh),
        .open_request_allowed   (open_request_allowed),
        .close_request_allowed  (close_request_allowed)
    );
                        
    frfcfs_b#(

        .CH_WIDTH   (CH_WIDTH),
        .RNK_WIDTH  (RNK_WIDTH),
        .BG_WIDTH   (BG_WIDTH),
        .BNK_WIDTH  (BNK_WIDTH),
        .COL_WIDTH  (COL_WIDTH),
        .ROW_WIDTH  (ROW_WIDTH),
        .ADDR_WIDTH (ADDR_WIDTH),

        .GFIFO_SIZE (GFIFO_SIZE),
        .DPTR_WIDTH (DPTR_WIDTH),
        .REQ_WIDTH  (REQ_WIDTH),

        .TCQ        (TCQ)

        ) frfcfs_b_inst (
    
        .rst_n                        (rst_n),
        .clk                          (clk),
        .channel                      (1'b0),
        .rank                         (rank),
        .bg                           (group),
        .bank                         (bank),
        .col                          (col),
        .row                          (row),
        .dptr                         (dptr_ni2rq),
        .ap                           (ap),
        .req_type                     (req_type),
        .idle_flag                    (idle_flag),
        .open_row                     (open_row),
        .use_addr                     (use_addr),
        .init_data_rd                 (init_data_rd),
        .init_data_wr                 (init_data_wr),
        .done_rd_dptr                 (done_rd_dptr),
        .done_wr_dptr                 (done_wr_dptr),
        .won_dptr                     (won_dptr),
        .won_open                     (won_open),
        .won                          (won),
        .won_addr                     (won_addr),
        .won_ap                       (won_ap),
        .won_cmd                      (won_cmd),
        .won_inject                   (won_inject),
        .block_from_command_generator (block_from_command_generator),
        .block_from_mc_refresh        (block_from_mc_refresh),
        .is_full                      (is_full)
    );
endmodule
