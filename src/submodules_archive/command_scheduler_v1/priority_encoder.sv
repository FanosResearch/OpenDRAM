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
    `include "./priority_encoder_5b.sv"
`endif // `ifdef USE_RELATIVE_PATH_INCLUDES


module priority_encoder#(
    parameter NUM_BNK_TOT = 16,
    parameter MODE = "PARALLEL"
)(
    input wire [NUM_BNK_TOT-1:0] priority_decoder_input,
    output wire [NUM_BNK_TOT-1:0] priority_decoder_output [0:NUM_BNK_TOT-1]
);


wire [NUM_BNK_TOT-1:0] priority_decoder_input_reorder [0:NUM_BNK_TOT-1];
wire [NUM_BNK_TOT-1:0] priority_decoder_input_reorder_not [0:NUM_BNK_TOT-1];

wire [NUM_BNK_TOT-1:0] priority_decoder_output_reorder [0:NUM_BNK_TOT-1];
wire [NUM_BNK_TOT-1:0] priority_decoder_output_reorder_carry [0:NUM_BNK_TOT-1];

wire [7:0] carry [NUM_BNK_TOT-1:0][NUM_BNK_TOT-1:0];
wire [7:0] carry_twosc [NUM_BNK_TOT-1:0];
wire [7:0] carry_out [NUM_BNK_TOT-1:0][NUM_BNK_TOT-1:1];






genvar i, bt;

