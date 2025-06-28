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
    `include "./command_queue.sv"
`endif // `ifdef USE_RELATIVE_PATH_INCLUDES


module command_queue_wrapper#(

        parameter CMD_TYPE_WIDTH    = 3,
        parameter CH_WIDTH          = 1,
        parameter RNK_WIDTH         = 1,
        parameter BG_WIDTH          = 2,
        parameter BNK_WIDTH         = 3,
        parameter ROW_WIDTH         = 3,
        parameter COL_WIDTH         = 6,
        parameter DATA_PTR_WIDTH    = 4,
        parameter NUM_BNK_TOT       = 16

        )(
    
        input clk,
        input rstn,

        input [CH_WIDTH - 1 : 0] i_channel [NUM_BNK_TOT-1:0],
        input [RNK_WIDTH - 1 : 0] i_rank [NUM_BNK_TOT-1:0],
        input [BG_WIDTH - 1 : 0] i_bgroup [NUM_BNK_TOT-1:0],
        input [BNK_WIDTH - 1 : 0] i_bank [NUM_BNK_TOT-1:0],
        input [ROW_WIDTH - 1 : 0] i_row [NUM_BNK_TOT-1:0],
        input [COL_WIDTH - 1 : 0] i_column [NUM_BNK_TOT-1:0],

        input [DATA_PTR_WIDTH - 1 : 0] i_data_ptr [NUM_BNK_TOT-1:0],

        input [NUM_BNK_TOT-1:0] i_pre_valid,
        input [CMD_TYPE_WIDTH - 1 : 0] i_pre_cmd [NUM_BNK_TOT-1:0],
        input [NUM_BNK_TOT-1:0] i_act_valid,
        input [CMD_TYPE_WIDTH - 1 : 0] i_act_cmd [NUM_BNK_TOT-1:0],
        input [NUM_BNK_TOT-1:0] i_cas_valid,
        input [CMD_TYPE_WIDTH - 1 : 0] i_cas_cmd [NUM_BNK_TOT-1:0],

        input [NUM_BNK_TOT-1:0] i_dequeue,

        output [NUM_BNK_TOT-1:0] o_valid,

        output [NUM_BNK_TOT-1:0][CH_WIDTH - 1 : 0] o_channel,
        output [NUM_BNK_TOT-1:0][RNK_WIDTH - 1 : 0] o_rank,
        output [NUM_BNK_TOT-1:0][BG_WIDTH - 1 : 0] o_bgroup,
        output [NUM_BNK_TOT-1:0][BNK_WIDTH - 1 : 0] o_bank,
        output [NUM_BNK_TOT-1:0][ROW_WIDTH - 1 : 0] o_row,
        output [NUM_BNK_TOT-1:0][COL_WIDTH - 1 : 0] o_column,

        output [NUM_BNK_TOT-1:0][DATA_PTR_WIDTH - 1 : 0] o_data_ptr,

        output [NUM_BNK_TOT-1:0][CMD_TYPE_WIDTH - 1 : 0] o_cmd ,
        
        output [NUM_BNK_TOT-1:0] o_open_request_allowed,
        output [NUM_BNK_TOT-1:0] o_close_request_allowed
    );

    genvar bnk_g;
    generate
        for(bnk_g = 0; bnk_g < NUM_BNK_TOT; bnk_g = bnk_g + 1) 
        begin : BANK
            command_queue#(
                .CMD_TYPE_WIDTH(CMD_TYPE_WIDTH) ,
                .CH_SEL_WIDTH(CH_WIDTH)   ,
                .RNK_SEL_WIDTH(RNK_WIDTH)  ,
                .BG_SEL_WIDTH(BG_WIDTH)   ,
                .BNK_SEL_WIDTH(BNK_WIDTH)  ,
                .ROW_SEL_WIDTH(ROW_WIDTH)  ,
                .COL_SEL_WIDTH(COL_WIDTH)  ,
                .DATA_PTR_WIDTH(DATA_PTR_WIDTH) 
            )command_queue_inst(
    
                .i_clk(clk),
                .i_rstn(rstn),
    
                .i_channel(i_channel[bnk_g]),
                .i_rank(i_rank[bnk_g]),
                .i_bgroup(i_bgroup[bnk_g]),
                .i_bank(i_bank[bnk_g]),
                .i_row(i_row[bnk_g]),
                .i_column(i_column[bnk_g]),
    
                .i_data_ptr(i_data_ptr[bnk_g]),       
                .i_pre_valid(i_pre_valid[bnk_g]),
                .i_pre_cmd(i_pre_cmd[bnk_g]),
                .i_act_valid(i_act_valid[bnk_g]),
                .i_act_cmd(i_act_cmd[bnk_g]),
                .i_cas_valid(i_cas_valid[bnk_g]),
                .i_cas_cmd(i_cas_cmd[bnk_g]),
                .i_dequeue(i_dequeue[bnk_g]),
                .o_valid(o_valid[bnk_g]),
    
    
                .o_channel(o_channel[bnk_g]),
                .o_rank(o_rank[bnk_g]),
                .o_bgroup(o_bgroup[bnk_g]),
                .o_bank(o_bank[bnk_g]),
                .o_row(o_row[bnk_g]),
                .o_column(o_column[bnk_g]),
    
                .o_data_ptr(o_data_ptr[bnk_g]),
                .o_cmd(o_cmd[bnk_g]),
    
                .o_open_request_allowed(o_open_request_allowed[bnk_g]),
                .o_close_request_allowed(o_close_request_allowed[bnk_g])
            );  
        end
    endgenerate
endmodule
