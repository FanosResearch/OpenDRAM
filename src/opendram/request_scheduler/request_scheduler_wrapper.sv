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

    parameter CH_WIDTH = 1,
    parameter RNK_WIDTH = 1,
    parameter BG_WIDTH = 1,
    parameter BNK_WIDTH = 2,
    parameter COL_WIDTH = 10,
    parameter ROW_WIDTH = 17,
    parameter ADDR_WIDTH = (RNK_WIDTH + BG_WIDTH + BNK_WIDTH + COL_WIDTH + ROW_WIDTH),

    parameter NUM_CH  = 1,
    parameter NUM_RNK  = 1,
    parameter NUM_BG   = 2,
    parameter NUM_BNK  = 4,
    parameter NUM_BNK_TOT = (NUM_CH * NUM_RNK * NUM_BG * NUM_BNK),

    parameter REQ_WIDTH = 3,
    parameter CMD_TYPE_WIDTH = 3,    
    parameter DPTR_WIDTH = 5,
    parameter PTR_WIDTH = DPTR_WIDTH + 1,

    parameter QUEUE_SIZE = 6,
    parameter QUEUE_SIZE_WIDTH = $clog2(QUEUE_SIZE),
    parameter GFIFO_SIZE = 6,

    parameter TCQ = 100

    )(

    input wire rst_n,
    input wire clk,
    
    input wire [RNK_WIDTH-1:0]      rank,
    input wire [BG_WIDTH-1:0]       group,
    input wire [BNK_WIDTH-1:0]      bank,
    input wire [COL_WIDTH-1:0]      col,
    input wire [ROW_WIDTH-1:0]      row,
    input wire [CMD_TYPE_WIDTH-1:0] req_type,
    input wire use_addr,
    input wire ap,

    input wire [DPTR_WIDTH-1:0] dptr_ni2rq,

    input   wire    per_rd_req,
    output  wire    per_rd_accept,

    input wire init_data_n,
    
    input wire [NUM_BNK_TOT-1:0] idle_flag,
    input wire [ROW_WIDTH-1:0] open_row [NUM_BNK_TOT-1:0],

    output wire [CH_WIDTH-1:0] o_channel [NUM_BNK_TOT-1:0],
    output wire [RNK_WIDTH-1:0] o_rank [NUM_BNK_TOT-1:0],  
    output wire [BG_WIDTH-1:0] o_group [NUM_BNK_TOT-1:0], 
    output wire [BNK_WIDTH-1:0] o_bank [NUM_BNK_TOT-1:0],  
    output wire [ROW_WIDTH-1:0] o_row [NUM_BNK_TOT-1:0],  
    output wire [COL_WIDTH-1:0] o_column [NUM_BNK_TOT-1:0], 
    output wire [PTR_WIDTH-1:0] o_ptr [NUM_BNK_TOT-1:0],

    output wire [NUM_BNK_TOT-1:0]    pre_bundle_valid,
    output wire [CMD_TYPE_WIDTH-1:0] pre_bundle_cmd [NUM_BNK_TOT-1:0], 
    
    output wire [NUM_BNK_TOT-1:0]    act_bundle_valid,
    output wire [CMD_TYPE_WIDTH-1:0] act_bundle_cmd [NUM_BNK_TOT-1:0],
    
    output wire [NUM_BNK_TOT-1:0]   cas_bundle_valid,
    output reg [CMD_TYPE_WIDTH-1:0] cas_bundle_cmd [NUM_BNK_TOT-1:0],

    input wire [NUM_BNK_TOT-1:0] open_request_allowed,
    input wire [NUM_BNK_TOT-1:0] close_request_allowed,

    output wire accept,

    input  wire block_from_mc_refresh,

    input wire                      init_data_rd,
    input wire                      init_data_wr,
    input wire  [DPTR_WIDTH-1:0]    done_rd_dptr,
    input wire  [DPTR_WIDTH-1:0]    done_wr_dptr

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

    reg [BG_WIDTH-1:0] group_r;
    reg [BNK_WIDTH-1:0] bank_r;

    wire all_banks_closed = &idle_flag;

    assign open_banks_and_not_full  = ~(idle_flag | is_full);
    assign inject_select            = (all_banks_closed) ? {{(NUM_BNK_TOT-2){1'b0}}, 1'b1} :  inject_index;

    assign per_rd_accept = |per_rd_accept_b;

    always @(posedge clk) begin
        group_r <= #TCQ group;
        bank_r <= #TCQ bank;
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
    
    assign use_addr_b = request_scheduler_select & {NUM_BNK_TOT{use_addr}};
    assign accept = &accept_from_ni;

    genvar bt;
    generate
        for(bt = 0; bt < NUM_BNK_TOT; bt = bt + 1) begin

            request_scheduler_b#(

                .CH_WIDTH(CH_WIDTH),
                .RNK_WIDTH(RNK_WIDTH),
                .BG_WIDTH(BG_WIDTH),
                .BNK_WIDTH(BNK_WIDTH),
                .COL_WIDTH(COL_WIDTH),
                .ROW_WIDTH(ROW_WIDTH),
                .ADDR_WIDTH(ADDR_WIDTH),

                .DPTR_WIDTH(DPTR_WIDTH),
                .PTR_WIDTH(PTR_WIDTH),

                .REQ_WIDTH(REQ_WIDTH),
                .CMD_TYPE_WIDTH(CMD_TYPE_WIDTH),

                .BANK_ID(bt),

                .GFIFO_SIZE(GFIFO_SIZE),
                .QUEUE_SIZE(QUEUE_SIZE),
                .QUEUE_SIZE_WIDTH(QUEUE_SIZE_WIDTH),

                .TCQ(TCQ)

            ) request_scheduler_b_inst (

                .rst_n(rst_n),
                .clk(clk),
    
                // NI Interface
                .rank(rank),
                .group(group),
                .bank(bank),
                .col(col),
                .row(row),
                .req_type(req_type),
                .use_addr(use_addr_b[bt]),
                .ap(ap),
                .dptr_ni2rq(dptr_ni2rq),

                .per_rd_req(per_rd_req), 
                .inject_select(inject_select[bt]),
                .request_scheduler_select(request_scheduler_select[bt]),
                .accept_from_ni_r(),
                .accept_from_ni(accept_from_ni[bt]),
                .inject_open(~all_banks_closed),
                .per_rd_accept(per_rd_accept_b[bt]),
    
                .stall(stall),
                .is_full(is_full[bt]),

                // Command Queue Interface
                .o_channel(o_channel[bt]),
                .o_rank(o_rank[bt]),  
                .o_group(o_group[bt]), 
                .o_bank(o_bank[bt]),  
                .o_row(o_row[bt]),  
                .o_column(o_column[bt]), 
                .o_ptr(o_ptr[bt]),
                .pre_bundle_valid(pre_bundle_valid[bt]),
                .pre_bundle_cmd(pre_bundle_cmd[bt]), 
                .act_bundle_valid(act_bundle_valid[bt]),
                .act_bundle_cmd(act_bundle_cmd[bt]),
                .cas_bundle_valid(cas_bundle_valid[bt]),
                .cas_bundle_cmd(cas_bundle_cmd[bt]),
                .open_request_allowed(open_request_allowed[bt]),
                .close_request_allowed(close_request_allowed[bt]),

                // Page Table
                .idle_flag(idle_flag[bt]),
                .open_row(open_row[bt]),
                .block_from_mc_refresh(block_from_mc_refresh),

                .init_data_rd(init_data_rd),
                .init_data_wr(init_data_wr),
                .done_rd_dptr(done_rd_dptr),
                .done_wr_dptr(done_wr_dptr)
            );
        end
    endgenerate 

endmodule
