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

module time_machinery#(
    
    parameter CMD_TYPE_WIDTH    = 3,
	
    parameter NUM_CH            = 1,
    parameter NUM_RNK           = 1,
    parameter NUM_BG            = 2,
    parameter NUM_BNK           = 4,
	
    parameter CH_SEL_WIDTH      = 1,
    parameter RNK_SEL_WIDTH     = 1,
    parameter BG_SEL_WIDTH      = 1,
    parameter BNK_SEL_WIDTH     = 2,
    
    parameter TIME_WIDTH        = 6,
    
    parameter TCQ               = 0.1
    
    )(
    
    // module working on the posedge of the clock
    input i_clk,
    // synchronous active-low reset
    input i_rstn,
    
    // 1st command picked by the scheduler
    input [CMD_TYPE_WIDTH - 1 : 0] i_sel_cmd0_type,
	input [RNK_SEL_WIDTH - 1 : 0] i_sel_cmd0_rnk,
	input [BG_SEL_WIDTH - 1 : 0]  i_sel_cmd0_bg,
	input [BNK_SEL_WIDTH - 1 : 0] i_sel_cmd0_bnk,

    // 2nd command picked by the scheduler
    input [CMD_TYPE_WIDTH - 1 : 0] i_sel_cmd1_type,
	input [RNK_SEL_WIDTH - 1 : 0] i_sel_cmd1_rnk,
	input [BG_SEL_WIDTH - 1 : 0]  i_sel_cmd1_bg,
	input [BNK_SEL_WIDTH - 1 : 0] i_sel_cmd1_bnk,
    
    // 3rd command picked by the scheduler
    input [CMD_TYPE_WIDTH - 1 : 0] i_sel_cmd2_type,
	input [RNK_SEL_WIDTH - 1 : 0] i_sel_cmd2_rnk,
	input [BG_SEL_WIDTH - 1 : 0]  i_sel_cmd2_bg,
	input [BNK_SEL_WIDTH - 1 : 0] i_sel_cmd2_bnk,
    
    // 4th command picked by the scheduler
    input [CMD_TYPE_WIDTH - 1 : 0] i_sel_cmd3_type,
	input [RNK_SEL_WIDTH - 1 : 0] i_sel_cmd3_rnk,
	input [BG_SEL_WIDTH - 1 : 0]  i_sel_cmd3_bg,
	input [BNK_SEL_WIDTH - 1 : 0] i_sel_cmd3_bnk,
	
	// index of the sub-slot that the ACT command issued
	input [1 : 0] i_sel_act_idx,
	input i_sel_act_idx_valid,
	
	// index of the sub-slot that the CAS command issued
	input [1 : 0] i_sel_cas_idx,
	input i_sel_cas_idx_valid,
    
    // time table
    output [NUM_CH * NUM_RNK * NUM_BG * NUM_BNK - 1 : 0] [3 : 0] [TIME_WIDTH - 1 : 0] o_cmd_counter
    );
    
    //---------------------------------------------------
    //----------------- Local Parameter -----------------
    //---------------------------------------------------
    
    localparam NUM_BNK_TOT = NUM_CH * NUM_RNK * NUM_BG * NUM_BNK;
    localparam TOT_BNK_SEL_WIDTH = RNK_SEL_WIDTH + BG_SEL_WIDTH + BNK_SEL_WIDTH;
    
    //---------------------------------------------------
    //------------------- Definitions -------------------
    //---------------------------------------------------
    
    // flag indicating if a CASWR(A) is issued in any of sub-slots, and if it is targeting the same_rank/same_bgroup
    logic [NUM_BNK_TOT - 1 : 0] [1 : 0] cwr_flag;
    
    // an indexed array holding issued command types
    logic [3 : 0] [CMD_TYPE_WIDTH - 1 : 0] sel_cmd_type_comb;
    
    // flags indicating if a bank is targeted by a command in an specific sub-slot
    logic [NUM_BNK_TOT - 1 : 0] [3 : 0] same_bank_comb;
    logic [NUM_BNK_TOT - 1 : 0] [3 : 0] same_bgroup_comb;
    logic [NUM_BNK_TOT - 1 : 0] [3 : 0] same_rank_comb;
    
    // combinational output of the tfaw_rnk module
    // tfaw_rnk output is registered inside the module itself
    wire [NUM_RNK - 1 : 0] [TIME_WIDTH - 1 : 0] faw_counter_last_comb;
    
    // constraints for all banks after issuing each command in each sub-slot
    reg [NUM_BNK_TOT - 1 : 0] [3 : 0] [TIME_WIDTH - 1 : 0] pre_const_comb;
    reg [NUM_BNK_TOT - 1 : 0] [3 : 0] [TIME_WIDTH - 1 : 0] act_const_comb;
    reg [NUM_BNK_TOT - 1 : 0] [3 : 0] [TIME_WIDTH - 1 : 0] rd_const_comb;
    reg [NUM_BNK_TOT - 1 : 0] [3 : 0] [TIME_WIDTH - 1 : 0] wr_const_comb;
    
    // cmd_counter table
    // _reg always keeps the valid value
    // _comb is always assigned to _reg
    // _reg is assigned to _next_comb in each clock edge
    reg [NUM_BNK_TOT - 1 : 0] [3 : 0] [TIME_WIDTH-1:0] cmd_counter_reg;
    logic [NUM_BNK_TOT - 1 : 0] [3 : 0] [TIME_WIDTH-1:0] cmd_counter_comb;
    logic [NUM_BNK_TOT - 1 : 0] [3 : 0] [TIME_WIDTH-1:0] cmd_counter_max_comb;
    logic [NUM_BNK_TOT - 1 : 0] [3 : 0] [TIME_WIDTH-1:0] cmd_counter_decremented_comb;
    logic [NUM_BNK_TOT - 1 : 0] [3 : 0] [TIME_WIDTH-1:0] cmd_counter_next_comb;
    
    // one-dimentional vector holding the maximum value between:
    // act constraint in the cmd_counter_decremented_comb and faw_counter_last_comb for each valid faw
    logic [NUM_BNK_TOT - 1 : 0] [3 : 0] [TIME_WIDTH-1:0] cmd_counter_act_tfaw_max_comb;
    
    // one-dimentional vector holding the rank/bgroup index for each bank
    logic [NUM_BNK_TOT - 1 : 0] [RNK_SEL_WIDTH-1:0] rank_idx_comb;
    logic [NUM_BNK_TOT - 1 : 0] [BG_SEL_WIDTH-1:0] bgroup_idx_comb;
    
    // genvars for rank_total, bank_total, and sub_cycle generate loops
    genvar rt;
    genvar bt;
    genvar sc;
    genvar te;
    
    //---------------------------------------------------
    //------------- Continuous Assignments --------------
    //---------------------------------------------------
    
    // assign the registered time table to the outputs
    assign o_cmd_counter = cmd_counter_reg;
    
    // assign all issued command types to an indexed array
    assign sel_cmd_type_comb = {i_sel_cmd3_type, i_sel_cmd2_type, i_sel_cmd1_type, i_sel_cmd0_type};
    
    //---------------------------------------------------
    //------------- Assign Rank/BGroup Index ------------
    //---------------------------------------------------
    
    // assign the rank and bank group index for each bank
    // e.g. rank_idx_comb[bt] = 0 means that the bank bt is located in rank 0
    generate
        for(bt = 0; bt < NUM_BNK_TOT; bt = bt + 1) begin : decode_bt
            assign rank_idx_comb[bt] = bt[TOT_BNK_SEL_WIDTH - 1 : BG_SEL_WIDTH + BNK_SEL_WIDTH];
            assign bgroup_idx_comb[bt] = bt[TOT_BNK_SEL_WIDTH - 1 : BNK_SEL_WIDTH];
        end
    endgenerate
    
    //---------------------------------------------------
    //-------------- Calculate same_ Flags --------------
    //---------------------------------------------------
    
    // assign the same_*_comb flags based on the picked command in each sub-slot
    // e.g. same_bank_comb[2][1] == 1'b1 means that the command issued in sub-slot[1] is targeting bank[2]
    // the same applies to other two
    generate
        for (bt = 0 ; bt < NUM_BNK_TOT ; bt = bt + 1) begin : same_flag
        
            // for the command in sub-slot[0]
            assign same_bank_comb[bt][0] = ({i_sel_cmd0_rnk, i_sel_cmd0_bg, i_sel_cmd0_bnk} == bt) ? 1'b1 : 1'b0;
            assign same_bgroup_comb[bt][0] = ({i_sel_cmd0_rnk, i_sel_cmd0_bg} == bgroup_idx_comb[bt]) ? 1'b1 : 1'b0;
            assign same_rank_comb[bt][0] = ({i_sel_cmd0_rnk} == rank_idx_comb[bt]) ? 1'b1 : 1'b0;
            
            // for the command in sub-slot[1]
            assign same_bank_comb[bt][1] = ({i_sel_cmd1_rnk, i_sel_cmd1_bg, i_sel_cmd1_bnk} == bt) ? 1'b1 : 1'b0;
            assign same_bgroup_comb[bt][1] = ({i_sel_cmd1_rnk, i_sel_cmd1_bg} == bgroup_idx_comb[bt]) ? 1'b1 : 1'b0;
            assign same_rank_comb[bt][1] = ({i_sel_cmd1_rnk} == rank_idx_comb[bt]) ? 1'b1 : 1'b0;
            
            // for the command in sub-slot[2]
            assign same_bank_comb[bt][2] = ({i_sel_cmd2_rnk, i_sel_cmd2_bg, i_sel_cmd2_bnk} == bt) ? 1'b1 : 1'b0;
            assign same_bgroup_comb[bt][2] = ({i_sel_cmd2_rnk, i_sel_cmd2_bg} == bgroup_idx_comb[bt]) ? 1'b1 : 1'b0;
            assign same_rank_comb[bt][2] = ({i_sel_cmd2_rnk} == rank_idx_comb[bt]) ? 1'b1 : 1'b0;
            
            // for the command in sub-slot[3]
            assign same_bank_comb[bt][3] = ({i_sel_cmd3_rnk, i_sel_cmd3_bg, i_sel_cmd3_bnk} == bt) ? 1'b1 : 1'b0;
            assign same_bgroup_comb[bt][3] = ({i_sel_cmd3_rnk, i_sel_cmd3_bg} == bgroup_idx_comb[bt]) ? 1'b1 : 1'b0;
            assign same_rank_comb[bt][3] = ({i_sel_cmd3_rnk} == rank_idx_comb[bt]) ? 1'b1 : 1'b0;
        end
    endgenerate

    //---------------------------------------------------
    //------------ Calculate CASWR(A) Flag --------------
    //---------------------------------------------------
    
    // flag indicating if a CASWR(A) is issued in any of sub-slots, and if it is targeting the same_rank/same_bgroup
    // i_cwr_flag   CASWR(A)        same_rank   same_bgroup
    // ----------------------------------------------------
    // 2'b00        not present     n/a         n/a
    // 2'b10        present         yes         no
    // 2'b11        present         yes         yes
    generate
        for(bt = 0; bt < NUM_BNK_TOT; bt = bt + 1) begin : calculate_cwr_flag
            always_comb begin
                cwr_flag[bt] <= (i_sel_cas_idx_valid == 1'b1 && (sel_cmd_type_comb[i_sel_cas_idx] == `CASWR || sel_cmd_type_comb[i_sel_cas_idx] == `CASWRA)) ? {same_rank_comb[bt][i_sel_cas_idx], same_bgroup_comb[bt][i_sel_cas_idx]} :
                                2'b00;
            end
        end
    endgenerate

    //---------------------------------------------------
    //-------------- Calculate Constraints --------------
    //---------------------------------------------------

    // constraints for all banks after issuing each command in each sub-slot are calculated separately
    // in the next step, the maximum for each constraint of each bank will be picked
    // e.g. pre_const_comb[2][0] = 46 means that the PRE value in the timetable of bank 2 will be 46 if the command in sub-slot[0] is targeting bank 2
    generate
        for(bt = 0; bt < NUM_BNK_TOT; bt = bt + 1) begin : constraints_calculator
        
            // calculate constraints after issuing the command in the 1st sub-slot
            constraints_calculator#(
                .CMD_TYPE_WIDTH(CMD_TYPE_WIDTH),
                .TIME_WIDTH(TIME_WIDTH),
                .ISSUED_SUB_CYCLE(0)
                ) cmd0_inst (
                .i_sel_cmd(i_sel_cmd0_type),
                .i_same_bank(same_bank_comb[bt][0]),
                .i_same_bgroup(same_bgroup_comb[bt][0]),
                .i_same_rank(same_rank_comb[bt][0]),
                .i_cwr_flag(cwr_flag[bt]),
                .i_issued_cas_sub_cycle(i_sel_cas_idx),
                .o_pre_const(pre_const_comb[bt][0]),
                .o_act_const(act_const_comb[bt][0]),
                .o_rd_const(rd_const_comb[bt][0]),
                .o_wr_const(wr_const_comb[bt][0])
            );
            
            // calculate constraints after issuing the command in the 2nd sub-slot
            constraints_calculator#(
                .CMD_TYPE_WIDTH(CMD_TYPE_WIDTH),
                .TIME_WIDTH(TIME_WIDTH),
                .ISSUED_SUB_CYCLE(1)
                ) cmd1_inst (
                .i_sel_cmd(i_sel_cmd1_type),
                .i_same_bank(same_bank_comb[bt][1]),
                .i_same_bgroup(same_bgroup_comb[bt][1]),
                .i_same_rank(same_rank_comb[bt][1]),
                .i_cwr_flag(cwr_flag[bt]),
                .i_issued_cas_sub_cycle(i_sel_cas_idx),
                .o_pre_const(pre_const_comb[bt][1]),
                .o_act_const(act_const_comb[bt][1]),
                .o_rd_const(rd_const_comb[bt][1]),
                .o_wr_const(wr_const_comb[bt][1])
            );
            
            // calculate constraints after issuing the command in the 3rd sub-slot
            constraints_calculator#(
                .CMD_TYPE_WIDTH(CMD_TYPE_WIDTH),
                .TIME_WIDTH(TIME_WIDTH),
                .ISSUED_SUB_CYCLE(2)
                ) cmd2_inst (
                .i_sel_cmd(i_sel_cmd2_type),
                .i_same_bank(same_bank_comb[bt][2]),
                .i_same_bgroup(same_bgroup_comb[bt][2]),
                .i_same_rank(same_rank_comb[bt][2]),
                .i_cwr_flag(cwr_flag[bt]),
                .i_issued_cas_sub_cycle(i_sel_cas_idx),
                .o_pre_const(pre_const_comb[bt][2]),
                .o_act_const(act_const_comb[bt][2]),
                .o_rd_const(rd_const_comb[bt][2]),
                .o_wr_const(wr_const_comb[bt][2])
            );
            
            // calculate constraints after issuing the command in the 4th sub-slot
            constraints_calculator#(
                .CMD_TYPE_WIDTH(CMD_TYPE_WIDTH),
                .TIME_WIDTH(TIME_WIDTH),
                .ISSUED_SUB_CYCLE(3)
                ) cmd3_inst (
                .i_sel_cmd(i_sel_cmd3_type),
                .i_same_bank(same_bank_comb[bt][3]),
                .i_same_bgroup(same_bgroup_comb[bt][3]),
                .i_same_rank(same_rank_comb[bt][3]),
                .i_cwr_flag(cwr_flag[bt]),
                .i_issued_cas_sub_cycle(i_sel_cas_idx),
                .o_pre_const(pre_const_comb[bt][3]),
                .o_act_const(act_const_comb[bt][3]),
                .o_rd_const(rd_const_comb[bt][3]),
                .o_wr_const(wr_const_comb[bt][3])
            );
        end
    endgenerate
    
    //---------------------------------------------------
    //-------------- Decrement Time Tables --------------
    //---------------------------------------------------
    
    // assign the registered value to a wire    
    assign cmd_counter_comb = cmd_counter_reg;

    // decrement all elements in the table by 4
    generate
        for(bt = 0; bt < NUM_BNK_TOT; bt = bt + 1) begin : decrement_table
            for(te = 0; te < 4; te = te + 1) begin
                assign cmd_counter_decremented_comb[bt][te] = (cmd_counter_comb[bt][te] > 4)? (cmd_counter_comb[bt][te] - 4) : {TIME_WIDTH{1'b0}};
            end
        end
    endgenerate
        
    //---------------------------------------------------
    //------------- Initiate tFAW Counters --------------
    //---------------------------------------------------
    
    // instantiate one tfaw counter for each rank
    // pass the commands in sub-slot[1] and sub-slot[3]
    // (only sub-slots that may have an ACT command)
    generate
        for (rt = 0; rt < NUM_RNK; rt = rt + 1) begin : tfaw_rnk
            tfaw_rnk#(
                .CMD_TYPE_WIDTH(CMD_TYPE_WIDTH),
                .RNK_SEL_WIDTH(RNK_SEL_WIDTH),
                .RANK_ID(rt),
                .TIME_WIDTH(TIME_WIDTH),
                .TCQ(TCQ)
                ) inst (
                .i_clk(i_clk),
                .i_rstn(i_rstn),
                .i_cmd0_type(i_sel_cmd1_type),
                .i_cmd0_rnk(i_sel_cmd1_rnk),
                .i_cmd1_type(i_sel_cmd3_type),
                .i_cmd1_rnk(i_sel_cmd3_rnk),
                .o_faw_counter_last(faw_counter_last_comb[rt])
            ); 
        end
    endgenerate
    
    //---------------------------------------------------
    //------- Pick Maximum Among Table and tFAW  --------
    //---------------------------------------------------

    // pick the maximum value among the act constraint in the table and the valid tfaw counter
    generate
        for(bt = 0; bt < NUM_BNK_TOT; bt = bt + 1) begin : get_table_faw_max
            assign cmd_counter_act_tfaw_max_comb[bt][0] = cmd_counter_decremented_comb[bt][0];
            assign cmd_counter_act_tfaw_max_comb[bt][1] = (cmd_counter_decremented_comb[bt][1] < faw_counter_last_comb[rank_idx_comb[bt]]) ?
                                                          faw_counter_last_comb[rank_idx_comb[bt]] : cmd_counter_decremented_comb[bt][1];
            assign cmd_counter_act_tfaw_max_comb[bt][2] = cmd_counter_decremented_comb[bt][2];
            assign cmd_counter_act_tfaw_max_comb[bt][3] = cmd_counter_decremented_comb[bt][3];
        end
    endgenerate
    
    //---------------------------------------------------
    //--------------- Update Time Tables ----------------
    //---------------------------------------------------
    
    // update the table for each bank with the maximum value between calculated constrains and the current value in the table
    generate
        for(bt = 0; bt < NUM_BNK_TOT; bt = bt + 1) begin : update_table
            always_comb begin
                
                //-------------- Intra-bank Constrains --------------
                
                // if the current bt is the same bank as the bank that command in sub-slot[0] is targeting
                if (same_bank_comb[bt][0] && (i_sel_cmd0_type != `NOP)) begin 
                    cmd_counter_max_comb[bt][0] <= (cmd_counter_act_tfaw_max_comb[bt][0] < pre_const_comb[bt][0]) ? pre_const_comb[bt][0] : cmd_counter_act_tfaw_max_comb[bt][0];
                    cmd_counter_max_comb[bt][1] <= (cmd_counter_act_tfaw_max_comb[bt][1] < act_const_comb[bt][0]) ? act_const_comb[bt][0] : cmd_counter_act_tfaw_max_comb[bt][1];
                    cmd_counter_max_comb[bt][2] <= (cmd_counter_act_tfaw_max_comb[bt][2] < rd_const_comb[bt][0]) ? rd_const_comb[bt][0] : cmd_counter_act_tfaw_max_comb[bt][2];
                    cmd_counter_max_comb[bt][3] <= (cmd_counter_act_tfaw_max_comb[bt][3] < wr_const_comb[bt][0]) ? wr_const_comb[bt][0] : cmd_counter_act_tfaw_max_comb[bt][3];
                end
                
                // if the current bt is the same bank as the bank that command in sub-slot[1] is targeting
                else if (same_bank_comb[bt][1] && (i_sel_cmd1_type != `NOP)) begin 
                    cmd_counter_max_comb[bt][0] <= (cmd_counter_act_tfaw_max_comb[bt][0] < pre_const_comb[bt][1]) ? pre_const_comb[bt][1] : cmd_counter_act_tfaw_max_comb[bt][0];
                    cmd_counter_max_comb[bt][1] <= (cmd_counter_act_tfaw_max_comb[bt][1] < act_const_comb[bt][1]) ? act_const_comb[bt][1] : cmd_counter_act_tfaw_max_comb[bt][1];
                    cmd_counter_max_comb[bt][2] <= (cmd_counter_act_tfaw_max_comb[bt][2] < rd_const_comb[bt][1]) ? rd_const_comb[bt][1] : cmd_counter_act_tfaw_max_comb[bt][2];
                    cmd_counter_max_comb[bt][3] <= (cmd_counter_act_tfaw_max_comb[bt][3] < wr_const_comb[bt][1]) ? wr_const_comb[bt][1] : cmd_counter_act_tfaw_max_comb[bt][3];
                end
                
                // if the current bt is the same bank as the bank that command in sub-slot[2] is targeting
                else if (same_bank_comb[bt][2] && (i_sel_cmd2_type != `NOP)) begin
                    cmd_counter_max_comb[bt][0] <= (cmd_counter_act_tfaw_max_comb[bt][0] < pre_const_comb[bt][2]) ? pre_const_comb[bt][2] : cmd_counter_act_tfaw_max_comb[bt][0];
                    cmd_counter_max_comb[bt][1] <= (cmd_counter_act_tfaw_max_comb[bt][1] < act_const_comb[bt][2]) ? act_const_comb[bt][2] : cmd_counter_act_tfaw_max_comb[bt][1];
                    cmd_counter_max_comb[bt][2] <= (cmd_counter_act_tfaw_max_comb[bt][2] < rd_const_comb[bt][2]) ? rd_const_comb[bt][2] : cmd_counter_act_tfaw_max_comb[bt][2];
                    cmd_counter_max_comb[bt][3] <= (cmd_counter_act_tfaw_max_comb[bt][3] < wr_const_comb[bt][2]) ? wr_const_comb[bt][2] : cmd_counter_act_tfaw_max_comb[bt][3];
                end
                
                // if the current bt is the same bank as the bank that command in sub-slot[3] is targeting
                else if (same_bank_comb[bt][3] && (i_sel_cmd3_type != `NOP)) begin
                    cmd_counter_max_comb[bt][0] <= (cmd_counter_act_tfaw_max_comb[bt][0] < pre_const_comb[bt][3]) ? pre_const_comb[bt][3] : cmd_counter_act_tfaw_max_comb[bt][0];
                    cmd_counter_max_comb[bt][1] <= (cmd_counter_act_tfaw_max_comb[bt][1] < act_const_comb[bt][3]) ? act_const_comb[bt][3] : cmd_counter_act_tfaw_max_comb[bt][1];
                    cmd_counter_max_comb[bt][2] <= (cmd_counter_act_tfaw_max_comb[bt][2] < rd_const_comb[bt][3]) ? rd_const_comb[bt][3] : cmd_counter_act_tfaw_max_comb[bt][2];
                    cmd_counter_max_comb[bt][3] <= (cmd_counter_act_tfaw_max_comb[bt][3] < wr_const_comb[bt][3]) ? wr_const_comb[bt][3] : cmd_counter_act_tfaw_max_comb[bt][3];
                end
                
                //-------------- Inter-bank Constraints --------------
                
                // if the current bt is not the same as any of the banks that the four issued commands are targeting,
                // apply inter-bank constraints
                else begin
                
                    // update pre constraint
                    cmd_counter_max_comb[bt][0] <=  cmd_counter_act_tfaw_max_comb[bt][0];        
                    
                    // update act constraint
                    if (i_sel_act_idx_valid)
                        cmd_counter_max_comb[bt][1] <= (cmd_counter_act_tfaw_max_comb[bt][1] < act_const_comb[bt][i_sel_act_idx]) ? act_const_comb[bt][i_sel_act_idx] : cmd_counter_act_tfaw_max_comb[bt][1];
                    else
                        cmd_counter_max_comb[bt][1] <= cmd_counter_act_tfaw_max_comb[bt][1];                
                    
                    // update rd and wr constraint
                    if (i_sel_cas_idx_valid) begin
                        cmd_counter_max_comb[bt][2] <= (cmd_counter_act_tfaw_max_comb[bt][2] < rd_const_comb[bt][i_sel_cas_idx]) ? rd_const_comb[bt][i_sel_cas_idx] : cmd_counter_act_tfaw_max_comb[bt][2];
                        cmd_counter_max_comb[bt][3] <= (cmd_counter_act_tfaw_max_comb[bt][3] < wr_const_comb[bt][i_sel_cas_idx]) ? wr_const_comb[bt][i_sel_cas_idx] : cmd_counter_act_tfaw_max_comb[bt][3];
                    end
                    else begin
                        cmd_counter_max_comb[bt][2] <= cmd_counter_act_tfaw_max_comb[bt][2];
                        cmd_counter_max_comb[bt][3] <= cmd_counter_act_tfaw_max_comb[bt][3];
                    end
                end
            end
        end
    endgenerate
    
    // assign the next value of the table after picking the maximum value
    assign cmd_counter_next_comb = cmd_counter_max_comb;
    
    //---------------------------------------------------
    //------------- Update Registers on i_clk -----------
    //---------------------------------------------------
    
    // update/reset time tables
    generate
        for(bt = 0; bt < NUM_BNK_TOT; bt = bt + 1) begin : update_registers
            always_ff @(posedge i_clk) begin
                // synchronous active-low reset logic
                if(!i_rstn) begin
                    cmd_counter_reg[bt][0] <= #(TCQ) 0;
                    cmd_counter_reg[bt][1] <= #(TCQ) {TIME_WIDTH{1'b0}};
                    cmd_counter_reg[bt][2] <= #(TCQ) {TIME_WIDTH{1'b0}};
                    cmd_counter_reg[bt][3] <= #(TCQ) {TIME_WIDTH{1'b0}};
                end
                // assign the calculated combinational values
                else begin
                    cmd_counter_reg[bt][0] <= #(TCQ) cmd_counter_next_comb[bt][0];
                    cmd_counter_reg[bt][1] <= #(TCQ) cmd_counter_next_comb[bt][1];
                    cmd_counter_reg[bt][2] <= #(TCQ) cmd_counter_next_comb[bt][2];
                    cmd_counter_reg[bt][3] <= #(TCQ) cmd_counter_next_comb[bt][3];
                end
            end
        end
    endgenerate
    
endmodule