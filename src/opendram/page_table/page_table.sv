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


module page_table #(
		
		NUM_RNK			= 1,
		NUM_BG			= 4,
		NUM_BNK			= 4,
		RNK_WIDTH		= 1,
		BG_WIDTH		= 2,
		BNK_WIDTH		= 2,
		ROW_WIDTH		= 16,
		COL_WIDTH		= 10,
		CMD_TYPE_WIDTH 	= 3,
		
		TCQ				= 100

		)(

    	input				  		rst_n,
		input				  		clk,
		input [CMD_TYPE_WIDTH-1:0]	sel_cmd0,
		input [CMD_TYPE_WIDTH-1:0]	sel_cmd1,
		input [CMD_TYPE_WIDTH-1:0]	sel_cmd2,
		input [CMD_TYPE_WIDTH-1:0]	sel_cmd3,

		input [RNK_WIDTH-1:0] sel_rnk0,
		input [RNK_WIDTH-1:0] sel_rnk1,
		input [RNK_WIDTH-1:0] sel_rnk2,
		input [RNK_WIDTH-1:0] sel_rnk3,

		input [BG_WIDTH-1:0]  sel_bg0,
		input [BG_WIDTH-1:0]  sel_bg1,
		input [BG_WIDTH-1:0]  sel_bg2,
		input [BG_WIDTH-1:0]  sel_bg3,

		input [BNK_WIDTH-1:0] sel_bnk0,
		input [BNK_WIDTH-1:0] sel_bnk1,
		input [BNK_WIDTH-1:0] sel_bnk2,
		input [BNK_WIDTH-1:0] sel_bnk3,

		input [ROW_WIDTH-1:0] sel_row0,
		input [ROW_WIDTH-1:0] sel_row1,
		input [ROW_WIDTH-1:0] sel_row2,
		input [ROW_WIDTH-1:0] sel_row3,

    	input                 ref_rnk_flag,
		input [RNK_WIDTH-1:0] ref_rnk_rnk,

		output [NUM_RNK*NUM_BG*NUM_BNK-1:0] idle_flag,
		output [ROW_WIDTH-1:0]	 			row_bnk [NUM_RNK*NUM_BG*NUM_BNK-1:0]
	);
	
	reg	 		             reg_idle_flag [NUM_RNK*NUM_BG*NUM_BNK-1:0]; 
	reg	 [ROW_WIDTH-1:0]	 reg_row_bnk [NUM_RNK*NUM_BG*NUM_BNK-1:0];  

	genvar i;
	generate
	    for(i = 0;i < (NUM_RNK*NUM_BG*NUM_BNK); i = i + 1) begin
	    	assign idle_flag [i] = reg_idle_flag[i];
	    	assign row_bnk [i] = reg_row_bnk[i];
	    end
	endgenerate

	integer ii;

	always @(posedge clk) // rst at the begining, initialize the idle_bnk flag by zeros
    
    	if(~rst_n) begin
    	    for (ii=0; ii < (NUM_RNK*NUM_BG*NUM_BNK); ii= ii+1) begin
    	        reg_idle_flag [ii] <= #(TCQ) 0;
    	        reg_row_bnk [ii] <= #(TCQ) 0;
    	    end
    	end
    
    	else begin
		
    	    if (ref_rnk_flag) begin // per rank refresh case
    	        for(ii=0; ii < NUM_BG*NUM_BNK; ii= ii+1) begin
    	            reg_idle_flag [ref_rnk_rnk+ii] <= #(TCQ) 0;
    	            reg_row_bnk [ref_rnk_rnk+ii] <= #(TCQ) 0;
    	        end
    	    end
	
		   	if (sel_cmd0 == `PRE) begin // PRE cmd0 case, change to idle bank
    	        reg_idle_flag [{sel_rnk0,sel_bg0,sel_bnk0}] <= #(TCQ) 0;
    	        reg_row_bnk [{sel_rnk0,sel_bg0,sel_bnk0}] <=  #(TCQ) 0;
		   	end

    		if (sel_cmd1 == `PRE) begin
    		    reg_idle_flag [{sel_rnk1,sel_bg1,sel_bnk1}] <= #(TCQ) 0;
    		    reg_row_bnk [{sel_rnk1,sel_bg1,sel_bnk1}] <= #(TCQ) 0;
			end
	
			if (sel_cmd2 == `PRE) begin
        		reg_idle_flag [{sel_rnk2,sel_bg2,sel_bnk2}] <= #(TCQ) 0;
        		reg_row_bnk [{sel_rnk2,sel_bg2,sel_bnk2}] <= #(TCQ) 0;
			end
	
    		if (sel_cmd3 == `PRE) begin
    		    reg_idle_flag [{sel_rnk3,sel_bg3,sel_bnk3}] <= #(TCQ) 0;
    		    reg_row_bnk [{sel_rnk3,sel_bg3,sel_bnk3}] <= #(TCQ) 0;
			end

	
			if (sel_cmd1 == `ACT && !(ref_rnk_flag && ref_rnk_rnk == sel_rnk1)) begin
        		reg_idle_flag [{sel_rnk1,sel_bg1,sel_bnk1}] <= #(TCQ) 1;
        		reg_row_bnk [{sel_rnk1,sel_bg1,sel_bnk1}] <= #(TCQ) sel_row1;
			end

			if (sel_cmd3 == `ACT && !(ref_rnk_flag && ref_rnk_rnk == sel_rnk3)) begin
    		    reg_idle_flag [{sel_rnk3,sel_bg3,sel_bnk3}] <= #(TCQ) 1;
    		    reg_row_bnk [{sel_rnk3,sel_bg3,sel_bnk3}] <= #(TCQ) sel_row3;
			end
	end
endmodule