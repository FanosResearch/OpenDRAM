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


module comparator#(
    
    parameter NUM_BNK_TOT = 1,
    parameter NUM_RNK_TOT = 1,    
    parameter CMD_TYPE_WIDTH = 3,
    parameter PTTRN_WIDTH = 4,
    parameter TIME_WIDTH = 16,

    parameter compare_value = 1,
    parameter CAS_EN = "ENABLE"
    )(
        input wire [NUM_BNK_TOT-1:0][CMD_TYPE_WIDTH-1:0] cmd,
        input wire [TIME_WIDTH-1:0] cmd_counter [NUM_BNK_TOT-1:0][3:0],
        input wire [TIME_WIDTH-1:0] tfaw_counter [NUM_RNK_TOT-1:0],
        input wire tfaw_valid [NUM_RNK_TOT-1:0],
        input wire [PTTRN_WIDTH-1:0] pattern,
        output wire [NUM_BNK_TOT-1:0] tv_f // 1 is valid
    );



localparam NUM_BANK_PER_RANK = NUM_BNK_TOT / NUM_RNK_TOT;

wire [TIME_WIDTH-1:0] pre_counter [NUM_BNK_TOT-1:0];
wire [TIME_WIDTH-1:0] act_counter [NUM_BNK_TOT-1:0];
wire [TIME_WIDTH-1:0] casrd_counter [NUM_BNK_TOT-1:0];
wire [TIME_WIDTH-1:0] caswr_counter [NUM_BNK_TOT-1:0];



wire [NUM_BNK_TOT-1:0] pre_cmp_f;
wire [NUM_BNK_TOT-1:0] act_cmp_f;
wire [NUM_RNK_TOT-1:0] tfaw_cmp_f;


reg [NUM_BNK_TOT-1:0] tv_f_r;

genvar bt, r;

generate
  for(bt=0; bt<NUM_BNK_TOT; bt = bt + 1)
  begin
    assign pre_counter[bt] = cmd_counter[bt][0];
    assign act_counter[bt] = cmd_counter[bt][1];
    assign casrd_counter[bt] = cmd_counter[bt][2];
    assign caswr_counter[bt] = cmd_counter[bt][3];
  end
endgenerate




assign tv_f = tv_f_r;
generate
if (CAS_EN == "ENABLE") begin
  wire [NUM_BNK_TOT-1:0] casrd_cmp_f;
  wire [NUM_BNK_TOT-1:0] caswr_cmp_f;

  for (bt = 0; bt< NUM_BNK_TOT; bt++) begin
    assign pre_cmp_f[bt] = (pre_counter[bt] <= compare_value);
    assign act_cmp_f[bt] = (act_counter[bt] <= compare_value);
    assign casrd_cmp_f[bt] = (casrd_counter[bt] <= compare_value);
    assign caswr_cmp_f[bt] = (caswr_counter[bt] <= compare_value);
  end
  for (r = 0; r< NUM_RNK_TOT; r++) begin
    assign tfaw_cmp_f[r] = ((tfaw_counter[r] <= compare_value) & tfaw_valid[r]) | ~tfaw_valid[r];
  end
  
  for(bt = 0; bt< NUM_BNK_TOT; bt++)
  begin
      always @(*) 
      begin
          case(cmd[bt])
          `PRE: begin
            tv_f_r[bt] = pre_cmp_f[bt];  
          end
          `ACT: begin
            tv_f_r[bt] = act_cmp_f[bt] & tfaw_cmp_f[bt/NUM_BANK_PER_RANK] & (~pattern[1]);
          end
          `CASRD, `CASRDA: begin
            tv_f_r[bt] = casrd_cmp_f[bt] & (~pattern[2]);
          end
          `CASWR, `CASWRA: begin
            tv_f_r[bt] = caswr_cmp_f[bt] & (~pattern[3]);
          end
          default: begin
            tv_f_r[bt] = 1'b0;
          end
      endcase    
      end
  end    
end else begin
  for (bt = 0; bt< NUM_BNK_TOT; bt++) begin
    assign pre_cmp_f[bt] = (pre_counter[bt] <= compare_value);
    assign act_cmp_f[bt] = (act_counter[bt] <= compare_value);
  end
  for (r = 0; r< NUM_RNK_TOT; r++) begin
    assign tfaw_cmp_f[r] = (tfaw_counter[r] <= (compare_value) & tfaw_valid[r]) | ~tfaw_valid[r];
  end
  for(bt = 0; bt< NUM_BNK_TOT; bt++)
  begin
      always @(*) 
      begin
          case(cmd[bt])
          `PRE: begin
            tv_f_r[bt] = pre_cmp_f[bt];  
          end
          `ACT: begin
            tv_f_r[bt] = act_cmp_f[bt] & tfaw_cmp_f[bt/NUM_BANK_PER_RANK] & (~pattern[1]);
          end
          default: begin
            tv_f_r[bt] = 1'b0;
          end
      endcase    
      end
  end
end
endgenerate


endmodule