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

    parameter CH_SEL_WIDTH = 1,
    parameter RNK_SEL_WIDTH = 1,
    parameter BG_SEL_WIDTH = 1,
    parameter BNK_SEL_WIDTH = 2,
    parameter ROW_SEL_WIDTH = 18,
    parameter COL_SEL_WIDTH = 10,
    parameter ADDR_WIDTH = (RNK_SEL_WIDTH + BG_SEL_WIDTH + BNK_SEL_WIDTH + COL_SEL_WIDTH + ROW_SEL_WIDTH),

    parameter DPTR_WIDTH = 5,
    parameter PTR_WIDTH = DPTR_WIDTH + 1,
    
    parameter REQ_TYPE_WIDTH = 3,
    parameter CMD_TYPE_WIDTH = 3,

    parameter CURRENT_BANK_ID = 0,

    parameter GFIFO_SIZE = 6,

    parameter TCQ       = 100

    )(

    input wire i_clk,
    input wire i_rstn,
    
    input wire [RNK_SEL_WIDTH-1:0]  i_rank,
    input wire [BG_SEL_WIDTH-1:0]   i_group,
    input wire [BNK_SEL_WIDTH-1:0]  i_bank,
    input wire [ROW_SEL_WIDTH-1:0]  i_row,
    input wire [COL_SEL_WIDTH-1:0]  i_column,
    input wire [REQ_TYPE_WIDTH-1:0] i_req_type,
    input wire                      i_use_addr,
    input wire                      i_ap,
    input wire [DPTR_WIDTH-1:0]     i_dptr_ni2rq,
    
    // Page Table
    input wire                      i_bank_is_idle,
    input wire  [ROW_SEL_WIDTH-1:0] i_current_open_row,
    input wire                      i_block_from_mc_refresh,
     
    input wire  i_per_rd_req, 
    input wire  i_inject_select,
    input wire  i_inject_open,
    output wire o_per_rd_accept,

    output wire o_accept_from_ni,

    input wire                  i_init_data_rd,
    input wire                  i_init_data_wr,
    input wire [DPTR_WIDTH-1:0] i_done_rd_dptr,
    input wire [DPTR_WIDTH-1:0] i_done_wr_dptr,

    output wire o_is_full,
    
    // Command Queue
    output wire [CH_SEL_WIDTH-1:0]  o_channel,
    output wire [RNK_SEL_WIDTH-1:0] o_rank,  
    output wire [BG_SEL_WIDTH-1:0]  o_group, 
    output wire [BNK_SEL_WIDTH-1:0] o_bank,  
    output wire [ROW_SEL_WIDTH-1:0] o_row,  
    output wire [COL_SEL_WIDTH-1:0] o_column, 
    output wire [PTR_WIDTH-1:0]     o_ptr,

    output wire                      o_pre_bundle_valid,
    output wire [CMD_TYPE_WIDTH-1:0] o_pre_bundle_cmd, 
    
    output wire                      o_act_bundle_valid,
    output wire [CMD_TYPE_WIDTH-1:0] o_act_bundle_cmd,
    
    output wire                      o_cas_bundle_valid,
    output reg [CMD_TYPE_WIDTH-1:0]  o_cas_bundle_cmd,

    input wire i_open_request_allowed,
    input wire i_close_request_allowed
    );
    
    localparam ADDR_WDITH = (CH_SEL_WIDTH + RNK_SEL_WIDTH + BG_SEL_WIDTH + BNK_SEL_WIDTH + COL_SEL_WIDTH + ROW_SEL_WIDTH);

    wire [ADDR_WIDTH-1:0]   won_addr;
    wire                    won_ap;
    wire [DPTR_WIDTH-1:0]   won_dptr;
    wire [2-1:0]            won_cmd;
    wire                    won;
    wire                    won_open;
    wire                    won_inject;
    wire                    request_queue_is_full;
    wire                    global_fifo_is_full;
    wire                    block_from_command_generator;

    wire accept_from_ni_comb;

    reg per_rd_req_r1;
    wire per_rd_block;

    assign accept_from_ni_comb = (~o_is_full & ~per_rd_block);
    assign o_accept_from_ni = accept_from_ni_comb;

    assign per_rd_block = i_per_rd_req & ~per_rd_req_r1 & i_inject_select;

    always @(posedge i_clk) begin
        per_rd_req_r1 <= #TCQ i_per_rd_req;
    end


    ////////////////////////////////////////////////////////
    ////              Command Generator                 ////
    ////////////////////////////////////////////////////////
    
    command_generator_b#(

        .CH_SEL_WIDTH(CH_SEL_WIDTH),
        .RNK_SEL_WIDTH(RNK_SEL_WIDTH),
        .BG_SEL_WIDTH(BG_SEL_WIDTH),
        .BNK_SEL_WIDTH(BNK_SEL_WIDTH),
        .ROW_SEL_WIDTH(ROW_SEL_WIDTH),
        .COL_SEL_WIDTH(COL_SEL_WIDTH),
        .ADDR_WIDTH(ADDR_WIDTH),

        .DATA_PTR_WIDTH(DPTR_WIDTH),
        .CMD_TYPE_WIDTH(CMD_TYPE_WIDTH),

        .PTR_WIDTH(PTR_WIDTH),

        .CURRENT_BANK_ID(CURRENT_BANK_ID),

        .TCQ(TCQ)

        ) command_generator_b_inst (
    
        .i_clk(i_clk), 
        .i_rstn(i_rstn),

        .i_won_addr(won_addr),
        .i_won_ap(won_ap),
        .i_won_dptr(won_dptr),
        .i_won_req(won_cmd),
        .i_won_open(won_open),
        .i_won_inject(won_inject),
        .i_won_valid(won),

        // Periodic Read
        .i_inject_select(i_inject_select),
        .i_inject_open(i_inject_open),
        .i_per_rd_req(i_per_rd_req),
        .i_inject_row(i_current_open_row),
        .o_per_rd_accept(o_per_rd_accept),

        // Command Queue Interface
        .o_channel(o_channel),
        .o_rank(o_rank),  
        .o_group(o_group), 
        .o_bank(o_bank),  
        .o_row(o_row),  
        .o_column(o_column), 
        .o_ptr(o_ptr),

        .o_pre_bundle_valid(o_pre_bundle_valid),
        .o_pre_bundle_cmd(o_pre_bundle_cmd), 
    
        .o_act_bundle_valid(o_act_bundle_valid),
        .o_act_bundle_cmd(o_act_bundle_cmd),
    
        .o_cas_bundle_valid(o_cas_bundle_valid),
        .o_cas_bundle_cmd(o_cas_bundle_cmd),

        .o_block_frfcfs(block_from_command_generator), 
        .i_block_from_mc_refresh(i_block_from_mc_refresh),
        .i_open_request_allowed(i_open_request_allowed),
        .i_close_request_allowed(i_close_request_allowed)
    );


    ////////////////////////////////////////////////////////
    ////                   FR-FCFS                      ////
    ////////////////////////////////////////////////////////
                        
    frfcfs_b#(

        .CH_SEL_WIDTH(CH_SEL_WIDTH),
        .RNK_SEL_WIDTH(RNK_SEL_WIDTH),
        .BG_SEL_WIDTH(BG_SEL_WIDTH),
        .BNK_SEL_WIDTH(BNK_SEL_WIDTH),
        .ROW_SEL_WIDTH(ROW_SEL_WIDTH),
        .COL_SEL_WIDTH(COL_SEL_WIDTH),
        .ADDR_WIDTH(ADDR_WIDTH),

        .GFIFO_SIZE(GFIFO_SIZE),
        .DPTR_WIDTH(DPTR_WIDTH),
        .REQ_TYPE_WIDTH(REQ_TYPE_WIDTH),

        .TCQ(TCQ)

        ) frfcfs_b_inst (
    
        .i_clk(i_clk),
        .i_rstn(i_rstn),

        .i_channel(1'b0),
        .i_rank(i_rank),
        .i_group(i_group),
        .i_bank(i_bank),
        .i_row(i_row),
        .i_column(i_column),
        .i_dptr(i_dptr_ni2rq),
        .i_ap(i_ap),
        .i_req_type(i_req_type),

        .i_bank_is_idle(i_bank_is_idle),
        .i_current_open_row(i_current_open_row),
        .i_use_addr(i_use_addr),
        
        .i_init_data_rd(i_init_data_rd),
        .i_init_data_wr(i_init_data_wr),
        .i_done_rd_dptr(i_done_rd_dptr),
        .i_done_wr_dptr(i_done_wr_dptr),
        
        .o_won_dptr(won_dptr),
        .o_won_open(won_open),
        .o_won_valid(won),
        .o_won_addr(won_addr),
        .o_won_ap(won_ap),
        .o_won_req(won_cmd),
        .o_won_inject(won_inject),

        .i_block_from_command_generator(block_from_command_generator),
        .i_block_from_mc_refresh(i_block_from_mc_refresh),
        
        .o_is_full(o_is_full)
    );
endmodule