generate
    if(MODE == "NAND") begin
    for(bt = 0; bt< NUM_BNK_TOT; bt++) 
        begin : priority_encoder_bank
            // generating inputs and outputs with proper order for priority decoder

            // reordering input and output
            for(i = bt; i<NUM_BNK_TOT; i++)
            begin
                assign priority_decoder_input_reorder[bt][i-bt] = priority_decoder_input[i];

                assign priority_decoder_output[bt][i] = priority_decoder_output_reorder[bt][i-bt];
            end
            for(i = 0; i<bt; i++)
            begin
                assign priority_decoder_input_reorder[bt][i+(NUM_BNK_TOT-bt)] = priority_decoder_input[i];

                assign priority_decoder_output[bt][i] = priority_decoder_output_reorder[bt][i+(NUM_BNK_TOT-bt)];
            end
            // priority decoder output
            for (i=0; i<NUM_BNK_TOT; i++) 
            begin : priority_encoder_bit
            if(i == 0) begin
                assign priority_decoder_output_reorder[bt][0] = priority_decoder_input_reorder[bt][0];
            end else if (i<7)begin
                CARRY8 #(
                    .CARRY_TYPE("SINGLE_CY8")  // 8-bit or dual 4-bit carry (DUAL_CY4, SINGLE_CY8)
                ) CARRY8_inst (
                    .CO(carry_out[bt][i]),         // 8-bit output: Carry-out
                    .O(),           // 8-bit output: Carry chain XOR data out
                    .CI(1'b0),         // 1-bit input: Lower Carry-In
                    .CI_TOP(1'b0), // 1-bit input: Upper Carry-In
                    .DI(8'b1111_1111),         // 8-bit input: Carry-MUX data in
                    .S({{(7-i){1'b1}}, {(~priority_decoder_input_reorder[bt][i]), priority_decoder_input_reorder[bt][i-1:0]}})            // 8-bit input: Carry-mux select
                );
                assign priority_decoder_output_reorder[bt][i] = carry_out[bt][i][i];       
            end else if (i == 7) begin
                CARRY8 #(
                    .CARRY_TYPE("SINGLE_CY8")  // 8-bit or dual 4-bit carry (DUAL_CY4, SINGLE_CY8)
                ) CARRY8_inst (
                    .CO(carry_out[bt][7]),         // 8-bit output: Carry-out
                    .O(),           // 8-bit output: Carry chain XOR data out
                    .CI(1'b0),         // 1-bit input: Lower Carry-In
                    .CI_TOP(1'b0), // 1-bit input: Upper Carry-In
                    .DI(8'b1111_1111),         // 8-bit input: Carry-MUX data in
                    .S({(~priority_decoder_input_reorder[bt][7]), priority_decoder_input_reorder[bt][6:0]})            // 8-bit input: Carry-mux select
                );
                assign priority_decoder_output_reorder[bt][7] = carry_out[bt][7][7];
            end else if (i == 8) begin
                CARRY8 #(
                    .CARRY_TYPE("SINGLE_CY8")  // 8-bit or dual 4-bit carry (DUAL_CY4, SINGLE_CY8)
                ) CARRY8_inst0 (
                    .CO(carry[bt][8]),         // 8-bit output: Carry-out
                    .O(),           // 8-bit output: Carry chain XOR data out
                    .CI(1'b0),         // 1-bit input: Lower Carry-In
                    .CI_TOP(1'b0), // 1-bit input: Upper Carry-In
                    .DI(8'b1111_1111),         // 8-bit input: Carry-MUX data in
                    .S(priority_decoder_input_reorder[bt][7:0])            // 8-bit input: Carry-mux select
                );
                CARRY8 #(
                    .CARRY_TYPE("SINGLE_CY8")  // 8-bit or dual 4-bit carry (DUAL_CY4, SINGLE_CY8)
                ) CARRY8_inst1 (
                    .CO(carry_out[bt][8]),         // 8-bit output: Carry-out
                    .O(),           // 8-bit output: Carry chain XOR data out
                    .CI(carry[bt][8][7]),         // 1-bit input: Lower Carry-In
                    .CI_TOP(1'b0), // 1-bit input: Upper Carry-In
                    .DI(8'b1111_1111),         // 8-bit input: Carry-MUX data in
                    .S({{(7){1'b1}}, ~priority_decoder_input_reorder[bt][8]})            // 8-bit input: Carry-mux select
                );
                assign priority_decoder_output_reorder[bt][8] = carry_out[bt][8][0];
            end else if (i < 15) begin
                CARRY8 #(
                    .CARRY_TYPE("SINGLE_CY8")  // 8-bit or dual 4-bit carry (DUAL_CY4, SINGLE_CY8)
                ) CARRY8_inst0 (
                    .CO(carry[bt][i]),         // 8-bit output: Carry-out
                    .O(),           // 8-bit output: Carry chain XOR data out
                    .CI(1'b0),         // 1-bit input: Lower Carry-In
                    .CI_TOP(1'b0), // 1-bit input: Upper Carry-In
                    .DI(8'b1111_1111),         // 8-bit input: Carry-MUX data in
                    .S({priority_decoder_input_reorder[bt][7:0]})            // 8-bit input: Carry-mux select
                );
                CARRY8 #(
                    .CARRY_TYPE("SINGLE_CY8")  // 8-bit or dual 4-bit carry (DUAL_CY4, SINGLE_CY8)
                ) CARRY8_inst1 (
                    .CO(carry_out[bt][i]),         // 8-bit output: Carry-out
                    .O(),           // 8-bit output: Carry chain XOR data out
                    .CI(carry[bt][i][7]),         // 1-bit input: Lower Carry-In
                    .CI_TOP(1'b0), // 1-bit input: Upper Carry-In
                    .DI(8'b1111_1111),         // 8-bit input: Carry-MUX data in
                    .S({{(15-i){1'b1}}, {(~priority_decoder_input_reorder[bt][i]), priority_decoder_input_reorder[bt][i-1:8]}})            // 8-bit input: Carry-mux select
                );
                assign priority_decoder_output_reorder[bt][i] = carry_out[bt][i][i-8];
            end else if (i == 15) begin
                CARRY8 #(
                    .CARRY_TYPE("SINGLE_CY8")  // 8-bit or dual 4-bit carry (DUAL_CY4, SINGLE_CY8)
                ) CARRY8_inst0 (
                    .CO(carry[bt][15]),         // 8-bit output: Carry-out
                    .O(),           // 8-bit output: Carry chain XOR data out
                    .CI(1'b0),         // 1-bit input: Lower Carry-In
                    .CI_TOP(1'b0), // 1-bit input: Upper Carry-In
                    .DI(8'b1111_1111),         // 8-bit input: Carry-MUX data in
                    .S({priority_decoder_input_reorder[bt][7:0]})            // 8-bit input: Carry-mux select
                );
                CARRY8 #(
                    .CARRY_TYPE("SINGLE_CY8")  // 8-bit or dual 4-bit carry (DUAL_CY4, SINGLE_CY8)
                ) CARRY8_inst1 (
                    .CO(carry_out[bt][i]),         // 8-bit output: Carry-out
                    .O(),           // 8-bit output: Carry chain XOR data out
                    .CI(carry[bt][15][7]),         // 1-bit input: Lower Carry-In
                    .CI_TOP(1'b0), // 1-bit input: Upper Carry-In
                    .DI(8'b1111_1111),         // 8-bit input: Carry-MUX data in
                    .S({(~priority_decoder_input_reorder[bt][15]), priority_decoder_input_reorder[bt][14:8]})            // 8-bit input: Carry-mux select
                );
                assign priority_decoder_output_reorder[bt][i] = carry_out[bt][i][7];
            end   
            end
        end
    end else if(MODE == "TWOS") begin
        for(bt = 0; bt< NUM_BNK_TOT; bt++) 
        begin : priority_encoder_bank
            // generating inputs and outputs with proper order for priority decoder

            // reordering input and output
            for(i = bt; i<NUM_BNK_TOT; i++)
            begin
                assign priority_decoder_input_reorder[bt][i-bt] = priority_decoder_input[i];

                assign priority_decoder_output[bt][i] = priority_decoder_output_reorder[bt][i-bt];
            end
            for(i = 0; i<bt; i++)
            begin
                assign priority_decoder_input_reorder[bt][i+(NUM_BNK_TOT-bt)] = priority_decoder_input[i];

                assign priority_decoder_output[bt][i] = priority_decoder_output_reorder[bt][i+(NUM_BNK_TOT-bt)];
            end

            assign priority_decoder_output_reorder[bt] = (priority_decoder_input_reorder[bt] & (-priority_decoder_input_reorder[bt]));
        end
    end else if(MODE == "TWOS_C") begin
        for(bt = 0; bt< NUM_BNK_TOT; bt++) 
        begin : priority_encoder_bank
            // generating inputs and outputs with proper order for priority decoder

            // reordering input and output
            for(i = bt; i<NUM_BNK_TOT; i++)
            begin
                assign priority_decoder_input_reorder[bt][i-bt] = priority_decoder_input[i];

                assign priority_decoder_output[bt][i] = priority_decoder_output_reorder[bt][i-bt];
            end
            for(i = 0; i<bt; i++)
            begin
                assign priority_decoder_input_reorder[bt][i+(NUM_BNK_TOT-bt)] = priority_decoder_input[i];

                assign priority_decoder_output[bt][i] = priority_decoder_output_reorder[bt][i+(NUM_BNK_TOT-bt)];
            end

            assign priority_decoder_input_reorder_not[bt] = ~priority_decoder_input_reorder[bt];

            CARRY8 #(
                    .CARRY_TYPE("SINGLE_CY8")  // 8-bit or dual 4-bit carry (DUAL_CY4, SINGLE_CY8)
                ) CARRY8_inst0 (
                    .CO(carry_twosc[bt]),         // 8-bit output: Carry-out
                    .O(priority_decoder_output_reorder_carry[bt][7:0]),           // 8-bit output: Carry chain XOR data out
                    .CI(1'b1),         // 1-bit input: Lower Carry-In
                    .CI_TOP(1'b0), // 1-bit input: Upper Carry-In
                    .DI(8'b0000_0000),         // 8-bit input: Carry-MUX data in
                    .S(priority_decoder_input_reorder_not[bt][7:0])            // 8-bit input: Carry-mux select
                );

            CARRY8 #(
                    .CARRY_TYPE("SINGLE_CY8")  // 8-bit or dual 4-bit carry (DUAL_CY4, SINGLE_CY8)
                ) CARRY8_inst1 (
                    .CO(),         // 8-bit output: Carry-out
                    .O(priority_decoder_output_reorder_carry[bt][15:8]),           // 8-bit output: Carry chain XOR data out
                    .CI(carry_twosc[bt][7]),         // 1-bit input: Lower Carry-In
                    .CI_TOP(1'b0), // 1-bit input: Upper Carry-In
                    .DI(8'b0000_0000),         // 8-bit input: Carry-MUX data in
                    .S(priority_decoder_input_reorder_not[bt][15:8])            // 8-bit input: Carry-mux select
                );

            assign priority_decoder_output_reorder[bt] = (priority_decoder_input_reorder[bt] & priority_decoder_output_reorder_carry[bt]);
        end
    end else if(MODE == "PARALLEL") begin
        
        wire look_ahead_1[NUM_BNK_TOT-1:0];
        wire look_ahead_2[NUM_BNK_TOT-1:0];
        wire look_ahead_3[NUM_BNK_TOT-1:0];
        wire look_ahead_4[NUM_BNK_TOT-1:0];

        wire [4:0] look_ahead_priority[NUM_BNK_TOT-1:0];


        for(bt = 0; bt< NUM_BNK_TOT; bt++) 
        begin : priority_encoder_bank
            // generating inputs and outputs with proper order for priority decoder

            // reordering input and output
            for(i = bt; i<NUM_BNK_TOT; i++)
            begin
                assign priority_decoder_input_reorder[bt][i-bt] = priority_decoder_input[i];

                assign priority_decoder_output[bt][i] = priority_decoder_output_reorder[bt][i-bt];
            end
            for(i = 0; i<bt; i++)
            begin
                assign priority_decoder_input_reorder[bt][i+(NUM_BNK_TOT-bt)] = priority_decoder_input[i];

                assign priority_decoder_output[bt][i] = priority_decoder_output_reorder[bt][i+(NUM_BNK_TOT-bt)];
            end
            // priority decoder output
            
            assign look_ahead_1[bt] = |(priority_decoder_input_reorder[bt][4:0]);
            assign look_ahead_2[bt] = |(priority_decoder_input_reorder[bt][9:5]);
            assign look_ahead_3[bt] = |(priority_decoder_input_reorder[bt][14:10]);
            assign look_ahead_4[bt] = priority_decoder_input_reorder[bt][15];


            priority_encoder_5b#(
                .NUM_BNK_TOT(NUM_BNK_TOT)
            ) priority_encoder_5b_inst0_lvl1(
                .input_signal({1'b0, look_ahead_4[bt], look_ahead_3[bt], look_ahead_2[bt], look_ahead_1[bt]}),
                .output_signal(look_ahead_priority[bt]),
                .look_ahead(1'b1)
            );


        priority_encoder_5b#(
            .NUM_BNK_TOT(NUM_BNK_TOT)
        ) priority_encoder_5b_inst0_lvl2(
            .input_signal(priority_decoder_input_reorder[bt][4:0]),
            .output_signal(priority_decoder_output_reorder[bt][4:0]),
            .look_ahead(look_ahead_priority[bt][0])
        );


        priority_encoder_5b#(
            .NUM_BNK_TOT(NUM_BNK_TOT)
        ) priority_encoder_5b_inst1_lvl2(
            .input_signal(priority_decoder_input_reorder[bt][9:5]),
            .output_signal(priority_decoder_output_reorder[bt][9:5]),
            .look_ahead(look_ahead_priority[bt][1])
        );

        priority_encoder_5b#(
            .NUM_BNK_TOT(NUM_BNK_TOT)
        ) priority_encoder_5b_inst2_lvl2(
            .input_signal(priority_decoder_input_reorder[bt][14:10]),
            .output_signal(priority_decoder_output_reorder[bt][14:10]),
            .look_ahead(look_ahead_priority[bt][2])
        );

        assign priority_decoder_output_reorder[bt][15] = look_ahead_priority[bt][3];


        end

    end

endgenerate


endmodule
