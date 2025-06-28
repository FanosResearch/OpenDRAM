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
    `include "./constraints_calculator.sv"
    `include "./tfaw_rnk.sv"
`endif // `ifdef USE_RELATIVE_PATH_INCLUDES


module time_machinery
#(	parameter	 // protocol DDR4_8Gb_x8, values for 2400U

			NUM_RNK		          = 1,
			NUM_BG		          = 4,
			NUM_BNK		          = 4,
			RNK_SEL_WIDTH	          = 1,
			BG_SEL_WIDTH	          = 2,
			BNK_SEL_WIDTH	          = 2,
			CMD_TYPE_WIDTH	          = 3,
            NOP_BITS	          = 3'b000,
            PRE_BITS	          = 3'b001,
            ACT_BITS	          = 3'b010,
            RD_BITS	              = 3'b011,
            WR_BITS	              = 3'b100,
            RDA_BITS	          = 3'b101,
            WRA_BITS	          = 3'b110,
            PREA_BITS	          = 3'b111,
            TIME_CONSTRAINT_WIDTH = 8
)
(
   
    input wire	 [CMD_TYPE_WIDTH-1:0]				sel_cmd,
	input wire	 [RNK_SEL_WIDTH-1:0]			    sel_rnk,
	input wire	 [BG_SEL_WIDTH-1:0]					sel_bg,
	input wire	 [BNK_SEL_WIDTH-1:0]				sel_bnk,
	
	input wire [TIME_CONSTRAINT_WIDTH-1:0]      cmd_counter_i    [NUM_RNK*NUM_BG*NUM_BNK-1:0][3:0],
	input wire [TIME_CONSTRAINT_WIDTH-1:0]      faw_counter_i    [NUM_RNK-1:0][3:0],
    input wire [3:0]                            faw_valid_i     [NUM_RNK-1:0],
    
	output reg [TIME_CONSTRAINT_WIDTH-1:0]      cmd_counter_o   [NUM_RNK*NUM_BG*NUM_BNK-1:0][3:0],
	output reg [TIME_CONSTRAINT_WIDTH-1:0]      faw_counter_o   [NUM_RNK-1:0][3:0],
    output reg [3:0]                            faw_valid_o     [NUM_RNK-1:0]

    );
    
    localparam table_entries = NUM_RNK*NUM_BG*NUM_BNK;
    localparam table_entries_bits = RNK_SEL_WIDTH + BG_SEL_WIDTH + BNK_SEL_WIDTH ;
    
    
    
// same_bnk, same_bg, and same_rnk flags
integer same_bnk;
integer same_bg;
integer same_rnk;
integer PRE_const;
integer ACT_const;
integer RD_const;
integer WR_const;
integer i;



genvar gen_r;
generate
for ( gen_r=0 ; gen_r<NUM_RNK; gen_r = gen_r + 1) 
begin
   tfaw_rnk #(
    .CMD_TYPE_WIDTH(CMD_TYPE_WIDTH),
    .ACT_BITS(ACT_BITS),
    .TIME_CONSTRAINT_WIDTH(TIME_CONSTRAINT_WIDTH),
    .tFAW (`tFAW)
    )u_tfaw_rnk(
    .sel_cmd(sel_cmd),
    .faw_counter_i(faw_counter_i[gen_r]),
    .faw_valid_i(faw_valid_i[gen_r]),
    .faw_counter_o(faw_counter_o[gen_r]),
    .faw_valid_o(faw_valid_o[gen_r])
    ); 
end
endgenerate


always @(*) //updates cmd_counter_o
begin
    for (i = 0 ; i < table_entries ; i = i+1)
    begin
        same_bnk = ({sel_rnk,sel_bg,sel_bnk} == i)? 1'b1:1'b0;
        same_bg = ({sel_rnk,sel_bg} == i[table_entries_bits-1:BNK_SEL_WIDTH]) ? 1'b1:1'b0;
        same_rnk = ({sel_rnk} == i[table_entries_bits-1:BNK_SEL_WIDTH+BG_SEL_WIDTH]) ? 1'b1:1'b0;
        calculate_constraints (sel_cmd, same_bnk, same_bg, same_rnk, PRE_const, ACT_const, RD_const, WR_const);
        cmd_counter_o[i][0] = (cmd_counter_i[i][0] < PRE_const)? PRE_const: cmd_counter_i[i][0]; // update banks counters
        cmd_counter_o[i][1] = (cmd_counter_i[i][1] < ACT_const)? ACT_const: cmd_counter_i[i][1];
        cmd_counter_o[i][2] = (cmd_counter_i[i][2] < RD_const)?  RD_const : cmd_counter_i[i][2];
        cmd_counter_o[i][3] = (cmd_counter_i[i][3] < WR_const)?  WR_const : cmd_counter_i[i][3];

        cmd_counter_o[i][0] = (cmd_counter_o[i][0] > 0)? (cmd_counter_o[i][0]-1) : 0; // decrement bank counters
        cmd_counter_o[i][1] = (cmd_counter_o[i][1] > 0)? (cmd_counter_o[i][1]-1) : 0;
        cmd_counter_o[i][2] = (cmd_counter_o[i][2] > 0)? (cmd_counter_o[i][2]-1) : 0;
        cmd_counter_o[i][3] = (cmd_counter_o[i][3] > 0)? (cmd_counter_o[i][3]-1) : 0;

    end
end

endmodule
