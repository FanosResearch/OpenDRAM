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
    `include "./request_scheduler_b.sv"
`endif // `ifdef USE_RELATIVE_PATH_INCLUDES


module request_scheduler_wrapper#(

    parameter CH_SEL_WIDTH = 1,
    parameter RNK_SEL_WIDTH = 1,
    parameter BG_SEL_WIDTH = 1,
    parameter BNK_SEL_WIDTH = 2,
    parameter ROW_SEL_WIDTH = 17,
    parameter COL_SEL_WIDTH = 10,
    parameter ADDR_WIDTH = (RNK_SEL_WIDTH + BG_SEL_WIDTH + BNK_SEL_WIDTH + COL_SEL_WIDTH + ROW_SEL_WIDTH),

    parameter NUM_CH = 1,
    parameter NUM_RNK = 1,
    parameter NUM_BG = 2,
    parameter NUM_BNK = 4,
    parameter NUM_BNK_TOT = (NUM_CH * NUM_RNK * NUM_BG * NUM_BNK),

    parameter DPTR_WIDTH = 5,
    parameter PTR_WIDTH = DPTR_WIDTH + 1,

    parameter REQ_TYPE_WIDTH = 3,
    parameter CMD_TYPE_WIDTH = 3,    

    parameter GFIFO_SIZE = 6,

    parameter TCQ = 100

    )(

    input wire i_clk,
    input wire i_rstn,
    
    input wire [RNK_SEL_WIDTH-1:0]  i_rank,
    input wire [BG_SEL_WIDTH-1:0]   i_group,
    input wire [BNK_SEL_WIDTH-1:0]  i_bank,
    input wire [ROW_SEL_WIDTH-1:0]  i_row,
    input wire [COL_SEL_WIDTH-1:0]  i_column,
    input wire [CMD_TYPE_WIDTH-1:0] i_req_type,
    input wire i_use_addr,
    input wire i_ap,

    input wire [DPTR_WIDTH-1:0] i_dptr_ni2rq,
    output wire o_accept,

    input wire i_per_rd_req,
    output wire o_per_rd_accept,
    
    input wire i_block_from_mc_refresh,
    
    // page table interface
    input wire [NUM_BNK_TOT-1:0] i_bank_is_idle,
    input wire [ROW_SEL_WIDTH-1:0] i_current_open_row [NUM_BNK_TOT-1:0],

    // CAL TOP
    input wire                      i_init_data_rd,
    input wire                      i_init_data_wr,
    input wire  [DPTR_WIDTH-1:0]    i_done_rd_dptr,
    input wire  [DPTR_WIDTH-1:0]    i_done_wr_dptr,

    // command queue interface
    output wire [CH_SEL_WIDTH-1:0] o_channel [NUM_BNK_TOT-1:0],
    output wire [RNK_SEL_WIDTH-1:0] o_rank [NUM_BNK_TOT-1:0],  
    output wire [BG_SEL_WIDTH-1:0] o_group [NUM_BNK_TOT-1:0], 
    output wire [BNK_SEL_WIDTH-1:0] o_bank [NUM_BNK_TOT-1:0],  
    output wire [ROW_SEL_WIDTH-1:0] o_row [NUM_BNK_TOT-1:0],  
    output wire [COL_SEL_WIDTH-1:0] o_column [NUM_BNK_TOT-1:0], 
    output wire [PTR_WIDTH-1:0] o_ptr [NUM_BNK_TOT-1:0],

    output wire [NUM_BNK_TOT-1:0]    o_pre_bundle_valid,
    output wire [CMD_TYPE_WIDTH-1:0] o_pre_bundle_cmd [NUM_BNK_TOT-1:0], 
    
    output wire [NUM_BNK_TOT-1:0]    o_act_bundle_valid,
    output wire [CMD_TYPE_WIDTH-1:0] o_act_bundle_cmd [NUM_BNK_TOT-1:0],
    
    output wire [NUM_BNK_TOT-1:0]   o_cas_bundle_valid,
    output reg [CMD_TYPE_WIDTH-1:0] o_cas_bundle_cmd [NUM_BNK_TOT-1:0],

    input wire [NUM_BNK_TOT-1:0] i_open_request_allowed,
    input wire [NUM_BNK_TOT-1:0] i_close_request_allowed

    );

    genvar i;

    wire [NUM_BNK_TOT-1:0] use_addr_b;
    wire [NUM_BNK_TOT-1:0] is_full;
    wire [NUM_BNK_TOT-1:0] inject_select;
    wire [NUM_BNK_TOT-1:0] inject_index;
    wire [NUM_BNK_TOT-1:0] open_banks_and_not_full;
    wire [NUM_BNK_TOT-1:0] request_scheduler_select;
    wire [NUM_BNK_TOT-1:0] accept_from_ni;
    wire [NUM_BNK_TOT-1:0] per_rd_accept_b;

    reg [BG_SEL_WIDTH-1:0] group_r;
    reg [BNK_SEL_WIDTH-1:0] bank_r;

    wire all_banks_closed = &i_bank_is_idle;

    assign open_banks_and_not_full  = ~(i_bank_is_idle | is_full);
    assign inject_select            = (all_banks_closed) ? {{(NUM_BNK_TOT-2){1'b0}}, 1'b1} :  inject_index;

    assign o_per_rd_accept = |per_rd_accept_b;

    always @(posedge i_clk) begin
        group_r <= #TCQ i_group;
        bank_r <= #TCQ i_bank;
    end

    generate
        for (i=0; i<NUM_BNK_TOT; i++) begin : BANK
            if(i==0) begin
                assign inject_index[0] = open_banks_and_not_full[0];    
            end else begin
                assign inject_index[i] = ~(|{(~open_banks_and_not_full[i]), open_banks_and_not_full[i-1:0]});
            end

            assign request_scheduler_select[i] = ({group_r, bank_r} == i);
        end    
    endgenerate
    
    assign use_addr_b = request_scheduler_select & {NUM_BNK_TOT{i_use_addr}};
    assign o_accept = &accept_from_ni;

    genvar bt;
    generate
        for(bt = 0; bt < NUM_BNK_TOT; bt = bt + 1) begin

            request_scheduler_b#(

                .CH_SEL_WIDTH(CH_SEL_WIDTH),
                .RNK_SEL_WIDTH(RNK_SEL_WIDTH),
                .BG_SEL_WIDTH(BG_SEL_WIDTH),
                .BNK_SEL_WIDTH(BNK_SEL_WIDTH),
                .ROW_SEL_WIDTH(ROW_SEL_WIDTH),
                .COL_SEL_WIDTH(COL_SEL_WIDTH),
                .ADDR_WIDTH(ADDR_WIDTH),

                .DPTR_WIDTH(DPTR_WIDTH),
                .PTR_WIDTH(PTR_WIDTH),

                .REQ_TYPE_WIDTH(REQ_TYPE_WIDTH),
                .CMD_TYPE_WIDTH(CMD_TYPE_WIDTH),

                .CURRENT_BANK_ID(bt),

                .GFIFO_SIZE(GFIFO_SIZE),

                .TCQ(TCQ)

            ) request_scheduler_b_inst (

                .i_clk(i_clk),
                .i_rstn(i_rstn),
    
                // NI Interface
                .i_rank(i_rank),
                .i_group(i_group),
                .i_bank(i_bank),
                .i_row(i_row),
                .i_column(i_column),
                .i_req_type(i_req_type),
                .i_use_addr(use_addr_b[bt]),
                .i_ap(i_ap),
                .i_dptr_ni2rq(i_dptr_ni2rq),

                // Page Table
                .i_bank_is_idle(i_bank_is_idle[bt]),
                .i_current_open_row(i_current_open_row[bt]),
                .i_block_from_mc_refresh(i_block_from_mc_refresh),

                .i_per_rd_req(i_per_rd_req), 
                .i_inject_select(inject_select[bt]),
                .i_inject_open(~all_banks_closed),
                .o_per_rd_accept(per_rd_accept_b[bt]),

                .o_accept_from_ni(accept_from_ni[bt]),
    
                .i_init_data_rd(i_init_data_rd),
                .i_init_data_wr(i_init_data_wr),
                .i_done_rd_dptr(i_done_rd_dptr),
                .i_done_wr_dptr(i_done_wr_dptr),

                .o_is_full(is_full[bt]),

                // Command Queue Interface
                .o_channel(o_channel[bt]),
                .o_rank(o_rank[bt]),  
                .o_group(o_group[bt]), 
                .o_bank(o_bank[bt]),  
                .o_row(o_row[bt]),  
                .o_column(o_column[bt]), 
                .o_ptr(o_ptr[bt]),

                .o_pre_bundle_valid(o_pre_bundle_valid[bt]),
                .o_pre_bundle_cmd(o_pre_bundle_cmd[bt]), 

                .o_act_bundle_valid(o_act_bundle_valid[bt]),
                .o_act_bundle_cmd(o_act_bundle_cmd[bt]),

                .o_cas_bundle_valid(o_cas_bundle_valid[bt]),
                .o_cas_bundle_cmd(o_cas_bundle_cmd[bt]),

                .i_open_request_allowed(i_open_request_allowed[bt]),
                .i_close_request_allowed(i_close_request_allowed[bt])
            );
        end
    endgenerate 

endmodule
