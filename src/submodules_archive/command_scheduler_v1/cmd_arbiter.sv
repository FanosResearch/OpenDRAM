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

module cmd_arbiter#(
        parameter NUM_BNK_TOT = 16,
        parameter QTYPE_LSB = 0,
        parameter QTYPE_MSB = 0,
        parameter CMD_TYPE_WIDTH = 3,
        parameter QWIDTH = 1,
        parameter CARRY8 = "DISABLE",
        parameter MODE = "NAND"
    )(
        
        input wire [NUM_BNK_TOT-1:0] final_flag, // 1 is valid
        input wire [QWIDTH-1:0] cmd_queue [0:NUM_BNK_TOT-1], // command queue 
        input wire [NUM_BNK_TOT-1:0] rr_ptr_i, // 1 is valid
        output wire [NUM_BNK_TOT-1:0] rr_ptr_o,
        output wire [QWIDTH-1:0] cmd_pick,
        input wire [NUM_BNK_TOT-1:0] bank_flag_i,
        output wire [NUM_BNK_TOT-1:0] sel_bank,
        output wire [NUM_BNK_TOT-1:0] bank_flag_o // 1 is valid
    );

    wire [NUM_BNK_TOT-1:0] priority_decoder_input [0:NUM_BNK_TOT-1];
    wire [NUM_BNK_TOT-1:0] priority_decoder [0:NUM_BNK_TOT-1];
    wire [NUM_BNK_TOT-1:0] priority_decoder_o [0:NUM_BNK_TOT-1];

    wire [NUM_BNK_TOT-1:0] sel_ptr_tmp1 [0:NUM_BNK_TOT-1];
    wire [NUM_BNK_TOT-1:0] sel_ptr_tmp2 [0:NUM_BNK_TOT-1];
    wire [NUM_BNK_TOT-1:0] sel_ptr; // 0 is valid

    reg  [NUM_BNK_TOT-1:0] rr_ptr_o_r;


    wire [QWIDTH-1:0] cmd_pick_tmp1 [0:NUM_BNK_TOT-1];
    wire [NUM_BNK_TOT-1:0] cmd_pick_tmp2 [0:QWIDTH-1];

    wire [CMD_TYPE_WIDTH-1:0] type_pick;

    genvar bt, i, j;

    generate
    if(CARRY8 == "ENABLE") begin
        priority_encoder#(
            .NUM_BNK_TOT(NUM_BNK_TOT),
            .MODE(MODE)
        ) priority_encoder_inst(
            .priority_decoder_input(final_flag),
            .priority_decoder_output(priority_decoder_o)
        );
    end
    else if(CARRY8 == "DISABLE") begin
        for(bt = 0; bt< NUM_BNK_TOT; bt++)
        begin : priority_encoder_bank
            // generating inputs and outputs with proper order for priority decoder
    
            for(i = bt; i<NUM_BNK_TOT; i++)
            begin
                assign priority_decoder_input[bt][i-bt] = final_flag[i];

                assign priority_decoder_o[bt][i] = priority_decoder[bt][i-bt];
            end
            for(i = 0; i<bt; i++)
            begin
                assign priority_decoder_input[bt][i+(NUM_BNK_TOT-bt)] = final_flag[i];

                assign priority_decoder_o[bt][i] = priority_decoder[bt][i+(NUM_BNK_TOT-bt)];
            end
            // priority decoder output
            for (i=0; i<NUM_BNK_TOT; i++) 
            begin : priority_encoder_bit
            if(i==0) begin
                assign priority_decoder[bt][0] = priority_decoder_input[bt][0];    
            end
            else begin
                assign priority_decoder[bt][i] = ~(|{(~priority_decoder_input[bt][i]), priority_decoder_input[bt][i-1:0]});
            end
            end    
        end
    end
        // Determining sel ptr, 0 is valid
    for(j = 0; j< NUM_BNK_TOT; j++)
    begin : sel_ptr_bank
        for ( i=0 ; i<NUM_BNK_TOT ; i++ ) begin
            assign sel_ptr_tmp1[j][i] = priority_decoder_o[j][i] & rr_ptr_i[j];
            assign sel_ptr_tmp2[j][i] = sel_ptr_tmp1[i][j];
            assign sel_ptr[i] = |sel_ptr_tmp2[i];
        end
    end
    endgenerate

    // generating new round robin pointer, comb logic
    always @(*) begin
        if(type_pick == `NOP) begin
            rr_ptr_o_r = rr_ptr_i;
        end else begin
            rr_ptr_o_r = {sel_ptr[NUM_BNK_TOT-2:0], sel_ptr[NUM_BNK_TOT-1]};
        end
    end
    assign rr_ptr_o = rr_ptr_o_r;


    // picking a command from the command queue
    generate
    for(bt = 0; bt < NUM_BNK_TOT ; bt++)
    begin : cmd_pick_bank
        for(i = 0; i< QWIDTH; i++)
        begin : cmd_pick_bit
            assign cmd_pick_tmp1[bt][i] = cmd_queue[bt][i] & sel_ptr[bt];
            assign cmd_pick_tmp2[i][bt] = cmd_pick_tmp1[bt][i];
            assign cmd_pick[i] = |cmd_pick_tmp2[i];
        end
    end
    endgenerate
    
    assign type_pick = cmd_pick[QTYPE_MSB:QTYPE_LSB];

    // assigning bank flag
    assign bank_flag_o = sel_bank & bank_flag_i;
    assign sel_bank = ~sel_ptr;

endmodule
