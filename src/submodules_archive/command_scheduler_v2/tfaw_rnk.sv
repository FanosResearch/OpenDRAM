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


module tfaw_rnk#(
    
    parameter CMD_TYPE_WIDTH    = 3,
    parameter RNK_SEL_WIDTH     = 1,
    parameter RANK_ID           = 0,
    parameter TIME_WIDTH        = 6,
    parameter TCQ               = 0.1
    
    )(
    
    // module working on the posedge of the clock
    input i_clk,
    // synchronous active-low reset
    input i_rstn,
    
    // command in the first sub-slot that can hold an act
    input [CMD_TYPE_WIDTH - 1 : 0] i_cmd0_type,
    input [RNK_SEL_WIDTH - 1 : 0] i_cmd0_rnk,
    
    // command in the second sub-slot that can hold an act
    input [CMD_TYPE_WIDTH - 1 : 0] i_cmd1_type,
    input [RNK_SEL_WIDTH - 1 : 0] i_cmd1_rnk,
	
	// last faw counter
	output [TIME_WIDTH - 1 : 0] o_faw_counter_last
    );
    
    //---------------------------------------------------
    //------------------- Definitions -------------------
    //---------------------------------------------------
    
    // registers holding the valid value of the counter
    reg [3 : 0] [TIME_WIDTH - 1 : 0] faw_counter_reg;
    
    // driven continuously by the last-level posedge-sensitive registered counter
    logic [3 : 0] [TIME_WIDTH - 1 : 0] faw_counter_comb;
    
    // combinational counter array after an enqueue
    logic [3 : 0] [TIME_WIDTH - 1 : 0] faw_counter_shifted_comb;
    
    // next value of the counter after decrementing by 4
    logic [3 : 0] [TIME_WIDTH - 1 : 0] faw_counter_next_comb;
    
    // offsetted tFAW constraint
    logic [TIME_WIDTH - 1 : 0] offsetted_tFAW_comb;
    
    // faw window genvar
    genvar fw;
    
    //---------------------------------------------------
    //------------- Continuous Assignments --------------
    //---------------------------------------------------
    
    // assign the top of shifted tFAW counter to the outputs
    assign o_faw_counter_last = faw_counter_shifted_comb[3];
    
    // offset tFAW value based on the issue sub-cycle
    assign offsetted_tFAW_comb = (i_cmd0_type == `ACT) ? (`tFAW - 'd3):
                                (i_cmd1_type == `ACT) ? (`tFAW - 'd1):
                                `tFAW;
    
    //---------------------------------------------------
    //-------------- Update tFAW Counter ----------------
    //---------------------------------------------------
    
    // assign the registered value to a wire    
    assign faw_counter_comb = faw_counter_reg;
    
    always_comb begin
    
        // update tfaw counter if an act is issued in any of the two passed sub-slots
        // and is targeting the same rank as the rank this module instantiated for (RANK_ID instantiation parameter)
        if((i_cmd0_type == `ACT && i_cmd0_rnk == RANK_ID) || (i_cmd1_type == `ACT && i_cmd1_rnk == RANK_ID)) begin
        
            // enqueue tFAW value and shift
            faw_counter_shifted_comb[3] <= faw_counter_comb[2];
            faw_counter_shifted_comb[2] <= faw_counter_comb[1];
            faw_counter_shifted_comb[1] <= faw_counter_comb[0];
            faw_counter_shifted_comb[0] <= offsetted_tFAW_comb;
        end   
        
        // if no act to the same rank as RANK_ID is issued,
        // do not enqueue/shift
        else begin
            faw_counter_shifted_comb <= faw_counter_comb;
        end
    end
    
    //---------------------------------------------------
    //-------------- Decrement Counters -----------------
    //---------------------------------------------------
    
    // decrement all elements in the array by 4
    generate
        for(fw = 0; fw < 4 ; fw = fw + 1) begin
            assign faw_counter_next_comb[fw] = (faw_counter_shifted_comb[fw] > 'd4) ? (faw_counter_shifted_comb[fw] - 'd4) : {TIME_WIDTH{1'b0}};
        end
    endgenerate
    
    //---------------------------------------------------
    //------------- Update Registers on i_clk -----------
    //---------------------------------------------------
    
    // update/reset arrays
    generate
        for(fw = 0; fw < 4 ; fw = fw + 1) begin
            always_ff @(posedge i_clk) begin
                // synchronous active-low reset logic
                if(!i_rstn) begin
                    faw_counter_reg[fw] <= #(TCQ) {TIME_WIDTH{1'b0}};
                end
                // assign the combinational values
                else begin
                    faw_counter_reg[fw] <= #(TCQ) faw_counter_next_comb[fw];
                end
            end
        end
    endgenerate
    
endmodule