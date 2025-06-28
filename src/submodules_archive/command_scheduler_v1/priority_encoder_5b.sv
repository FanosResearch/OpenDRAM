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


module priority_encoder_5b#(
    parameter NUM_BNK_TOT = 16
    )(

        input wire [4:0] input_signal,
        input wire look_ahead,

        output wire [4:0] output_signal

);

    reg [4:0] output_signal_comb;

    assign output_signal = output_signal_comb;
    always @(*) begin
        if(look_ahead) begin
            casex (input_signal)
            5'bxxxx1    : output_signal_comb = 5'b00001;
            5'bxxx10    : output_signal_comb = 5'b00010;
            5'bxx100    : output_signal_comb = 5'b00100;
            5'bx1000    : output_signal_comb = 5'b01000;
            5'b10000    : output_signal_comb = 5'b10000;
            default     : output_signal_comb = 5'b00000;
            endcase
        end else begin
            output_signal_comb = 5'b00000;
        end
    end
endmodule
