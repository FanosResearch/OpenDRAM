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


module priority_encoder#(

    parameter VECTOR_WIDTH      = 8,
    parameter PTR_WIDTH         = 3,
    parameter ENCODER_PRIORITY  = "LSB_FIRST"
    
    )(
    
    input [VECTOR_WIDTH - 1 : 0] i_vector,
    output [PTR_WIDTH - 1 : 0] o_idx,
    output o_valid

    );
    
    assign o_valid = (i_vector != {VECTOR_WIDTH{1'b0}}) ? 1'b1 : 1'b0;
    
    generate
       
       // ------------------ 2-Bit Priority Encoder ------------------
       
       if(VECTOR_WIDTH == 2) begin 
       
            if(ENCODER_PRIORITY == "LSB_FIRST") begin : lsb_first
                assign o_idx = (i_vector[0] == 1'b1) ? 1'd0 :
                               (i_vector[1] == 1'b1) ? 1'd1 :
                               1'd0;
            end
            else if(ENCODER_PRIORITY == "MSB_FIRST") begin : msb_first
                assign o_idx = (i_vector[1] == 1'b1) ? 1'd1 :
                               (i_vector[0] == 1'b1) ? 1'd0 :
                               1'd1;
            end
       end
       
       // ------------------ 4-Bit Priority Encoder ------------------
       
       if(VECTOR_WIDTH == 4) begin 
       
            if(ENCODER_PRIORITY == "LSB_FIRST") begin : lsb_first
                assign o_idx = (i_vector[0] == 1'b1) ? 2'd0 :
                            (i_vector[1] == 1'b1) ? 2'd1 :
                            (i_vector[2] == 1'b1) ? 2'd2 :
                            (i_vector[3] == 1'b1) ? 2'd3 :
                            2'd0;
            end
            else if(ENCODER_PRIORITY == "MSB_FIRST") begin : msb_first
                assign o_idx = (i_vector[3] == 1'b1) ? 2'd3 :
                            (i_vector[2] == 1'b1) ? 2'd2 :
                            (i_vector[1] == 1'b1) ? 2'd1 :
                            (i_vector[0] == 1'b1) ? 2'd0 :
                            2'd3;
            end
       end
       
       // ------------------ 8-Bit Priority Encoder ------------------
       
       else if(VECTOR_WIDTH == 8) begin 
       
            if(ENCODER_PRIORITY == "LSB_FIRST") begin : lsb_first
                assign o_idx = (i_vector[0] == 1'b1) ? 3'd0 :
                            (i_vector[1] == 1'b1) ? 3'd1 :
                            (i_vector[2] == 1'b1) ? 3'd2 :
                            (i_vector[3] == 1'b1) ? 3'd3 :
                            (i_vector[4] == 1'b1) ? 3'd4 :
                            (i_vector[5] == 1'b1) ? 3'd5 :
                            (i_vector[6] == 1'b1) ? 3'd6 :
                            (i_vector[7] == 1'b1) ? 3'd7 :
                            3'd0;
            end
            else if(ENCODER_PRIORITY == "MSB_FIRST") begin : msb_first
                assign o_idx = (i_vector[7] == 1'b1) ? 3'd7 :
                            (i_vector[6] == 1'b1) ? 3'd6 :
                            (i_vector[5] == 1'b1) ? 3'd5 :
                            (i_vector[4] == 1'b1) ? 3'd4 :
                            (i_vector[3] == 1'b1) ? 3'd3 :
                            (i_vector[2] == 1'b1) ? 3'd2 :
                            (i_vector[1] == 1'b1) ? 3'd1 :
                            (i_vector[0] == 1'b1) ? 3'd0 :
                            3'd7;
            end
       end
       
       // ------------------ 16-Bit Priority Encoder ------------------
       
       else if(VECTOR_WIDTH == 16) begin 
       
            if(ENCODER_PRIORITY == "LSB_FIRST") begin : lsb_first
                assign o_idx = (i_vector[0] == 1'b1) ? 4'd0 :
                            (i_vector[1] == 1'b1) ? 4'd1 :
                            (i_vector[2] == 1'b1) ? 4'd2 :
                            (i_vector[3] == 1'b1) ? 4'd3 :
                            (i_vector[4] == 1'b1) ? 4'd4 :
                            (i_vector[5] == 1'b1) ? 4'd5 :
                            (i_vector[6] == 1'b1) ? 4'd6 :
                            (i_vector[7] == 1'b1) ? 4'd7 :
                            (i_vector[8] == 1'b1) ? 4'd8 :
                            (i_vector[9] == 1'b1) ? 4'd9 :
                            (i_vector[10] == 1'b1) ? 4'd10 :
                            (i_vector[11] == 1'b1) ? 4'd11 :
                            (i_vector[12] == 1'b1) ? 4'd12 :
                            (i_vector[13] == 1'b1) ? 4'd13 :
                            (i_vector[14] == 1'b1) ? 4'd14 :
                            (i_vector[15] == 1'b1) ? 4'd15 :
                            4'd0;
            end
            else if(ENCODER_PRIORITY == "MSB_FIRST") begin : msb_first
                assign o_idx = (i_vector[15] == 1'b1) ? 4'd15 :
                            (i_vector[14] == 1'b1) ? 4'd14 :
                            (i_vector[13] == 1'b1) ? 4'd13 :
                            (i_vector[12] == 1'b1) ? 4'd12 :
                            (i_vector[11] == 1'b1) ? 4'd11 :
                            (i_vector[10] == 1'b1) ? 4'd10 :
                            (i_vector[9] == 1'b1) ? 4'd9 :
                            (i_vector[8] == 1'b1) ? 4'd8 :
                            (i_vector[7] == 1'b1) ? 4'd7 :
                            (i_vector[6] == 1'b1) ? 4'd6 :
                            (i_vector[5] == 1'b1) ? 4'd5 :
                            (i_vector[4] == 1'b1) ? 4'd4 :
                            (i_vector[3] == 1'b1) ? 4'd3 :
                            (i_vector[2] == 1'b1) ? 4'd2 :
                            (i_vector[1] == 1'b1) ? 4'd1 :
                            (i_vector[0] == 1'b1) ? 4'd0 :
                            4'd15;
            end
       end
       
    endgenerate
endmodule
