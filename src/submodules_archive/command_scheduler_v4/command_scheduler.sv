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
    `include "./rr_arbiter.sv"
    `include "./priority_encoder.sv"
    `include "./time_machinery.sv"
`endif // `ifdef USE_RELATIVE_PATH_INCLUDES


module command_scheduler#(

    parameter CMD_TYPE_WIDTH    = 3,
	
    parameter NUM_CH            = 1,
    parameter NUM_RNK           = 1,
    parameter NUM_BG            = 4,
    parameter NUM_BNK           = 4,
	
    parameter CH_SEL_WIDTH      = 1,
    parameter RNK_SEL_WIDTH     = 1,
    parameter BG_SEL_WIDTH      = 2,
    parameter BNK_SEL_WIDTH     = 2,
    parameter ROW_SEL_WIDTH     = 16,
    parameter COL_SEL_WIDTH     = 10,
    
    parameter DATA_PTR_WIDTH    = 5,
    
    parameter TIME_WIDTH        = 6,
    
    parameter TCQ               = 0.1
    
    )(
    
    // module working on the posedge of the clock
    input i_clk,
    // synchronous active-low reset
    input i_rstn,
    
    // inputs from the queues
    input [NUM_CH * NUM_RNK * NUM_BG * NUM_BNK - 1 : 0] [CH_SEL_WIDTH - 1 : 0] i_channel,
    input [NUM_CH * NUM_RNK * NUM_BG * NUM_BNK - 1 : 0] [RNK_SEL_WIDTH - 1 : 0] i_rank,
    input [NUM_CH * NUM_RNK * NUM_BG * NUM_BNK - 1 : 0] [BG_SEL_WIDTH - 1 : 0] i_bgroup,
    input [NUM_CH * NUM_RNK * NUM_BG * NUM_BNK - 1 : 0] [BNK_SEL_WIDTH - 1 : 0] i_bank,
    input [NUM_CH * NUM_RNK * NUM_BG * NUM_BNK - 1 : 0] [ROW_SEL_WIDTH - 1 : 0] i_row,
    input [NUM_CH * NUM_RNK * NUM_BG * NUM_BNK - 1 : 0] [COL_SEL_WIDTH - 1 : 0] i_column,
    input [NUM_CH * NUM_RNK * NUM_BG * NUM_BNK - 1 : 0] [DATA_PTR_WIDTH - 1 : 0] i_data_ptr,
    input [NUM_CH * NUM_RNK * NUM_BG * NUM_BNK - 1 : 0] [CMD_TYPE_WIDTH - 1 : 0] i_cmd,
    input [NUM_CH * NUM_RNK * NUM_BG * NUM_BNK - 1 : 0] i_valid,
    
    // input from periodic read module
    // if it is high, no cas can be issued
    input i_block_cas,
    
    // outputs to the queues
    output [NUM_CH * NUM_RNK * NUM_BG * NUM_BNK - 1 : 0] o_dequeue,
    
    // four selected commands
    output [3 : 0] [CH_SEL_WIDTH - 1 : 0] o_channel,
    output [3 : 0] [RNK_SEL_WIDTH - 1 : 0] o_rank,
    output [3 : 0] [BG_SEL_WIDTH - 1 : 0] o_bgroup,
    output [3 : 0] [BNK_SEL_WIDTH - 1 : 0] o_bank,
    output [3 : 0] [ROW_SEL_WIDTH - 1 : 0] o_row,
    output [3 : 0] [COL_SEL_WIDTH - 1 : 0] o_column,
    output [3 : 0] [DATA_PTR_WIDTH - 1 : 0] o_data_ptr,
    output [3 : 0] [CMD_TYPE_WIDTH - 1 : 0] o_cmd
    );
    
    //---------------------------------------------------
    //----------------- Local Parameter -----------------
    //---------------------------------------------------
    
    localparam NUM_RNK_TOT = NUM_CH * NUM_RNK;
    
    localparam NUM_BNK_TOT = NUM_CH * NUM_RNK * NUM_BG * NUM_BNK;
    localparam TOT_BNK_SEL_WIDTH = (NUM_BNK_TOT == 1) ? 1 : $clog2(NUM_BNK_TOT);
    
    localparam CMD_ADDR_WDITH = CH_SEL_WIDTH
                              + RNK_SEL_WIDTH
                              + BG_SEL_WIDTH
                              + BNK_SEL_WIDTH
                              + ROW_SEL_WIDTH
                              + COL_SEL_WIDTH;
                              
    localparam CMD_PKT_WIDTH = CMD_TYPE_WIDTH + CMD_ADDR_WDITH + DATA_PTR_WIDTH;
    
    //---------------------------------------------------
    //--------------- User-defined Types ----------------
    //---------------------------------------------------   
    
    // type definition for each portion of command address                            
    typedef logic [CH_SEL_WIDTH - 1 : 0] channel_t;
    typedef logic [RNK_SEL_WIDTH - 1 : 0] rank_t;
    typedef logic [BG_SEL_WIDTH - 1 : 0] bgroup_t;
    typedef logic [BNK_SEL_WIDTH - 1 : 0] bank_t;
    typedef logic [ROW_SEL_WIDTH - 1 : 0] row_t;
    typedef logic [COL_SEL_WIDTH - 1 : 0] column_t;
    
    // type definition for data pointer
    typedef logic [DATA_PTR_WIDTH - 1 : 0] data_ptr_t;
    
    // type definition for command
    typedef logic [CMD_TYPE_WIDTH - 1 : 0] cmd_t;
    
    // command address structure, holding all portions of address
    // as it is packed, it will be synthesized as a bit vector
    typedef struct packed {
        channel_t channel;
        rank_t rank;
        bgroup_t bgroup;
        bank_t bank;
        row_t row;
        column_t column;
    } cmd_addr_t;
    
    // command packet structure
    typedef struct packed {
        cmd_t cmd;
        cmd_addr_t addr;
        data_ptr_t data_ptr;
    } cmd_packet_t; 
    
    //---------------------------------------------------
    //------------------- Definitions -------------------
    //---------------------------------------------------
    
    // array holding the front command of each bank queue
    cmd_packet_t [NUM_BNK_TOT - 1 : 0] queues_front_comb;
    // each index i of queues_front_valid_comb indicates if there is a command in front of the queue i or not
    // connected to the valid output of each queue
    wire [NUM_BNK_TOT - 1 : 0] queues_front_valid_comb;
    // each index i of dequeue_comb indicates if the command in front of the queue i must be dequeued or not
    // connected to the dequeue input of each queue
    wire [NUM_BNK_TOT - 1 : 0] dequeue_comb;
    
    // each index i of the following vectors indicate if the PRE/ACT/CAS command in front of the queue i can be issued in sub-cycle 0/1/2/3 or not
    wire [NUM_BNK_TOT - 1 : 0] pre_sc0_ready_comb;
    wire [NUM_BNK_TOT - 1 : 0] cas_sc2_ready_comb;
    wire [NUM_BNK_TOT - 1 : 0] act_sc3_ready_comb;
    
    // index of the bank with an ACT in front to be picked at sub-cycle 3
    wire [TOT_BNK_SEL_WIDTH - 1 : 0] act_idx_sc3_comb;
    logic act_idx_sc3_valid_comb;
    
    // index of the bank with a CAS in front to be picked at sub-cycle 2
    wire [TOT_BNK_SEL_WIDTH - 1 : 0] cas_idx_sc2_comb;
    logic cas_idx_sc2_valid_comb;
    
    // four slots for holding commands for each sub-cycle
    cmd_packet_t [3 : 0] slots_comb;

    // index of two banks with a PRE in front to be picked at the resolve stage
    logic [1 : 0] [TOT_BNK_SEL_WIDTH - 1 : 0] pre_idx_comb;
    logic [1 : 0] pre_idx_valid_comb;
    
    // counting the number of PRE available in front of the queues
    wire [1 : 0] pre_count_comb;
    
    // NOP command to be used in the resolve stage
    cmd_packet_t nop_cmd_comb;
    assign nop_cmd_comb = {`NOP, {CMD_ADDR_WDITH{1'b0}}, {DATA_PTR_WIDTH{1'b0}}};

    // genvars for rank_total, bank_total, and sub_cycle generate loops
    genvar rt;
    genvar bt;
    genvar sc;
	
    // outputs of the time machinery module
    wire [NUM_BNK_TOT - 1 : 0] [3 : 0] [TIME_WIDTH - 1 : 0] cmd_counter_intra_bank_comb;
    wire [NUM_BNK_TOT - 1 : 0] [3 : 0] [TIME_WIDTH - 1 : 0] cmd_counter_inter_bank_comb;
    wire [NUM_RNK - 1 : 0] [TIME_WIDTH - 1 : 0] faw_counter_last_comb;
    wire [NUM_CH * NUM_RNK * NUM_BG * NUM_BNK - 1 : 0] [TIME_WIDTH - 1 : 0] ras_counter_comb;
    
    //---------------------------------------------------
    //--------------- Initial Assignments ---------------
    //---------------------------------------------------
    
    // assign front command of each queue i to the queues_front_comb[i]
    generate
        for(bt = 0; bt < NUM_BNK_TOT; bt = bt + 1) begin
            assign queues_front_comb[bt] = {i_cmd[bt],
                                           {i_channel[bt], i_rank[bt], i_bgroup[bt], i_bank[bt], i_row[bt], i_column[bt]},
                                           i_data_ptr[bt]};
        end
    endgenerate
    
    // assign valid signal of each queue to queues_front_valid_comb signal
    assign queues_front_valid_comb = i_valid;
    
    //---------------------------------------------------
    //------- Cycle-specific Ready-to-issue Logic -------
    //---------------------------------------------------
    
    // each index bt at cas_sc0_ready_comb indicate that there is a CAS in front of queue bt, which can be issued at sub-cycle 0
    // each index bt at act_sc1_ready_comb indicate that there is an ACT in front of queue bt, which can be issued at sub-cycle 1
    // same applies to the other three
    generate
        for(bt = 0; bt < NUM_BNK_TOT; bt = bt + 1) begin
            // locate sc0_ready PRE
            assign pre_sc0_ready_comb[bt] = (queues_front_valid_comb[bt] == 1'b1 && queues_front_comb[bt].cmd == `PRE && cmd_counter_intra_bank_comb[bt][0] == 'd0 && cmd_counter_inter_bank_comb[bt][0] == 'd0 && ras_counter_comb[bt] == 'd0) ? 1'b1 : 1'b0;
            // locate sc2_ready CAS
            assign cas_sc2_ready_comb[bt] = ((queues_front_valid_comb[bt] == 1'b1 && i_block_cas == 1'b0) &&
                                            (((queues_front_comb[bt].cmd == `CASRD || queues_front_comb[bt].cmd == `CASRDA) && cmd_counter_intra_bank_comb[bt][2] <= 'd2 && cmd_counter_inter_bank_comb[bt][2] <= 'd2) ||
                                            ((queues_front_comb[bt].cmd == `CASWR || queues_front_comb[bt].cmd == `CASWRA) && cmd_counter_intra_bank_comb[bt][3] <= 'd2 && cmd_counter_inter_bank_comb[bt][3] <= 'd2)))
                                            ? 1'b1 : 1'b0;
            // locate sc3_ready ACT
            `ifndef OMIT_TFAW_COUNTER
            assign act_sc3_ready_comb[bt] = (queues_front_valid_comb[bt] == 1'b1 && queues_front_comb[bt].cmd == `ACT && cmd_counter_intra_bank_comb[bt][1] <= 'd3 && cmd_counter_inter_bank_comb[bt][1] <= 'd3 && faw_counter_last_comb[queues_front_comb[bt].addr.rank] <= 'd3) ? 1'b1 : 1'b0;
            `elsif OMIT_TFAW_COUNTER
            assign act_sc3_ready_comb[bt] = (queues_front_valid_comb[bt] == 1'b1 && queues_front_comb[bt].cmd == `ACT && cmd_counter_intra_bank_comb[bt][1] <= 'd3 && cmd_counter_inter_bank_comb[bt][1] <= 'd3) ? 1'b1 : 1'b0;
            `endif
        end
    endgenerate
    
    //---------------------------------------------------
    //--------------- Pick CAS Candidates ---------------
    //---------------------------------------------------
     
    // round-robin arbiter for the second CAS that can be issue at sub-cycle 2    
    rr_arbiter#(
        .VECTOR_WIDTH(NUM_BNK_TOT),
        .PTR_WIDTH(TOT_BNK_SEL_WIDTH),
        .TCQ(TCQ)
        ) rr_arbiter_cas_sc2 (
        .i_clk(i_clk),
        .i_rstn(i_rstn),
        .i_vector(cas_sc2_ready_comb),
        .o_winner(cas_idx_sc2_comb),
        .o_winner_valid(cas_idx_sc2_valid_comb)
    );
    
    //---------------------------------------------------
    //--------------- Pick ACT Candidates ---------------
    //---------------------------------------------------
    
    // round-robin arbiter for the second ACT that can be issue at sub-cycle 3     
    rr_arbiter#(
        .VECTOR_WIDTH(NUM_BNK_TOT),
        .PTR_WIDTH(TOT_BNK_SEL_WIDTH),
        .TCQ(TCQ)
        ) rr_arbiter_act_sc3 (
        .i_clk(i_clk),
        .i_rstn(i_rstn),
        .i_vector(act_sc3_ready_comb),
        .o_winner(act_idx_sc3_comb),
        .o_winner_valid(act_idx_sc3_valid_comb)
    );
    
    //---------------------------------------------------
    //--------------- Pick PRE Candidates ---------------
    //---------------------------------------------------    
    
    // pick the index of first PRE
    priority_encoder#(
        .VECTOR_WIDTH(NUM_BNK_TOT),
        .PTR_WIDTH(TOT_BNK_SEL_WIDTH),
        .ENCODER_PRIORITY("LSB_FIRST")
        ) priority_encoder_pre0 (
        .i_vector(pre_sc0_ready_comb),
        .o_idx(pre_idx_comb[0]),
        .o_valid(pre_idx_valid_comb[0])
    );
    
    // pick the index of second PRE
    priority_encoder#(
        .VECTOR_WIDTH(NUM_BNK_TOT),
        .PTR_WIDTH(TOT_BNK_SEL_WIDTH),
        .ENCODER_PRIORITY("MSB_FIRST")
        ) priority_encoder_pre1 (
        .i_vector(pre_sc0_ready_comb),
        .o_idx(pre_idx_comb[1]),
        .o_valid(pre_idx_valid_comb[1])
    );
    
    // assign the number of available PRE
    assign pre_count_comb = ((pre_idx_valid_comb[0] == 1'b1) && (pre_idx_comb[0] == pre_idx_comb[1])) ? 2'd1 :
                            ((pre_idx_valid_comb[0] == 1'b1) && (pre_idx_comb[0] != pre_idx_comb[1])) ? 2'd2 :
                            2'd0;
    
    //---------------------------------------------------
    //------------------ Resolve Stage ------------------
    //---------------------------------------------------
    
    assign slots_comb[0] = (pre_count_comb == 2'd1 || pre_count_comb == 2'd2) ? queues_front_comb[pre_idx_comb[0]] :
                           nop_cmd_comb;
    assign slots_comb[1] = (pre_count_comb == 2'd2) ? queues_front_comb[pre_idx_comb[1]] :
                           nop_cmd_comb;
    assign slots_comb[2] = (cas_idx_sc2_valid_comb == 1'b1) ? queues_front_comb[cas_idx_sc2_comb] :
                           nop_cmd_comb;
    assign slots_comb[3] = (act_idx_sc3_valid_comb == 1'b1) ? queues_front_comb[act_idx_sc3_comb] :
                           nop_cmd_comb;
    
    //---------------------------------------------------
    //--------------- Output Assignments ----------------
    //---------------------------------------------------   
            
    // assign all commands of the slots_resolved_comb to the outputs
    generate
        for(sc = 0; sc < 4; sc = sc + 1) begin
            assign {o_cmd[sc],
                   {o_channel[sc], o_rank[sc], o_bgroup[sc], o_bank[sc], o_row[sc], o_column[sc]},
                   o_data_ptr[sc]}
                   = slots_comb[sc];
        end
    endgenerate
    
    //---------------------------------------------------
    //------------------ Dequeue Logic ------------------
    //---------------------------------------------------
            
    // assign dequeue signal for each queue based on the picked commands
    generate
        for(bt = 0; bt < NUM_BNK_TOT; bt = bt + 1) begin
            assign dequeue_comb[bt] = (bt == act_idx_sc3_comb && act_idx_sc3_valid_comb == 1'b1) ? 1'b1 :
                                      (bt == cas_idx_sc2_comb && cas_idx_sc2_valid_comb == 1'b1) ? 1'b1 :
                                      (bt == pre_idx_comb[0] && (pre_count_comb == 2'd1 || pre_count_comb == 2'd2)) ? 1'b1 :
                                      (bt == pre_idx_comb[1] && pre_count_comb == 2'd2) ? 1'b1 :
                                      1'b0;
        end
    endgenerate
    assign o_dequeue = dequeue_comb;    
    
    //---------------------------------------------------
    //-------------- Time Machinary Logic ---------------
    //---------------------------------------------------
    
    // update time machinery after filling all 4 sub-slots (resolved)
    time_machinery#(
    
        .CMD_TYPE_WIDTH(CMD_TYPE_WIDTH),
    
        .NUM_CH(NUM_CH),
        .NUM_RNK(NUM_RNK),
        .NUM_BG(NUM_BG),
        .NUM_BNK(NUM_BNK),
        
        .CH_SEL_WIDTH(CH_SEL_WIDTH),
        .RNK_SEL_WIDTH(RNK_SEL_WIDTH),
        .BG_SEL_WIDTH(BG_SEL_WIDTH),
        .BNK_SEL_WIDTH(BNK_SEL_WIDTH),
        
        .TIME_WIDTH(TIME_WIDTH),
        
        .TCQ(TCQ)
        
        ) time_machinery_inst (
    
        .i_clk(i_clk),
        .i_rstn(i_rstn),
    
        .i_sel_cmd0_type(slots_comb[0].cmd),
        .i_sel_cmd0_rnk(slots_comb[0].addr.rank),
    	.i_sel_cmd0_bg(slots_comb[0].addr.bgroup),
    	.i_sel_cmd0_bnk(slots_comb[0].addr.bank),
    	
    	.i_sel_cmd1_type(slots_comb[1].cmd),
        .i_sel_cmd1_rnk(slots_comb[1].addr.rank),
    	.i_sel_cmd1_bg(slots_comb[1].addr.bgroup),
    	.i_sel_cmd1_bnk(slots_comb[1].addr.bank),
    	
    	.i_sel_cmd2_type(slots_comb[2].cmd),
        .i_sel_cmd2_rnk(slots_comb[2].addr.rank),
    	.i_sel_cmd2_bg(slots_comb[2].addr.bgroup),
    	.i_sel_cmd2_bnk(slots_comb[2].addr.bank),
    	
    	.i_sel_cmd3_type(slots_comb[3].cmd),
        .i_sel_cmd3_rnk(slots_comb[3].addr.rank),
    	.i_sel_cmd3_bg(slots_comb[3].addr.bgroup),
    	.i_sel_cmd3_bnk(slots_comb[3].addr.bank),
    	
	    .i_sel_act_idx(2'd3),
	    .i_sel_act_idx_valid(act_idx_sc3_valid_comb),
	
        .i_sel_cas_idx(2'd2),
        .i_sel_cas_idx_valid(cas_idx_sc2_valid_comb),
        
        .o_cmd_counter_intra_bank(cmd_counter_intra_bank_comb),
        .o_cmd_counter_inter_bank(cmd_counter_inter_bank_comb),
        
        .o_faw_counter_last(faw_counter_last_comb),
        .o_ras_counter(ras_counter_comb)
    );
    
endmodule
