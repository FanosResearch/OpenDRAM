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

        .CH_SEL_WIDTH           (CH_WIDTH),
        .RNK_SEL_WIDTH          (RNK_WIDTH),
        .BG_SEL_WIDTH           (BG_WIDTH),
        .BNK_SEL_WIDTH          (BNK_WIDTH),
        .ROW_SEL_WIDTH          (ROW_WIDTH),
        .COL_SEL_WIDTH          (COL_WIDTH),
        .ADDR_WIDTH         (ADDR_WIDTH),

        .DATA_PTR_WIDTH         (DPTR_WIDTH),
        .CMD_TYPE_WIDTH     (CMD_TYPE_WIDTH),

        .PTR_WIDTH          (PTR_WIDTH),

        .CURRENT_BANK_ID            (BANK_ID),

        .TCQ                (TCQ)

        ) command_generator_b_inst (
    
        .i_clk            (clk), 
        .i_rstn          (rst_n),

        .i_won_addr       (won_addr),
        .i_won_ap         (won_ap),
        .i_won_dptr       (won_dptr),
        .i_won_req        (won_cmd),
        .i_won_open       (won_open),
        .i_won_inject     (won_inject),
        .i_won_valid      (won),

        // Periodic Read
        .i_inject_select  (inject_select),
        .i_inject_open    (inject_open),
        .i_per_rd_req     (per_rd_req),
        .i_inject_row     (open_row),
        .o_per_rd_accept  (per_rd_accept),

        // Command Queue Interface
        .o_channel      (o_channel),
        .o_rank         (o_rank),  
        .o_group        (o_group), 
        .o_bank         (o_bank),  
        .o_row          (o_row),  
        .o_column       (o_column), 
        .o_ptr          (o_ptr),

        .o_pre_bundle_valid   (pre_bundle_valid),
        .o_pre_bundle_cmd     (pre_bundle_cmd), 
    
        .o_act_bundle_valid   (act_bundle_valid),
        .o_act_bundle_cmd     (act_bundle_cmd),
    
        .o_cas_bundle_valid   (cas_bundle_valid),
        .o_cas_bundle_cmd     (cas_bundle_cmd),

        .o_block_frfcfs                  (block_from_command_generator), 
        .i_block_from_mc_refresh  (block_from_mc_refresh),
        .i_open_request_allowed   (open_request_allowed),
        .i_close_request_allowed  (close_request_allowed)
    );
                        
    frfcfs_b#(

        .CH_SEL_WIDTH   (CH_WIDTH),
        .RNK_SEL_WIDTH  (RNK_WIDTH),
        .BG_SEL_WIDTH   (BG_WIDTH),
        .BNK_SEL_WIDTH  (BNK_WIDTH),
        .ROW_SEL_WIDTH  (ROW_WIDTH),
        .COL_SEL_WIDTH  (COL_WIDTH),
        .ADDR_WIDTH (ADDR_WIDTH),

        .GFIFO_SIZE (GFIFO_SIZE),
        .DPTR_WIDTH (DPTR_WIDTH),
        .REQ_TYPE_WIDTH  (REQ_WIDTH),

        .TCQ        (TCQ)

        ) frfcfs_b_inst (
    
        .i_clk                          (clk),
        .i_rstn                        (rst_n),

        .i_channel                      (1'b0),
        .i_rank                         (rank),
        .i_group                           (group),
        .i_bank                         (bank),
        .i_row                          (row),
        .i_column                       (col),
        .i_dptr                         (dptr_ni2rq),
        .i_ap                           (ap),
        .i_req_type                     (req_type),

        .i_bank_is_idle                    (idle_flag),
        .i_current_open_row                     (open_row),
        .i_use_addr                     (use_addr),
        
        .i_init_data_rd                 (init_data_rd),
        .i_init_data_wr                 (init_data_wr),
        .i_done_rd_dptr                 (done_rd_dptr),
        .i_done_wr_dptr                 (done_wr_dptr),
        
        .o_won_dptr                     (won_dptr),
        .o_won_open                     (won_open),
        .o_won_valid                          (won),
        .o_won_addr                     (won_addr),
        .o_won_ap                       (won_ap),
        .o_won_req                      (won_cmd),
        .o_won_inject                   (won_inject),

        .i_block_from_command_generator (block_from_command_generator),
        .i_block_from_mc_refresh        (block_from_mc_refresh),
        
        .o_is_full                      (is_full)
    );
endmodule
