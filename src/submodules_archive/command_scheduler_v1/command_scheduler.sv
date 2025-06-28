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

`ifdef USE_RELATIVE_PATH_INCLUDES
    `include "./time_machinery.sv"
    `include "./cmd_arbiter.sv"
    `include "./comparator.sv"
`endif // `ifdef USE_RELATIVE_PATH_INCLUDES


module command_scheduler#(

    parameter CMD_TYPE_WIDTH    = 3,
	
    parameter NUM_CH            = 1,
    parameter NUM_RNK           = 1,
    parameter NUM_BG            = 2,
    parameter NUM_BNK           = 4,

    parameter CH_SEL_WIDTH	= 1,
    parameter RNK_SEL_WIDTH	= 1,
    parameter BG_SEL_WIDTH	= 2,
    parameter BNK_SEL_WIDTH	= 2,
    parameter ROW_SEL_WIDTH	= 16,
    parameter COL_SEL_WIDTH	= 10,
    
    parameter DATA_PTR_WIDTH = 5,
    
    parameter TIME_WIDTH = 6,
    
    parameter TCQ        = 100
    
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
    output [3 : 0] [CMD_TYPE_WIDTH - 1 : 0] o_cmd,

    // indicate the slot in which the periodic read is injected, if exists
    output   wire                    o_sel_inj0,
    output   wire                    o_sel_inj2
    );

    localparam PTTRN_WIDTH = 4;
    localparam PTR_WIDTH   = DATA_PTR_WIDTH;
    localparam NUM_BNK_TOT = NUM_CH*NUM_RNK*NUM_BG*NUM_BNK;
    localparam NUM_RNK_TOT = NUM_CH*NUM_RNK;

    localparam ADDR_WIDTH = CH_SEL_WIDTH + RNK_SEL_WIDTH + BG_SEL_WIDTH + BNK_SEL_WIDTH + ROW_SEL_WIDTH + COL_SEL_WIDTH;  
    // localparam QWIDTH = 1 /* no cmd bit */ + CMD_TYPE_WIDTH + PTTRN_WIDTH + DATA_PTR_WIDTH + ADDR_WIDTH;
    localparam QWIDTH = CMD_TYPE_WIDTH + PTTRN_WIDTH + PTR_WIDTH + ADDR_WIDTH;

    // ADDR INDICES 
    localparam ACOL_LSB = 0;
    localparam ACOL_MSB = ACOL_LSB + COL_SEL_WIDTH -1;
    localparam AROW_LSB = ACOL_MSB + 1;
    localparam AROW_MSB = AROW_LSB + ROW_SEL_WIDTH -1;
    localparam ABNK_LSB = AROW_MSB + 1;
    localparam ABNK_MSB = ABNK_LSB + BNK_SEL_WIDTH -1;
    localparam ABG_LSB = ABNK_MSB + 1;
    localparam ABG_MSB = ABG_LSB + BG_SEL_WIDTH -1;
    localparam ARNK_LSB = ABG_MSB + 1;
    localparam ARNK_MSB = ARNK_LSB + RNK_SEL_WIDTH -1;
    localparam ACH_LSB = ARNK_MSB + 1;
    localparam ACH_MSB = ACH_LSB + CH_SEL_WIDTH -1;


    // QUEUE INDICES
    localparam QADDR_LSB = 0;
    localparam QADDR_MSB = QADDR_LSB + ADDR_WIDTH - 1;
    localparam QDPTR_LSB = QADDR_MSB + 1;
    localparam QDPTR_MSB = QDPTR_LSB + PTR_WIDTH - 1;
    localparam QPTRN_LSB = QDPTR_MSB + 1;
    localparam QPTRN_MSB = QPTRN_LSB + 4 - 1;
    localparam QTYPE_LSB = QPTRN_MSB + 1;
    localparam QTYPE_MSB = QTYPE_LSB + CMD_TYPE_WIDTH - 1;
    // localparam QNOP_LSB = QTYPE_MSB + 1;
    // localparam QNOP_MSB = QTYPE_LSB + 1 - 1;


    // last subcycle selected address
    reg   [RNK_SEL_WIDTH-1:0] sel_rnk_ls;
    reg   [BG_SEL_WIDTH-1:0] sel_bg_ls;
    reg   [BNK_SEL_WIDTH-1:0] sel_bnk_ls;
    reg   [CMD_TYPE_WIDTH-1:0] sel_cmd_ls;



    // temporary wires to design the logic in a organized way
    // wire [CH_SEL_WIDTH-1:0] ch [0:NUM_BNK_TOT-1];
    // wire [RNK_SEL_WIDTH-1:0] rank [0:NUM_BNK_TOT-1];
    // wire [BG_SEL_WIDTH-1:0] bg [0:NUM_BNK_TOT-1];
    // wire [BNK_SEL_WIDTH-1:0] bank [0:NUM_BNK_TOT-1];
    // wire [ROW_SEL_WIDTH-1:0] row [0:NUM_BNK_TOT-1];
    // wire [COL_SEL_WIDTH-1:0] col [0:NUM_BNK_TOT-1];
    // wire [DATA_PTR_WIDTH-1:0] dptr [0:NUM_BNK_TOT-1];
    // wire [3:0] pattern [0:NUM_BNK_TOT-1];
    // wire [CMD_TYPE_WIDTH-1:0] cmd [NUM_BNK_TOT-1:0];



    wire [NUM_BNK_TOT-1:0] tv_f0;
    wire [NUM_BNK_TOT-1:0] tv_f1;
    wire [NUM_BNK_TOT-1:0] tv_f2;
    wire [NUM_BNK_TOT-1:0] tv_f3;
    wire [NUM_BNK_TOT-1:0] fv_f0;
    wire [NUM_BNK_TOT-1:0] fv_f1;
    wire [NUM_BNK_TOT-1:0] fv_f2;
    wire [NUM_BNK_TOT-1:0] fv_f3;


    // registers and wire sel ptr implementation
    wire [ADDR_WIDTH-1:0] addr [0:NUM_BNK_TOT-1];
    wire [QWIDTH-1:0] queue [0:NUM_BNK_TOT-1];

    wire [QWIDTH-1:0] cmd_pick0;
    wire [QWIDTH-1:0] cmd_pick1;
    wire [QWIDTH-1:0] cmd_pick2;
    wire [QWIDTH-1:0] cmd_pick3;

    wire [ADDR_WIDTH-1:0] addr_pick0;
    wire [ADDR_WIDTH-1:0] addr_pick1;
    wire [ADDR_WIDTH-1:0] addr_pick2;
    wire [ADDR_WIDTH-1:0] addr_pick3;

    reg [3:0] pattern_ls;
    wire [3:0] pattern_pick0;
    wire [3:0] pattern_pick1;
    wire [3:0] pattern_pick2;
    wire [3:0] pattern_pick3;
    // round robin pointer
    reg [NUM_BNK_TOT-1:0] rr_ptr;
    wire [NUM_BNK_TOT-1:0] rr_ptr0;
    wire [NUM_BNK_TOT-1:0] rr_ptr1;
    wire [NUM_BNK_TOT-1:0] rr_ptr2;
    wire [NUM_BNK_TOT-1:0] rr_ptr3;
    wire [NUM_BNK_TOT-1:0] rr_ptr_ns;
    // bank valid flag, 0 is valid
    wire [NUM_BNK_TOT-1:0] bv_f0;
    wire [NUM_BNK_TOT-1:0] bv_f1;
    wire [NUM_BNK_TOT-1:0] bv_f2;
    wire [NUM_BNK_TOT-1:0] bv_f3;
    wire [NUM_BNK_TOT-1:0] bv_f4;
    wire [NUM_BNK_TOT-1:0] bv_f_ns;
    reg [NUM_BNK_TOT-1:0] bv_f;


    //2D array counters hold the remaining time for issuing (0->PRE/1->ACT/2->RD/3->WR) cmds. num of entries equals to the total number of banks
    reg [TIME_WIDTH-1:0] cmd_counter  [NUM_BNK_TOT-1:0][3:0];
    wire [TIME_WIDTH-1:0] cmd_counter0 [NUM_BNK_TOT-1:0][3:0];
    wire [TIME_WIDTH-1:0] cmd_counter1 [NUM_BNK_TOT-1:0][3:0];
    wire [TIME_WIDTH-1:0] cmd_counter2 [NUM_BNK_TOT-1:0][3:0];
    wire [TIME_WIDTH-1:0] cmd_counter3 [NUM_BNK_TOT-1:0][3:0];
    wire [TIME_WIDTH-1:0] cmd_counter_ns [NUM_BNK_TOT-1:0][3:0];

    reg [TIME_WIDTH-1:0] tfaw_counter [NUM_RNK_TOT-1:0][3:0];
    wire [TIME_WIDTH-1:0] tfaw_counter0 [NUM_RNK_TOT-1:0][3:0];
    wire [TIME_WIDTH-1:0] tfaw_counter1 [NUM_RNK_TOT-1:0][3:0];
    wire [TIME_WIDTH-1:0] tfaw_counter2 [NUM_RNK_TOT-1:0][3:0];
    wire [TIME_WIDTH-1:0] tfaw_counter3 [NUM_RNK_TOT-1:0][3:0];
    wire [TIME_WIDTH-1:0] tfaw_counter_ns [NUM_RNK_TOT-1:0][3:0];

    wire [TIME_WIDTH-1:0] tfaw_counter_last_ls [NUM_RNK_TOT-1:0];
    wire [TIME_WIDTH-1:0] tfaw_counter_last0 [NUM_RNK_TOT-1:0];
    wire [TIME_WIDTH-1:0] tfaw_counter_last1 [NUM_RNK_TOT-1:0];
    wire [TIME_WIDTH-1:0] tfaw_counter_last2 [NUM_RNK_TOT-1:0];
    wire [TIME_WIDTH-1:0] tfaw_counter_last3 [NUM_RNK_TOT-1:0];



    reg [3:0] tfaw_valid [NUM_RNK_TOT-1:0]; 
    wire  [3:0] tfaw_valid_ls [NUM_RNK_TOT-1:0];
    wire  [3:0] tfaw_valid0 [NUM_RNK_TOT-1:0];
    wire  [3:0] tfaw_valid1 [NUM_RNK_TOT-1:0];
    wire  [3:0] tfaw_valid2 [NUM_RNK_TOT-1:0];
    wire  [3:0] tfaw_valid3 [NUM_RNK_TOT-1:0];
    wire  [3:0] tfaw_valid_ns [NUM_RNK_TOT-1:0];

    wire  tfaw_valid_last_ls [NUM_RNK_TOT-1:0];
    wire  tfaw_valid_last0 [NUM_RNK_TOT-1:0];
    wire  tfaw_valid_last1 [NUM_RNK_TOT-1:0];
    wire  tfaw_valid_last2 [NUM_RNK_TOT-1:0];
    wire  tfaw_valid_last3 [NUM_RNK_TOT-1:0];


    wire [NUM_BNK_TOT-1:0]  cas_mask;
    wire [NUM_BNK_TOT-1:0]  cas_mask_and_periodic_read;
    wire [NUM_BNK_TOT-1:0]  q_valid_and_blocked_cas;

    reg [NUM_CH * NUM_RNK * NUM_BG * NUM_BNK - 1 : 0] [4-1:0] q_pattern;

    genvar bnk_g;
    generate
    for(bnk_g=0; bnk_g<NUM_BNK_TOT; bnk_g = bnk_g + 1) begin
        always @(*) begin
            case (i_cmd[bnk_g])
                `PRE                                :   q_pattern[bnk_g] = 4'b0000;
                `ACT                                :   q_pattern[bnk_g] = 4'b0010;
                `CASRD, `CASRDA, `CASWR, `CASWRA    :   q_pattern[bnk_g] = 4'b0011;
                default                             :   q_pattern[bnk_g] = 4'b0000;
            endcase
        end
    end
   endgenerate


    /* ORGANIZING QUEUES' INPUTS */
    genvar bt, i, ctr, j, r, gen_r;
    // generate
    //     for(bt = 0; bt< NUM_BNK_TOT; bt = bt + 1)
    //     begin
    //         assign ch[bt] = i_channel[bt*CH_SEL_WIDTH +: CH_SEL_WIDTH];
    //         assign rank[bt] = i_rank[bt*RNK_SEL_WIDTH +: RNK_SEL_WIDTH];
    //         assign bg[bt] = i_bgroup[bt*BG_SEL_WIDTH +: BG_SEL_WIDTH];
    //         assign bank[bt] = i_bank[bt*BNK_SEL_WIDTH +: BNK_SEL_WIDTH];
    //         assign row[bt] = i_row[bt*ROW_SEL_WIDTH +: ROW_SEL_WIDTH];
    //         assign col[bt] = i_column[bt*COL_SEL_WIDTH +: COL_SEL_WIDTH];
    //         assign dptr[bt] = i_data_ptr[bt*DATA_PTR_WIDTH +: DATA_PTR_WIDTH];
    //         assign pattern[bt] = q_pattern[bt*4 +: 4];
    //         assign cmd[bt] = i_cmd[bt*CMD_TYPE_WIDTH +: CMD_TYPE_WIDTH];
    //     end
    // endgenerate


    /* ENCAPSULATING COMMAND */
    generate
        for(bt = 0; bt < NUM_BNK_TOT; bt = bt + 1)
        begin : caps_bank
            assign addr[bt] = {i_channel[bt], i_rank[bt], i_bgroup[bt], i_bank[bt], i_row[bt], i_column[bt]};
            assign queue[bt] = {i_cmd[bt], q_pattern[bt], i_data_ptr[bt], addr[bt]}; 
            assign cas_mask[bt] = (i_cmd[bt] == `CASRD) | (i_cmd[bt] == `CASRDA) | (i_cmd[bt] == `CASWR) | (i_cmd[bt] == `CASWRA);
        end
    endgenerate

    assign cas_mask_and_periodic_read   = i_block_cas ? cas_mask : {NUM_BNK_TOT{1'b0}};
    assign q_valid_and_blocked_cas      = i_valid & ~cas_mask_and_periodic_read;

    //////////////////////////////////////////////////////////////////////////
    //                              PHASE 0                                 //
    //////////////////////////////////////////////////////////////////////////

    assign rr_ptr0 = rr_ptr;
    // assign cmd_counter0 = cmd_counter;
    // assign tfaw_counter0 = tfaw_counter;
    // assign tfaw_valid0 = tfaw_valid;

    generate
        for(gen_r = 0; gen_r<NUM_RNK; gen_r = gen_r + 1)
        begin : tfaw_rank0
            assign tfaw_counter_last_ls[gen_r] = tfaw_counter[gen_r][3];
            assign tfaw_valid_last_ls[gen_r] = tfaw_valid[gen_r][3];
        end
    endgenerate



    time_machinery#(
    	.NUM_RNK(NUM_RNK),
    	.NUM_BG(NUM_BG),
    	.NUM_BNK(NUM_BNK),
    	.RNK_SEL_WIDTH(RNK_SEL_WIDTH),
    	.BG_SEL_WIDTH(BG_SEL_WIDTH),
    	.BNK_SEL_WIDTH(BNK_SEL_WIDTH),
    	.CMD_TYPE_WIDTH(CMD_TYPE_WIDTH),
        .NOP_BITS(`NOP),
        .PRE_BITS(`PRE),
        .ACT_BITS(`ACT),
        .RD_BITS(`CASRD),
        .WR_BITS(`CASWR),
        .RDA_BITS(`CASRDA),
        .WRA_BITS(`CASWRA),
        .PREA_BITS(3'b111),
        .TIME_CONSTRAINT_WIDTH(TIME_WIDTH)
    )time_machinery_ins0(
        .sel_cmd(sel_cmd_ls),
    	.sel_rnk(sel_rnk_ls),
    	.sel_bg(sel_bg_ls),
    	.sel_bnk(sel_bnk_ls),
    	.cmd_counter_i(cmd_counter),
    	.faw_counter_i(tfaw_counter),
        .faw_valid_i(tfaw_valid),
    	.cmd_counter_o(cmd_counter0),
    	.faw_counter_o(tfaw_counter0),
        .faw_valid_o(tfaw_valid0)
        );




    // Timing Validity flag, 0 is valid
    comparator#(
        .NUM_BNK_TOT(NUM_BNK_TOT),
        .NUM_RNK_TOT(NUM_RNK_TOT),
        .CMD_TYPE_WIDTH(CMD_TYPE_WIDTH),
        .TIME_WIDTH(TIME_WIDTH),
        .compare_value(1)
    ) cmd_cmp0 (
        .cmd(i_cmd),
        .cmd_counter(cmd_counter),
        .tfaw_counter(tfaw_counter_last_ls),
        .pattern(pattern_ls),
        .tfaw_valid(tfaw_valid_last_ls),
        .tv_f(tv_f0)
    );

    assign fv_f0 = q_valid_and_blocked_cas & tv_f0 & bv_f;

    cmd_arbiter#(
        .NUM_BNK_TOT(NUM_BNK_TOT),
        .QTYPE_LSB(QTYPE_LSB),
        .QTYPE_MSB(QTYPE_MSB),
        .CMD_TYPE_WIDTH(CMD_TYPE_WIDTH),
        .QWIDTH(QWIDTH),
        .CARRY8("ENABLE"),
        .MODE("TWOS")
    )cmd_arbiter0(
        .final_flag(fv_f0),
        .cmd_queue(queue),
        .rr_ptr_i(rr_ptr0),
        .rr_ptr_o(rr_ptr1),
        .cmd_pick(cmd_pick0),
        .bank_flag_i(bv_f),
        .sel_bank(bv_f1),
        .bank_flag_o()
        );


    assign o_cmd[0]         = cmd_pick0[QTYPE_MSB:QTYPE_LSB];
    assign pattern_pick0    = cmd_pick0[QPTRN_MSB:QPTRN_LSB];
    assign addr_pick0       = cmd_pick0[QADDR_MSB:QADDR_LSB];
    assign o_channel[0]          = addr_pick0[ACH_MSB:ACH_LSB];
    assign o_rank[0]         = addr_pick0[ARNK_MSB:ARNK_LSB];
    assign o_bgroup[0]          = addr_pick0[ABG_MSB:ABG_LSB];
    assign o_bank[0]         = addr_pick0[ABNK_MSB:ABNK_LSB];
    assign o_row[0]         = addr_pick0[AROW_MSB:AROW_LSB];
    assign o_column[0]         = addr_pick0[ACOL_MSB:ACOL_LSB];
    assign o_data_ptr[0]        = cmd_pick0[QADDR_MSB+1 +: DATA_PTR_WIDTH];
    assign o_sel_inj0         = cmd_pick0[QADDR_MSB+1];

    //////////////////////////////////////////////////////////////////////////
    //                              PHASE 1                                 //
    //////////////////////////////////////////////////////////////////////////


    generate
        for(gen_r = 0; gen_r<NUM_RNK; gen_r = gen_r + 1)
        begin
            assign tfaw_counter_last0[gen_r] = tfaw_counter0[gen_r][3];
            assign tfaw_valid_last0[gen_r] = tfaw_valid0[gen_r][3];
        end
    endgenerate


    time_machinery#(
    	.NUM_RNK(NUM_RNK),
    	.NUM_BG(NUM_BG),
    	.NUM_BNK(NUM_BNK),
    	.RNK_SEL_WIDTH(RNK_SEL_WIDTH),
    	.BG_SEL_WIDTH(BG_SEL_WIDTH),
    	.BNK_SEL_WIDTH(BNK_SEL_WIDTH),
    	.CMD_TYPE_WIDTH(CMD_TYPE_WIDTH),
        .NOP_BITS(`NOP),
        .PRE_BITS(`PRE),
        .ACT_BITS(`ACT),
        .RD_BITS(`CASRD),
        .WR_BITS(`CASWR),
        .RDA_BITS(`CASRDA),
        .WRA_BITS(`CASWRA),
        .PREA_BITS(3'b111),
        .TIME_CONSTRAINT_WIDTH(TIME_WIDTH)
    )time_machinery_ins1(
        .sel_cmd(o_cmd[0]),
    	.sel_rnk(o_rank[0]),
    	.sel_bg(o_bgroup[0]),
    	.sel_bnk(o_bank[0]),
    	.cmd_counter_i(cmd_counter0),
    	.faw_counter_i(tfaw_counter0),
        .faw_valid_i(tfaw_valid0),
    	.cmd_counter_o(cmd_counter1),
    	.faw_counter_o(tfaw_counter1),
        .faw_valid_o(tfaw_valid1)
        );

    // Timing Validity flag, 0 is valid
    comparator#(
        .NUM_BNK_TOT(NUM_BNK_TOT),
        .NUM_RNK_TOT(NUM_RNK_TOT),
        .CMD_TYPE_WIDTH(CMD_TYPE_WIDTH),
        .TIME_WIDTH(TIME_WIDTH),
        .CAS_EN("DISABLE"),
        .compare_value(1)
    ) cmd_cmp1 (

        .cmd(i_cmd),
        .cmd_counter(cmd_counter0),
        .tfaw_counter(tfaw_counter_last0),
        .pattern(pattern_pick0),
        .tfaw_valid(tfaw_valid_last0),
        .tv_f(tv_f1)
    );

    assign fv_f1 = q_valid_and_blocked_cas & tv_f1 & bv_f1 ;

    cmd_arbiter#(
        .NUM_BNK_TOT(NUM_BNK_TOT),
        .QTYPE_LSB(QTYPE_LSB),
        .QTYPE_MSB(QTYPE_MSB),
        .CMD_TYPE_WIDTH(CMD_TYPE_WIDTH),
        .QWIDTH(QWIDTH),
        .CARRY8("ENABLE"),
        .MODE("TWOS")
    )cmd_arbiter1(
        .final_flag(fv_f1),
        .cmd_queue(queue),
        .rr_ptr_i(rr_ptr1),
        .rr_ptr_o(rr_ptr2),
        .cmd_pick(cmd_pick1),
        .bank_flag_i(bv_f1),
        .sel_bank(),
        .bank_flag_o(bv_f2)
        );

    assign o_cmd[1] = cmd_pick1[QTYPE_MSB:QTYPE_LSB];
    assign pattern_pick1 = cmd_pick1[QPTRN_MSB:QPTRN_LSB];
    assign addr_pick1 = cmd_pick1[QADDR_MSB:QADDR_LSB];
    assign o_channel[1] = addr_pick1[ACH_MSB:ACH_LSB];
    assign o_rank[1] = addr_pick1[ARNK_MSB:ARNK_LSB];
    assign o_bgroup[1] = addr_pick1[ABG_MSB:ABG_LSB];
    assign o_bank[1] = addr_pick1[ABNK_MSB:ABNK_LSB];
    assign o_row[1] = addr_pick1[AROW_MSB:AROW_LSB];
    assign o_column[1] = addr_pick1[ACOL_MSB:ACOL_LSB];
    assign o_data_ptr[1] = {DATA_PTR_WIDTH{1'b0}};


    //////////////////////////////////////////////////////////////////////////
    //                              PHASE 2                                 //
    //////////////////////////////////////////////////////////////////////////


    generate
        for(gen_r = 0; gen_r<NUM_RNK; gen_r = gen_r + 1)
        begin
            assign tfaw_counter_last1[gen_r] = tfaw_counter1[gen_r][3];
            assign tfaw_valid_last1[gen_r] = tfaw_valid1[gen_r][3];
        end
    endgenerate


    time_machinery#(
    	.NUM_RNK(NUM_RNK),
    	.NUM_BG(NUM_BG),
    	.NUM_BNK(NUM_BNK),
    	.RNK_SEL_WIDTH(RNK_SEL_WIDTH),
    	.BG_SEL_WIDTH(BG_SEL_WIDTH),
    	.BNK_SEL_WIDTH(BNK_SEL_WIDTH),
    	.CMD_TYPE_WIDTH(CMD_TYPE_WIDTH),
        .NOP_BITS(`NOP),
        .PRE_BITS(`PRE),
        .ACT_BITS(`ACT),
        .RD_BITS(`CASRD),
        .WR_BITS(`CASWR),
        .RDA_BITS(`CASRDA),
        .WRA_BITS(`CASWRA),
        .PREA_BITS(3'b111),
        .TIME_CONSTRAINT_WIDTH(TIME_WIDTH)
    )time_machinery_ins2(
        .sel_cmd(o_cmd[1]),
    	.sel_rnk(o_rank[1]),
    	.sel_bg(o_bgroup[1]),
    	.sel_bnk(o_bank[1]),
    	.cmd_counter_i(cmd_counter1),
    	.faw_counter_i(tfaw_counter1),
        .faw_valid_i(tfaw_valid1),
    	.cmd_counter_o(cmd_counter2),
    	.faw_counter_o(tfaw_counter2),
        .faw_valid_o(tfaw_valid2)
        );

    // Timing Validity flag, 0 is valid
    comparator#(
        .NUM_BNK_TOT(NUM_BNK_TOT),
        .NUM_RNK_TOT(NUM_RNK_TOT),
        .CMD_TYPE_WIDTH(CMD_TYPE_WIDTH),
        .TIME_WIDTH(TIME_WIDTH),
        .compare_value(1)
    ) cmd_cmp2(
        .cmd(i_cmd),
        .cmd_counter(cmd_counter1),
        .tfaw_counter(tfaw_counter_last1),
        .pattern(pattern_pick1),
        .tfaw_valid(tfaw_valid_last1),
        .tv_f(tv_f2)
    );

    assign fv_f2 = q_valid_and_blocked_cas & tv_f2 & bv_f2 ;

    cmd_arbiter#(
        .NUM_BNK_TOT(NUM_BNK_TOT),
        .QTYPE_LSB(QTYPE_LSB),
        .QTYPE_MSB(QTYPE_MSB),
        .CMD_TYPE_WIDTH(CMD_TYPE_WIDTH),
        .QWIDTH(QWIDTH),
        .CARRY8("ENABLE"),
        .MODE("TWOS")
    )cmd_arbiter2(
        .final_flag(fv_f2),
        .cmd_queue(queue),
        .rr_ptr_i(rr_ptr2),
        .rr_ptr_o(rr_ptr3),
        .cmd_pick(cmd_pick2),
        .bank_flag_i(bv_f2),
        .sel_bank(),
        .bank_flag_o(bv_f3)
        );



    assign o_cmd[2] = cmd_pick2[QTYPE_MSB:QTYPE_LSB];
    assign pattern_pick2 = cmd_pick2[QPTRN_MSB:QPTRN_LSB];
    assign addr_pick2 = cmd_pick2[QADDR_MSB:QADDR_LSB];
    assign o_channel[2] = addr_pick2[ACH_MSB:ACH_LSB];
    assign o_rank[2] = addr_pick2[ARNK_MSB:ARNK_LSB];
    assign o_bgroup[2] = addr_pick2[ABG_MSB:ABG_LSB];
    assign o_bank[2] = addr_pick2[ABNK_MSB:ABNK_LSB];
    assign o_row[2] = addr_pick2[AROW_MSB:AROW_LSB];
    assign o_column[2] = addr_pick2[ACOL_MSB:ACOL_LSB];
    assign o_data_ptr[2]        = cmd_pick2[QADDR_MSB+1 +: DATA_PTR_WIDTH];
    assign o_sel_inj2         = cmd_pick2[QADDR_MSB+1];

    //////////////////////////////////////////////////////////////////////////
    //                              PHASE 3                                 //
    //////////////////////////////////////////////////////////////////////////


    generate
        for(gen_r = 0; gen_r<NUM_RNK; gen_r = gen_r + 1)
        begin
            assign tfaw_counter_last2[gen_r] = tfaw_counter2[gen_r][3];
            assign tfaw_valid_last2[gen_r] = tfaw_valid2[gen_r][3];
        end
    endgenerate


    time_machinery#(
    	.NUM_RNK(NUM_RNK),
    	.NUM_BG(NUM_BG),
    	.NUM_BNK(NUM_BNK),
    	.RNK_SEL_WIDTH(RNK_SEL_WIDTH),
    	.BG_SEL_WIDTH(BG_SEL_WIDTH),
    	.BNK_SEL_WIDTH(BNK_SEL_WIDTH),
    	.CMD_TYPE_WIDTH(CMD_TYPE_WIDTH),
        .NOP_BITS(`NOP),
        .PRE_BITS(`PRE),
        .ACT_BITS(`ACT),
        .RD_BITS(`CASRD),
        .WR_BITS(`CASWR),
        .RDA_BITS(`CASRDA),
        .WRA_BITS(`CASWRA),
        .PREA_BITS(3'b111),
        .TIME_CONSTRAINT_WIDTH(TIME_WIDTH)
    )time_machinery_ins3(
        .sel_cmd(o_cmd[2]),
    	.sel_rnk(o_rank[2]),
    	.sel_bg(o_bgroup[2]),
    	.sel_bnk(o_bank[2]),
    	.cmd_counter_i(cmd_counter2),
    	.faw_counter_i(tfaw_counter2),
        .faw_valid_i(tfaw_valid2),
    	.cmd_counter_o(cmd_counter_ns),
    	.faw_counter_o(tfaw_counter_ns),
        .faw_valid_o(tfaw_valid_ns)
        );



    // Timing Validity flag, 0 is valid
    comparator#(
        .NUM_BNK_TOT(NUM_BNK_TOT),
        .NUM_RNK_TOT(NUM_RNK_TOT),
        .CMD_TYPE_WIDTH(CMD_TYPE_WIDTH),
        .TIME_WIDTH(TIME_WIDTH),
        .compare_value(1),
        .CAS_EN("DISABLE")
    ) cmd_cmp3(
        .cmd(i_cmd),
        .cmd_counter(cmd_counter2),
        .tfaw_counter(tfaw_counter_last2),
        .pattern(pattern_pick2),
        .tfaw_valid(tfaw_valid_last2),
        .tv_f(tv_f3)
    );

    assign fv_f3 = q_valid_and_blocked_cas & tv_f3 & bv_f3 ;

    cmd_arbiter#(
        .NUM_BNK_TOT(NUM_BNK_TOT),
        .QTYPE_LSB(QTYPE_LSB),
        .QTYPE_MSB(QTYPE_MSB),
        .CMD_TYPE_WIDTH(CMD_TYPE_WIDTH),
        .QWIDTH(QWIDTH),
        .CARRY8("ENABLE"),
        .MODE("TWOS")
    )cmd_arbiter3(
        .final_flag(fv_f3),
        .cmd_queue(queue),
        .rr_ptr_i(rr_ptr3),
        .rr_ptr_o(rr_ptr_ns),
        .cmd_pick(cmd_pick3),
        .bank_flag_i(bv_f3),
        .sel_bank(bv_f_ns),
        .bank_flag_o(bv_f4)
        );



    assign o_cmd[3] = cmd_pick3[QTYPE_MSB:QTYPE_LSB];
    assign pattern_pick3 = cmd_pick3[QPTRN_MSB:QPTRN_LSB];
    assign addr_pick3 = cmd_pick3[QADDR_MSB:QADDR_LSB];
    assign o_channel[3] = addr_pick3[ACH_MSB:ACH_LSB];
    assign o_rank[3] = addr_pick3[ARNK_MSB:ARNK_LSB];
    assign o_bgroup[3] = addr_pick3[ABG_MSB:ABG_LSB];
    assign o_bank[3] = addr_pick3[ABNK_MSB:ABNK_LSB];
    assign o_row[3] = addr_pick3[AROW_MSB:AROW_LSB];
    assign o_column[3] = addr_pick3[ACOL_MSB:ACOL_LSB];
    assign o_data_ptr[3] = {DATA_PTR_WIDTH{1'b0}};

    // // updating timing table and counters
    // time_machine#(
    //     .NUM_BNK_TOT(NUM_BNK_TOT),
    //     .NUM_RNK_TOT(NUM_RNK_TOT),    

    //     .CH_SEL_WIDTH(CH_SEL_WIDTH),
    // 	.RNK_SEL_WIDTH(RNK_SEL_WIDTH),
    // 	.BG_SEL_WIDTH(BG_SEL_WIDTH),
    // 	.BNK_SEL_WIDTH(BNK_SEL_WIDTH),
    //     .CMD_TYPE_WIDTH(CMD_TYPE_WIDTH),
    //     .TIME_WIDTH(TIME_WIDTH)
    // ) time_machine_inst3 (
    //     .cmd(o_cmd[3]),
    //     .ch(o_channel[3]),
    //     .rank(o_rank[3]),
    //     .bg(o_bgroup[3]),
    //     .bank(o_bank[3]),
    //     .cmd_counter_i(cmd_counter3),
    //     .cmd_counter_o(cmd_counter_ns),
    //     .faw_counter_i(tfaw_counter3),
    //     .faw_counter_o(tfaw_counter_ns),
    //     .faw_valid_i(tfaw_valid3),
    //     .faw_valid_o(tfaw_valid4)
    // );

    //////////////////////////////////////////////////////////////////////////
    //                              UPDATING REGS                           //
    //////////////////////////////////////////////////////////////////////////


    // time_machinery#(
    // 	.NUM_RNK(NUM_RNK),
    // 	.NUM_BG(NUM_BG),
    // 	.NUM_BNK(NUM_BNK),
    // 	.RNK_SEL_WIDTH(RNK_SEL_WIDTH),
    // 	.BG_SEL_WIDTH(BG_SEL_WIDTH),
    // 	.BNK_SEL_WIDTH(BNK_SEL_WIDTH),
    // 	.CMD_TYPE_WIDTH(CMD_TYPE_WIDTH),
    //     .NOP_BITS(`NOP),
    //     .PRE_BITS(`PRE),
    //     .ACT_BITS(`ACT),
    //     .RD_BITS(`CASRD),
    //     .WR_BITS(`CASWR),
    //     .RDA_BITS(`CASRDA),
    //     .WRA_BITS(`CASWRA),
    //     .PREA_BITS(3'b111),
    //     .TIME_CONSTRAINT_WIDTH(TIME_WIDTH)
    // )time_machinery_ins4(
    //     .sel_cmd(o_cmd[3]),
    // 	.sel_rnk(o_rank[3]),
    // 	.sel_bg(o_bgroup[3]),
    // 	.sel_bnk(o_bank[3]),
    // 	.cmd_counter_i(cmd_counter3),
    // 	.faw_counter_i(tfaw_counter3),
    //     .faw_valid_i(tfaw_valid3),
    // 	.cmd_counter_o(cmd_counter_ns),
    // 	.faw_counter_o(tfaw_counter_ns),
    //     .faw_valid_o(tfaw_valid_ns)
    //     );


    // updating registers
    generate
        for(bt = 0; bt< NUM_BNK_TOT; bt++)
        begin
            always @(posedge i_clk) begin
                if(~i_rstn) begin
                    cmd_counter[bt][0] <= #(TCQ) 0;
                    cmd_counter[bt][1] <= #(TCQ) 0;
                    cmd_counter[bt][2] <= #(TCQ) 0;
                    cmd_counter[bt][3] <= #(TCQ) 0;
                end
                else begin
                    cmd_counter[bt][0] <= #(TCQ) cmd_counter_ns[bt][0];
                    cmd_counter[bt][1] <= #(TCQ) cmd_counter_ns[bt][1];
                    cmd_counter[bt][2] <= #(TCQ) cmd_counter_ns[bt][2];
                    cmd_counter[bt][3] <= #(TCQ) cmd_counter_ns[bt][3];
                end
            end
        end
        for(r = 0; r< NUM_RNK_TOT; r++)
        begin
            always @(posedge i_clk) begin
                if(~i_rstn) begin
                    tfaw_counter[r][0] <= #(TCQ) 0;
                    tfaw_counter[r][1] <= #(TCQ) 0;
                    tfaw_counter[r][2] <= #(TCQ) 0;
                    tfaw_counter[r][3] <= #(TCQ) 0;

                    tfaw_valid[r][0] <= #(TCQ) 0;
                    tfaw_valid[r][1] <= #(TCQ) 0;
                    tfaw_valid[r][2] <= #(TCQ) 0;
                    tfaw_valid[r][3] <= #(TCQ) 0;                
                end
                else begin
                
                    tfaw_counter[r][0] <= #(TCQ) tfaw_counter_ns[r][0];
                    tfaw_counter[r][1] <= #(TCQ) tfaw_counter_ns[r][1];
                    tfaw_counter[r][2] <= #(TCQ) tfaw_counter_ns[r][2];
                    tfaw_counter[r][3] <= #(TCQ) tfaw_counter_ns[r][3];

                    tfaw_valid[r][0] <= #(TCQ) tfaw_valid_ns[r][0];
                    tfaw_valid[r][1] <= #(TCQ) tfaw_valid_ns[r][1];
                    tfaw_valid[r][2] <= #(TCQ) tfaw_valid_ns[r][2];
                    tfaw_valid[r][3] <= #(TCQ) tfaw_valid_ns[r][3];
                end
            end
        end
    endgenerate

    always @(posedge i_clk) begin
        if(~i_rstn) begin
            rr_ptr <= #(TCQ) {{(NUM_BNK_TOT-1){1'b0}}, 1'b1};
            sel_bnk_ls  <= #(TCQ) 0;
            sel_bg_ls   <= #(TCQ) 0;
            sel_rnk_ls  <= #(TCQ) 0;
            sel_cmd_ls  <= #(TCQ) `NOP;
            bv_f        <= #(TCQ) {NUM_BNK_TOT{1'b1}};
            pattern_ls  <= #(TCQ) {PTTRN_WIDTH{1'b0}};
        end
        else begin
            rr_ptr      <= #(TCQ) rr_ptr_ns;
            sel_cmd_ls  <= #(TCQ) o_cmd[3];
            sel_rnk_ls  <= #(TCQ) o_rank[3];
            sel_bnk_ls  <= #(TCQ) o_bank[3];
            sel_bg_ls   <= #(TCQ) o_bgroup[3];
            bv_f        <= #(TCQ) bv_f_ns;
            pattern_ls  <= #(TCQ) pattern_pick3;
        end
    end


    assign o_dequeue = ~bv_f4;

endmodule
