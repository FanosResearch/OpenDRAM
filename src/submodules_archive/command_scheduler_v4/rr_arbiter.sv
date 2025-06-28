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
    `include "./priority_encoder.sv"
`endif // `ifdef USE_RELATIVE_PATH_INCLUDES


module rr_arbiter#(

    parameter VECTOR_WIDTH  = 8,
    parameter PTR_WIDTH     = 3,
    parameter TCQ           = 0.1

    )(

    input i_clk,
    input i_rstn,

    input [VECTOR_WIDTH - 1 : 0] i_vector,
    output [PTR_WIDTH - 1 : 0] o_winner,
    output o_winner_valid

    );
    
    //---------------------------------------------------
    //------------------- Definitions -------------------
    //---------------------------------------------------
    
    reg [PTR_WIDTH - 1 : 0] rr_ptr_reg;
    wire [PTR_WIDTH - 1 : 0] rr_ptr_next_comb;
    
    wire [VECTOR_WIDTH - 1 : 0] rotated_vector_comb;
    wire [PTR_WIDTH - 1 : 0] p_encoder_out_comb;
    wire p_encoder_out_valid_comb;
    wire [PTR_WIDTH - 1 : 0] winner_comb;
    
    //---------------------------------------------------
    //------------- Continuous Assignments --------------
    //---------------------------------------------------
    
    // assign the winner of the arbiteration to the output
    assign o_winner = winner_comb;
    assign o_winner_valid = p_encoder_out_valid_comb;
    
    //---------------------------------------------------
    //-------------------- Rotation ---------------------
    //---------------------------------------------------
    
    // rotating the input vector to shift element[rr_ptr_reg] to element[0]
    assign rotated_vector_comb = ({i_vector, i_vector} >> rr_ptr_reg);
    
    //---------------------------------------------------
    //---------------- Priority Encoder -----------------
    //---------------------------------------------------
    
    priority_encoder#(
        .VECTOR_WIDTH(VECTOR_WIDTH),
        .PTR_WIDTH(PTR_WIDTH),
        .ENCODER_PRIORITY("LSB_FIRST")
        ) priority_encoder_inst (
        .i_vector(rotated_vector_comb),
        .o_idx(p_encoder_out_comb),
        .o_valid(p_encoder_out_valid_comb)
    );
    
    // calculate index of the winner in the unrotated initial vecotr
    assign winner_comb = rr_ptr_reg + p_encoder_out_comb;
    
    // calculate the next value of the pointer
    assign rr_ptr_next_comb = (p_encoder_out_valid_comb == 1'b1 && winner_comb == 2**PTR_WIDTH-1) ? 0 :
                              (p_encoder_out_valid_comb == 1'b1 && winner_comb != 2**PTR_WIDTH-1) ? winner_comb + 1 :
                              rr_ptr_reg;
                               
    //---------------------------------------------------
    //------------- Update Registers on i_clk -----------
    //---------------------------------------------------
    
    // update/reset round-robin pointer
    always_ff @(posedge i_clk) begin
        // synchronous active-low reset logic
        if(!i_rstn) begin
            rr_ptr_reg <= #(TCQ) 0;
        end
        else begin
            rr_ptr_reg <= #(TCQ) rr_ptr_next_comb;
        end
    end
    
endmodule
