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
    `include "./cs_macros.svh"
    `include "./time_constraints.vh"
    `include "./constraints_calculator.sv"
    `include "./tfaw_rnk.sv"
    `include "./tras_counter.sv"
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
    
    // time tables
    output [NUM_CH * NUM_RNK * NUM_BG * NUM_BNK - 1 : 0] [3 : 0] [TIME_WIDTH - 1 : 0] o_cmd_counter_intra_bank,
    output [NUM_CH * NUM_RNK * NUM_BG * NUM_BNK - 1 : 0] [3 : 0] [TIME_WIDTH - 1 : 0] o_cmd_counter_inter_bank,
    
    // faw counter
    output [NUM_RNK - 1 : 0] [TIME_WIDTH - 1 : 0] o_faw_counter_last,
    
    // ras counter
    output [NUM_CH * NUM_RNK * NUM_BG * NUM_BNK - 1 : 0] [TIME_WIDTH - 1 : 0] o_ras_counter
    );
    
    //---------------------------------------------------
    //----------------- Local Parameter -----------------
    //---------------------------------------------------
    
    localparam NUM_BNK_TOT = NUM_CH * NUM_RNK * NUM_BG * NUM_BNK;
    localparam TOT_BNK_SEL_WIDTH = RNK_SEL_WIDTH + BG_SEL_WIDTH + BNK_SEL_WIDTH;
    
    //---------------------------------------------------
    //------------------- Definitions -------------------
    //---------------------------------------------------
    
    // an indexed array holding issued command types
    logic [3 : 0] [CMD_TYPE_WIDTH - 1 : 0] sel_cmd_type_comb;
    
    // flags indicating if a bank is targeted by a command in an specific sub-slot
    logic [NUM_BNK_TOT - 1 : 0] [3 : 0] same_bank_comb;
    logic [NUM_BNK_TOT - 1 : 0] [3 : 0] same_bgroup_comb;
    logic [NUM_BNK_TOT - 1 : 0] [3 : 0] same_rank_comb;
    
    // combinational output of the tfaw_rnk module
    // tfaw_rnk output is registered inside the module itself
    wire [NUM_RNK - 1 : 0] [TIME_WIDTH - 1 : 0] faw_counter_last_comb;
    
    // combinational output of the tras_counter module
    // tras_counter output is registered inside the module itself
    wire [NUM_CH * NUM_RNK * NUM_BG * NUM_BNK - 1 : 0] [TIME_WIDTH - 1 : 0] ras_counter_comb;
    
    // constraints for all banks after issuing each command in each sub-slot
    reg [NUM_BNK_TOT - 1 : 0] [3 : 0] [TIME_WIDTH - 1 : 0] pre_const_comb;
    reg [NUM_BNK_TOT - 1 : 0] [3 : 0] [TIME_WIDTH - 1 : 0] act_const_comb;
    reg [NUM_BNK_TOT - 1 : 0] [3 : 0] [TIME_WIDTH - 1 : 0] rd_const_comb;
    reg [NUM_BNK_TOT - 1 : 0] [3 : 0] [TIME_WIDTH - 1 : 0] wr_const_comb;
    
    // cmd_counter table for intra-bank constraints
    // _reg always keeps the valid value
    // _comb is always assigned _reg
    // _reg is assigned _next_comb in each clock edge
    reg [NUM_BNK_TOT - 1 : 0] [3 : 0] [TIME_WIDTH-1:0] cmd_counter_intra_bank_reg;
    logic [NUM_BNK_TOT - 1 : 0] [3 : 0] [TIME_WIDTH-1:0] cmd_counter_intra_bank_comb;
    logic [NUM_BNK_TOT - 1 : 0] [3 : 0] [TIME_WIDTH-1:0] cmd_counter_intra_bank_decremented_comb;
    logic [NUM_BNK_TOT - 1 : 0] [3 : 0] [TIME_WIDTH-1:0] cmd_counter_intra_bank_next_comb;
    
    // cmd_counter table for inter-bank constraints
    // _reg always keeps the valid value
    // _comb is always assigned _reg
    // _reg is assigned _next_comb in each clock edge
    reg [NUM_BNK_TOT - 1 : 0] [3 : 0] [TIME_WIDTH-1:0] cmd_counter_inter_bank_reg;
    logic [NUM_BNK_TOT - 1 : 0] [3 : 0] [TIME_WIDTH-1:0] cmd_counter_inter_bank_comb;
    logic [NUM_BNK_TOT - 1 : 0] [3 : 0] [TIME_WIDTH-1:0] cmd_counter_inter_bank_decremented_comb;
    logic [NUM_BNK_TOT - 1 : 0] [3 : 0] [TIME_WIDTH-1:0] cmd_counter_inter_bank_next_comb;
    
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
    
    // assign the registered time tables and faw counter to the outputs
    assign o_cmd_counter_intra_bank = cmd_counter_intra_bank_reg;
    assign o_cmd_counter_inter_bank = cmd_counter_inter_bank_reg;
    assign o_faw_counter_last = faw_counter_last_comb;
    assign o_ras_counter = ras_counter_comb;
    
    // assign all issued command types to an indexed array
    assign sel_cmd_type_comb = {i_sel_cmd3_type, i_sel_cmd2_type, i_sel_cmd1_type, i_sel_cmd0_type};
    
    //---------------------------------------------------
    //------------- Initiate tFAW Counters --------------
    //---------------------------------------------------
    
    // read "macros.vh" for explanations
    
    // define a separate tFAW counter
    `ifndef OMIT_TFAW_COUNTER
    
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
    
    // disable tFAW counter and use increased tRRD
    `elsif OMIT_TFAW_COUNTER
    
    generate
        for (rt = 0; rt < NUM_RNK; rt = rt + 1) begin : tfaw_rnk
            assign faw_counter_last_comb[rt] = {TIME_WIDTH{1'b0}};
        end
    endgenerate
    
    `endif
    
    //---------------------------------------------------
    //------------- Initiate tRAS Counters --------------
    //---------------------------------------------------
    
    // read "macros.vh" for explanations
    
    // define a separate tRAS counter
    `ifndef OMIT_TRAS_COUNTER
    
    tras_counter#(
        .CMD_TYPE_WIDTH(CMD_TYPE_WIDTH),
        .NUM_RNK(NUM_RNK),
        .NUM_BG(NUM_BG),
        .NUM_BNK(NUM_BNK),
        .RNK_SEL_WIDTH(RNK_SEL_WIDTH),
        .BG_SEL_WIDTH(BG_SEL_WIDTH),
        .BNK_SEL_WIDTH(BNK_SEL_WIDTH),
        .TIME_WIDTH(TIME_WIDTH),
        .ISSUED_SUB_CYCLE('d3),
        .TCQ(TCQ)
        ) tras_counter_inst (
        .i_clk(i_clk),
        .i_rstn(i_rstn),
        .i_cmd_type(i_sel_cmd3_type),
        .i_cmd_rnk(i_sel_cmd3_rnk),
        .i_cmd_bg(i_sel_cmd3_bg),
        .i_cmd_bnk(i_sel_cmd3_bnk),
        .o_ras_counter(ras_counter_comb)
    );
    
    // disable tRAS counter and use increased tRAS
    `elsif OMIT_TRAS_COUNTER
    
    generate
        for (bt = 0; bt < NUM_BNK_TOT; bt = bt + 1) begin : tras_counter
            assign ras_counter_comb[bt] = {TIME_WIDTH{1'b0}};
        end
    endgenerate
    
    `endif
        
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
    assign cmd_counter_intra_bank_comb = cmd_counter_intra_bank_reg;
    assign cmd_counter_inter_bank_comb = cmd_counter_inter_bank_reg;

    // decrement all elements in the table by 4
    
    //-------------- Intra-bank Table --------------
    generate
        for(bt = 0; bt < NUM_BNK_TOT; bt = bt + 1) begin : decrement_intra_bank_table
            for(te = 0; te < 4; te = te + 1) begin
                assign cmd_counter_intra_bank_decremented_comb[bt][te] = (cmd_counter_intra_bank_comb[bt][te] > 4)? (cmd_counter_intra_bank_comb[bt][te] - 4) : {TIME_WIDTH{1'b0}};
            end
        end
    endgenerate
    
    //-------------- Inter-bank Table --------------
    generate
        for(bt = 0; bt < NUM_BNK_TOT; bt = bt + 1) begin : decrement_inter_bank_table
            for(te = 0; te < 4; te = te + 1) begin
                assign cmd_counter_inter_bank_decremented_comb[bt][te] = (cmd_counter_inter_bank_comb[bt][te] > 4)? (cmd_counter_inter_bank_comb[bt][te] - 4) : {TIME_WIDTH{1'b0}};
            end
        end
    endgenerate
    
    //---------------------------------------------------
    //--------------- Update Time Tables ----------------
    //---------------------------------------------------
    
    // update both inter-bank and intra-bank tables for each bank with the calculated constraints

    //-------------- Intra-bank Constrains --------------
    generate
        for(bt = 0; bt < NUM_BNK_TOT; bt = bt + 1) begin : update_intra_bank_table
            always_comb begin
                
                // if the current bt is the same bank as the bank that command in sub-slot[0] is targeting
                if (same_bank_comb[bt][0] && (i_sel_cmd0_type != `NOP)) begin 
                    cmd_counter_intra_bank_next_comb[bt][0] <= pre_const_comb[bt][0];
                    cmd_counter_intra_bank_next_comb[bt][1] <= act_const_comb[bt][0];
                    cmd_counter_intra_bank_next_comb[bt][2] <= rd_const_comb[bt][0];
                    cmd_counter_intra_bank_next_comb[bt][3] <= wr_const_comb[bt][0];
                end
                
                // if the current bt is the same bank as the bank that command in sub-slot[1] is targeting
                else if (same_bank_comb[bt][1] && (i_sel_cmd1_type != `NOP)) begin 
                    cmd_counter_intra_bank_next_comb[bt][0] <= pre_const_comb[bt][1];
                    cmd_counter_intra_bank_next_comb[bt][1] <= act_const_comb[bt][1];
                    cmd_counter_intra_bank_next_comb[bt][2] <= rd_const_comb[bt][1];
                    cmd_counter_intra_bank_next_comb[bt][3] <= wr_const_comb[bt][1];
                end
                
                // if the current bt is the same bank as the bank that command in sub-slot[2] is targeting
                else if (same_bank_comb[bt][2] && (i_sel_cmd2_type != `NOP)) begin
                    cmd_counter_intra_bank_next_comb[bt][0] <= pre_const_comb[bt][2];
                    cmd_counter_intra_bank_next_comb[bt][1] <= act_const_comb[bt][2];
                    cmd_counter_intra_bank_next_comb[bt][2] <= rd_const_comb[bt][2];
                    cmd_counter_intra_bank_next_comb[bt][3] <= wr_const_comb[bt][2];
                end
                
                // if the current bt is the same bank as the bank that command in sub-slot[3] is targeting
                else if (same_bank_comb[bt][3] && (i_sel_cmd3_type != `NOP)) begin
                    cmd_counter_intra_bank_next_comb[bt][0] <= pre_const_comb[bt][3];
                    cmd_counter_intra_bank_next_comb[bt][1] <= act_const_comb[bt][3];
                    cmd_counter_intra_bank_next_comb[bt][2] <= rd_const_comb[bt][3];
                    cmd_counter_intra_bank_next_comb[bt][3] <= wr_const_comb[bt][3];
                end

                // if the current bt is not targeted by any of the commands issued in four sub-slots
                else begin
                    cmd_counter_intra_bank_next_comb[bt][0] <= cmd_counter_intra_bank_decremented_comb[bt][0];
                    cmd_counter_intra_bank_next_comb[bt][1] <= cmd_counter_intra_bank_decremented_comb[bt][1];
                    cmd_counter_intra_bank_next_comb[bt][2] <= cmd_counter_intra_bank_decremented_comb[bt][2];
                    cmd_counter_intra_bank_next_comb[bt][3] <= cmd_counter_intra_bank_decremented_comb[bt][3];
                end
            end
        end
    endgenerate
    
    //-------------- Inter-bank Table --------------
    generate
        for(bt = 0; bt < NUM_BNK_TOT; bt = bt + 1) begin : update_inter_bank_table
            always_comb begin
                
                // update pre constraint
                // commands issued to a bank does not affect the pre constraint of other banks
                cmd_counter_inter_bank_next_comb[bt][0] <= {TIME_WIDTH{1'b0}};
                
                // update act constraint
                // commands issued to a bank does not affect the act constraint of other banks,
                // unless the issued command is an act
                if (i_sel_act_idx_valid)
                    cmd_counter_inter_bank_next_comb[bt][1] <= act_const_comb[bt][i_sel_act_idx];
                else
                    cmd_counter_inter_bank_next_comb[bt][1] <= cmd_counter_inter_bank_decremented_comb[bt][1];
                
                // update rd and wr constraint
                // commands issued to a bank does not affect the rd/wr constraint of other banks,
                // unless the issued command is a rd/wr
                if (i_sel_cas_idx_valid) begin
                    cmd_counter_inter_bank_next_comb[bt][2] <= rd_const_comb[bt][i_sel_cas_idx];
                    cmd_counter_inter_bank_next_comb[bt][3] <= wr_const_comb[bt][i_sel_cas_idx];
                end
                else begin
                    cmd_counter_inter_bank_next_comb[bt][2] <= cmd_counter_inter_bank_decremented_comb[bt][2];
                    cmd_counter_inter_bank_next_comb[bt][3] <= cmd_counter_inter_bank_decremented_comb[bt][3];
                end
            end
        end
    endgenerate
    
    //---------------------------------------------------
    //------------- Update Registers on i_clk -----------
    //---------------------------------------------------
    
    // update/reset time tables
    generate
        for(bt = 0; bt < NUM_BNK_TOT; bt = bt + 1) begin : update_registers
            always_ff @(posedge i_clk) begin
            
                // synchronous active-low reset logic
                if(!i_rstn) begin
                    
                    //-------------- Intra-bank Table --------------
                    cmd_counter_intra_bank_reg[bt][0] <= #(TCQ) {TIME_WIDTH{1'b0}};
                    cmd_counter_intra_bank_reg[bt][1] <= #(TCQ) {TIME_WIDTH{1'b0}};
                    cmd_counter_intra_bank_reg[bt][2] <= #(TCQ) {TIME_WIDTH{1'b0}};
                    cmd_counter_intra_bank_reg[bt][3] <= #(TCQ) {TIME_WIDTH{1'b0}};
                
                    //-------------- Inter-bank Table --------------
                    cmd_counter_inter_bank_reg[bt][0] <= #(TCQ) {TIME_WIDTH{1'b0}};
                    cmd_counter_inter_bank_reg[bt][1] <= #(TCQ) {TIME_WIDTH{1'b0}};
                    cmd_counter_inter_bank_reg[bt][2] <= #(TCQ) {TIME_WIDTH{1'b0}};
                    cmd_counter_inter_bank_reg[bt][3] <= #(TCQ) {TIME_WIDTH{1'b0}};
                    
                end
                
                // assign the calculated combinational values
                else begin
                    
                    //-------------- Intra-bank Table --------------
                    cmd_counter_intra_bank_reg[bt][0] <= #(TCQ) cmd_counter_intra_bank_next_comb[bt][0];
                    cmd_counter_intra_bank_reg[bt][1] <= #(TCQ) cmd_counter_intra_bank_next_comb[bt][1];
                    cmd_counter_intra_bank_reg[bt][2] <= #(TCQ) cmd_counter_intra_bank_next_comb[bt][2];
                    cmd_counter_intra_bank_reg[bt][3] <= #(TCQ) cmd_counter_intra_bank_next_comb[bt][3];
                
                    //-------------- Inter-bank Table --------------
                    cmd_counter_inter_bank_reg[bt][0] <= #(TCQ) cmd_counter_inter_bank_next_comb[bt][0];
                    cmd_counter_inter_bank_reg[bt][1] <= #(TCQ) cmd_counter_inter_bank_next_comb[bt][1];
                    cmd_counter_inter_bank_reg[bt][2] <= #(TCQ) cmd_counter_inter_bank_next_comb[bt][2];
                    cmd_counter_inter_bank_reg[bt][3] <= #(TCQ) cmd_counter_inter_bank_next_comb[bt][3];
                    
                end
            end
        end
    endgenerate
endmodule