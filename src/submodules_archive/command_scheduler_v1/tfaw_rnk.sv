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


module tfaw_rnk
#(	parameter	 // protocol DDR4_8Gb_x8, values for 2400U
            CMD_TYPE_WIDTH	          = 3,
            ACT_BITS	          = 3'b010,
            TIME_CONSTRAINT_WIDTH = 8,
            tFAW                  = 36
)
(
    input wire [CMD_TYPE_WIDTH-1:0]			   sel_cmd,
    input wire [TIME_CONSTRAINT_WIDTH-1:0] faw_counter_i    [3:0],
    input wire [3:0]                       faw_valid_i,
	
	output reg [TIME_CONSTRAINT_WIDTH-1:0]  faw_counter_o   [3:0],
    output reg [3:0]                        faw_valid_o     
	
    );
    
    integer j;
    
always@(*)
begin

    if(sel_cmd == ACT_BITS)  
    begin
    faw_counter_o [3] = faw_counter_i[2];  // shift the counter and valid arrays 
    faw_counter_o [2] = faw_counter_i[1];
    faw_counter_o [1] = faw_counter_i[0];
    faw_valid_o   [3] = faw_valid_i[2];
    faw_valid_o   [2] = faw_valid_i[1];
    faw_valid_o   [1] = faw_valid_i[0];
    
    faw_valid_o   [0] = 1;
    faw_counter_o [0] = tFAW;
    end   
    
    else
    begin
    faw_counter_o [3] = faw_counter_i[3];  // the counters have same state
    faw_counter_o [2] = faw_counter_i[2];
    faw_counter_o [1] = faw_counter_i[1];
    faw_valid_o   [3] = faw_valid_i[3];
    faw_valid_o   [2] = faw_valid_i[2];
    faw_valid_o   [1] = faw_valid_i[1];
    
    faw_valid_o   [0] = faw_valid_i[0];
    faw_counter_o [0] = faw_counter_i[0];    
    end
    
    for ( j =0; j < 4 ; j = j+1)
    begin
        faw_counter_o[j]  = (faw_counter_o[j] >  0)?  faw_counter_o[j]-1 : 0;
        faw_valid_o  [j]  = (faw_counter_o[j] == 0)?  0: faw_valid_o[j];
    end
    
end

     
endmodule