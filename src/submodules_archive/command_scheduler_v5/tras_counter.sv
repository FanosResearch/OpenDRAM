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

`timescale 1ns / 1ps

`include "../global.svh"

`ifdef USE_RELATIVE_PATH_INCLUDES
    `include "./time_constraints.vh"
`endif // `ifdef USE_RELATIVE_PATH_INCLUDES

module tras_counter#(
    
    parameter CMD_TYPE_WIDTH    = 3,
    
    parameter NUM_RNK           = 1,
    parameter NUM_BG            = 2,
    parameter NUM_BNK           = 4,
	
    parameter RNK_SEL_WIDTH     = 1,
    parameter BG_SEL_WIDTH      = 1,
    parameter BNK_SEL_WIDTH     = 2,
    
    parameter TIME_WIDTH        = 6,
    parameter ISSUED_SUB_CYCLE  = 3,
    parameter TCQ               = 0.1
    
    )(
    
    // module working on the posedge of the clock
    input i_clk,
    // synchronous active-low reset
    input i_rstn,
    
    // command in the first sub-slot that can hold an act
    input [CMD_TYPE_WIDTH - 1 : 0] i_cmd_type,
	input [RNK_SEL_WIDTH - 1 : 0] i_cmd_rnk,
	input [BG_SEL_WIDTH - 1 : 0]  i_cmd_bg,
	input [BNK_SEL_WIDTH - 1 : 0] i_cmd_bnk,
	
	// ras counter
	output [NUM_RNK * NUM_BG * NUM_BNK - 1 : 0] [TIME_WIDTH - 1 : 0] o_ras_counter
    );
    
    //---------------------------------------------------
    //----------------- Local Parameter -----------------
    //---------------------------------------------------
    
    localparam NUM_BNK_TOT = NUM_RNK * NUM_BG * NUM_BNK;
    
    localparam SUB_CYCLE_OFFSET = (ISSUED_SUB_CYCLE == 0) ? 4 :
                                  (ISSUED_SUB_CYCLE == 1) ? 3 :
                                  (ISSUED_SUB_CYCLE == 2) ? 2 :
                                  (ISSUED_SUB_CYCLE == 3) ? 1 :
                                  0;
    
    //---------------------------------------------------
    //------------------- Definitions -------------------
    //---------------------------------------------------
    
    // registers holding the valid value of the counter
    reg [NUM_RNK * NUM_BG * NUM_BNK - 1 : 0] [TIME_WIDTH - 1 : 0] ras_counter_reg;
    
    // driven continuously by the posedge-sensitive registered counter
    logic [NUM_RNK * NUM_BG * NUM_BNK - 1 : 0] [TIME_WIDTH - 1 : 0] ras_counter_comb;
    
    // next value of the counter
    logic [NUM_RNK * NUM_BG * NUM_BNK - 1 : 0] [TIME_WIDTH - 1 : 0] ras_counter_next_comb;
    
    genvar bt;
    
    //---------------------------------------------------
    //------------- Continuous Assignments --------------
    //---------------------------------------------------
    
    // assign the combinational next tRAS counter to the output
    assign o_ras_counter = ras_counter_reg;
    
    //---------------------------------------------------
    //-------------- Update tRAS Counter ----------------
    //---------------------------------------------------
    
    // assign the registered value to a wire    
    assign ras_counter_comb = ras_counter_reg;
    
    // traverse all counters per bank
    generate
        for(bt = 0; bt < NUM_BNK_TOT ; bt = bt + 1) begin
            always_comb begin

                // if an ACT is issued and is targetting the current bt,
                // reset the counter with tRAS
                if(i_cmd_type == `ACT && {i_cmd_rnk, i_cmd_bg, i_cmd_bnk} == bt)
                   ras_counter_next_comb[bt] <= `tRAS - SUB_CYCLE_OFFSET;
                   
                // if no ACT is issued,
                // decrement the counter by 4
                else 
                   ras_counter_next_comb[bt] <= (ras_counter_comb[bt] > 'd4) ? (ras_counter_comb[bt] - 'd4) : {TIME_WIDTH{1'b0}};
                
            end
        end
    endgenerate
    
    //---------------------------------------------------
    //------------- Update Registers on i_clk -----------
    //---------------------------------------------------
    
    // update/reset arrays
    generate
        for(bt = 0; bt < NUM_BNK_TOT ; bt = bt + 1) begin
            always_ff @(posedge i_clk) begin
                // synchronous active-low reset logic
                if(!i_rstn) begin
                    ras_counter_reg[bt] <= #(TCQ) {TIME_WIDTH{1'b0}};
                end
                // assign the combinational values
                else begin
                    ras_counter_reg[bt] <= #(TCQ) ras_counter_next_comb[bt];
                end
            end
        end
    endgenerate
    
endmodule