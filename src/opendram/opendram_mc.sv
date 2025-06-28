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

`include "./global.svh"

`ifdef USE_RELATIVE_PATH_INCLUDES
    `include "ddr4_v2_2_mc_ctl.sv"
    `include "ddr4_v2_2_mc_periodic.sv"
    `include "ddr4_v2_2_mc_ref.sv"
    `include "ddr4_v2_2_mc_ecc.sv"
    `include "./request_scheduler/request_scheduler_wrapper.sv"
    `include "./command_queue/command_queue_wrapper.sv"
    `include "./page_table/page_table.sv"
    `include "./command_scheduler/command_scheduler.sv"
`endif // `ifdef USE_RELATIVE_PATH_INCLUDES


module opendram_mc#(

     parameter MEM                  = "DDR4"
    ,parameter TCQ                  = 100

    ,parameter NUM_CH               = 1
    ,parameter NUM_RNK              = 1
    ,parameter RANKS                = 1
    ,parameter NUM_BG               = 2
    ,parameter NUM_BNK              = 4
    ,parameter NUM_BNK_TOT          = NUM_CH * NUM_RNK * NUM_BG * NUM_BNK    

    ,parameter CH_WIDTH             = 1
    ,parameter RNK_WIDTH            = 1
    ,parameter BG_WIDTH             = 1
    ,parameter BNK_WIDTH            = 2
    ,parameter ROW_WIDTH            = 18
    ,parameter COL_WIDTH            = 10

    ,parameter S_HEIGHT             = 1
    ,parameter LR_WIDTH             = 1

    ,parameter CKE_WIDTH            = 1
    ,parameter CS_WIDTH             = 1
    ,parameter ABITS                = 18    
    ,parameter BGBITS               = 2
    ,parameter BABITS               = 2
    ,parameter RKBITS               = (NUM_RNK <= 4) ? 2 : 3

    ,parameter DPTR_WIDTH           = 5
    ,parameter CMD_TYPE_WIDTH       = 3
    ,parameter REQ_WIDTH            = 3

    ,parameter ADDR_FIFO_WIDTH      = 52
    ,parameter QUEUE_SIZE           = 2
    ,parameter QUEUE_SIZE_WIDTH     = 5
    ,parameter GFIFO_SIZE           = 8
    
    ,parameter ECC                  = "OFF"
    ,parameter ECC_WIDTH            = 8
    ,parameter PAYLOAD_WIDTH        = 8
    ,parameter PAYLOAD_DM_WIDTH     = 1

    ,parameter ODTWRDEL             = 5'd9
    ,parameter ODTRD                = 16'h0000
    ,parameter ODTWRDUR             = 4'd6
    ,parameter ODTWRODEL            = 5'd9
    ,parameter ODTWRODUR            = 4'd6
    ,parameter ODTRDDUR             = 4'd6
    ,parameter ODTRDODEL            = 5'd9
    ,parameter ODTRDODUR            = 4'd6
    ,parameter ODTNOP               = 16'h0000
    
    ,parameter ODTBITS              = 1
    ,parameter PER_RD_INTVL         = 32'd334
    ,parameter tREFI                = 10400            
    ,parameter tRFC                 = 347     
    ,parameter tRP                  = 18          
    ,parameter tWR                  = 20     
    ,parameter ZQINTVL              = 1333333334          
    ,parameter PARTIAL_RECONFIG     = "Disable"
    ,parameter tCK                  = 750
    ,parameter MR6                  = 13'b0_1100_0001_0100
    ,parameter ODTWR                = 16'h0021
    ,parameter ODTRDDEL             = 5'd18
    
    ,parameter DQ_WIDTH             = 8
    ,parameter DQS_WIDTH            = 1
    ,parameter DM_WIDTH             = 1
    ,parameter nCK_PER_CLK          = 4

    )(
    
     input wire                     clk
    ,input wire                     rst_n
    ,input wire                     calDone 
    ,input wire [5:0]               tCWL

    ,output wire [7:0]              mcCKt 
    ,output wire [7:0]              mcCKc
    ,output wire [7:0]              mc_ACT_n
    ,output wire [7:0]              mc_RAS_n
    ,output wire [7:0]              mc_CAS_n
    ,output wire [7:0]              mc_WE_n
    ,output wire [ABITS*8-1:0]      mc_ADR
    ,output wire [BABITS*8-1:0]     mc_BA
    ,output wire [BGBITS*8-1:0]     mc_BG
    ,output wire [LR_WIDTH*8-1:0]   mc_C
    ,output wire [CKE_WIDTH*8-1:0]    mc_CKE
    ,output wire [CS_WIDTH*8-1:0]     mc_CS_n
    ,output wire [ODTBITS*8-1:0]    mc_ODT

    ,output [1:0]                   casSlot
    ,output                         casSlot2
    ,output                         rdCAS
    ,output                         wrCAS
    ,output [(DPTR_WIDTH) -1:0]     win_data_ptr
    ,output                         winInjTxn
    ,output                         gt_data_ready
    ,output [RKBITS-1:0]            win_rank_cas

    ,output                         ref_ack
    ,output                         zq_ack

    ,output [DQ_WIDTH*8-1:0]        wr_data_mc2phy
    ,output [DM_WIDTH*8-1:0]        wr_data_mask_mc2phy
    ,output [PAYLOAD_WIDTH*8-1:0]   rd_data_mc2ni
    ,output [DPTR_WIDTH-1:0]        rd_data_addr_mc2ni
    ,output                         rd_data_en_mc2ni
    ,output                         rd_data_end_mc2ni
    ,output [DQ_WIDTH*8-1:0]        rd_data_phy2mc

    ,input  wire [RNK_WIDTH-1:0]      rank
    ,input  wire [BNK_WIDTH-1:0]      bank
    ,input  wire [BG_WIDTH-1:0]       group
    ,input  wire [ROW_WIDTH-1:0]      row
    ,input  wire [COL_WIDTH-1:0]      col
    ,input  wire [DPTR_WIDTH-1:0]     dBufAdr
    ,input  wire [CMD_TYPE_WIDTH-1:0] req_type
    ,input  wire                      ap
    ,input  wire                      useAdr
    ,output wire                      mc_accept
  
    ,input [PAYLOAD_WIDTH*8-1:0]    wr_data_ni2mc
    ,input [PAYLOAD_DM_WIDTH*8-1:0] wr_data_mask_ni2mc
    ,input [DPTR_WIDTH-1:0]         wr_data_addr_phy2mc
    ,input [DQ_WIDTH*8-1:0]         rd_data_phy2mc_xif
    ,input [DPTR_WIDTH-1:0]         rd_data_addr_phy2mc
    ,input                          rd_data_en_phy2mc
    ,input                          rd_data_end_phy2mc
    
    ,input  wire                    ref_req
    ,input  wire                    zq_req

    ,input  wire                    per_rd_done

    // IBM SR
    ,input  wire                    sre_req
    ,output wire                    sre_ack
    ,input  wire                    ui_busy
    ,output wire                    mc_block_req
    ,input  wire                    stop_gate_tracking_ack
    ,output wire                    stop_gate_tracking_req
    ,output wire                    cmd_complete
    ,input  wire                    srx_cke0_release
    ,input  wire                    srx_req

    ,input wire                     init_data_rd
    ,input wire                     init_data_wr
    ,input wire  [DPTR_WIDTH-1:0]   done_rd_dptr
    ,input wire  [DPTR_WIDTH-1:0]   done_wr_dptr
    );

    genvar bnk_g;

    wire                 preIss;
    wire                 refIss;
    wire                 zqIss;
    wire                 zqIssAll;
    wire [RKBITS-1:0]    refRank;
    wire [LR_WIDTH-1:0]  refLRank;
    wire                 refReq;
    reg                  refReq_r;
    wire 	             prevCmdAP;
    wire [3:0]          refOK;
    reg  [3:0]          refOK_r;
    wire                winRead;
    wire                winWrite;
    wire                tranSentC;

    // Periodic Read Module Signals
    wire [31:0] periodic_config             = ( PER_RD_INTVL == 0 ) ? 32'b0 : { 30'b0, calDone, calDone };
    wire [31:0] periodic_interval_config    = PER_RD_INTVL;
    wire                 per_block_ref;
    wire                 per_rd_req;
    wire                 per_cas_block_req;
    wire                 per_rd_accept;

    wire                int_sreIss;
    wire [RANKS-1:0]    int_sreCkeDis;
    wire 	            int_srxIss;

    wire [2:0]          dbg_sre_sm_ps;
    wire [3:0]          dbg_refSt;


    ////////////////////////////////////////////////////////
    ////            Request Scheduler Interface         ////
    ////////////////////////////////////////////////////////

    wire                            init_data_n;  
    wire [(DPTR_WIDTH)-1:0]         done_dptr;
    wire [(QUEUE_SIZE_WIDTH)-1:0]   done_qptr;
    wire                            done_type;
    wire [NUM_BNK_TOT-1:0]          idle_flag;
    wire [ROW_WIDTH-1:0]	        row_bnk [NUM_BNK_TOT-1:0];

    wire [NUM_BNK_TOT-1:0]      pre_bundle_valid;
    wire [CMD_TYPE_WIDTH-1:0]   pre_bundle_cmd [NUM_BNK_TOT-1:0];

    wire [NUM_BNK_TOT-1:0]      act_bundle_valid;
    wire [CMD_TYPE_WIDTH-1:0]   act_bundle_cmd [NUM_BNK_TOT-1:0];

    wire [NUM_BNK_TOT-1:0]      cas_bundle_valid;
    wire [CMD_TYPE_WIDTH-1:0]   cas_bundle_cmd [NUM_BNK_TOT-1:0];

    wire [CH_WIDTH - 1 : 0]         o_channel [NUM_BNK_TOT-1:0];
    wire [RNK_WIDTH - 1 : 0]        o_rank    [NUM_BNK_TOT-1:0];
    wire [BG_WIDTH - 1 : 0]         o_bgroup  [NUM_BNK_TOT-1:0];
    wire [BNK_WIDTH - 1 : 0]        o_bank    [NUM_BNK_TOT-1:0];
    wire [ROW_WIDTH - 1 : 0]        o_row     [NUM_BNK_TOT-1:0];
    wire [COL_WIDTH - 1 : 0]        o_column  [NUM_BNK_TOT-1:0];
    wire [(DPTR_WIDTH+1) - 1 : 0]   o_ptr     [NUM_BNK_TOT-1:0];

    wire [NUM_BNK_TOT-1:0]          open_request_allowed;
    wire [NUM_BNK_TOT-1:0]          close_request_allowed;

    wire [CMD_TYPE_WIDTH-1:0]       sel_cmd0;
    wire [CMD_TYPE_WIDTH-1:0]       sel_cmd1;
    wire [CMD_TYPE_WIDTH-1:0]       sel_cmd2;
    wire [CMD_TYPE_WIDTH-1:0]       sel_cmd3;
    reg  [CMD_TYPE_WIDTH-1:0]       sel_cmd0_r;
    reg  [CMD_TYPE_WIDTH-1:0]       sel_cmd1_r;
    reg  [CMD_TYPE_WIDTH-1:0]       sel_cmd2_r;
    reg  [CMD_TYPE_WIDTH-1:0]       sel_cmd3_r;

    wire [CH_WIDTH-1:0]             sel_ch0;
    wire [CH_WIDTH-1:0]             sel_ch1;
    wire [CH_WIDTH-1:0]             sel_ch2;
    wire [CH_WIDTH-1:0]             sel_ch3;
    reg  [CH_WIDTH-1:0]             sel_ch0_r;
    reg  [CH_WIDTH-1:0]             sel_ch1_r;
    reg  [CH_WIDTH-1:0]             sel_ch2_r;
    reg  [CH_WIDTH-1:0]             sel_ch3_r;

    wire [RNK_WIDTH-1:0]            sel_rnk0;
    wire [RNK_WIDTH-1:0]            sel_rnk1;
    wire [RNK_WIDTH-1:0]            sel_rnk2;
    wire [RNK_WIDTH-1:0]            sel_rnk3;
    reg  [RNK_WIDTH-1:0]            sel_rnk0_r;
    reg  [RNK_WIDTH-1:0]            sel_rnk1_r;
    reg  [RNK_WIDTH-1:0]            sel_rnk2_r;
    reg  [RNK_WIDTH-1:0]            sel_rnk3_r;

    wire [BG_WIDTH-1:0]             sel_bg0;
    wire [BG_WIDTH-1:0]             sel_bg1;
    wire [BG_WIDTH-1:0]             sel_bg2;
    wire [BG_WIDTH-1:0]             sel_bg3;
    reg  [BG_WIDTH-1:0]             sel_bg0_r;
    reg  [BG_WIDTH-1:0]             sel_bg1_r;
    reg  [BG_WIDTH-1:0]             sel_bg2_r;
    reg  [BG_WIDTH-1:0]             sel_bg3_r;

    wire [BNK_WIDTH-1:0]            sel_bnk0;
    wire [BNK_WIDTH-1:0]            sel_bnk1;
    wire [BNK_WIDTH-1:0]            sel_bnk2;
    wire [BNK_WIDTH-1:0]            sel_bnk3;
    reg  [BNK_WIDTH-1:0]            sel_bnk0_r;
    reg  [BNK_WIDTH-1:0]            sel_bnk1_r;
    reg  [BNK_WIDTH-1:0]            sel_bnk2_r;
    reg  [BNK_WIDTH-1:0]            sel_bnk3_r;

    wire [ROW_WIDTH-1:0]            sel_row0;
    wire [ROW_WIDTH-1:0]            sel_row1;
    wire [ROW_WIDTH-1:0]            sel_row2;
    wire [ROW_WIDTH-1:0]            sel_row3;
    reg  [ROW_WIDTH-1:0]            sel_row0_r;
    reg  [ROW_WIDTH-1:0]            sel_row1_r;
    reg  [ROW_WIDTH-1:0]            sel_row2_r;
    reg  [ROW_WIDTH-1:0]            sel_row3_r;

    wire [COL_WIDTH-1:0]            sel_col0;
    wire [COL_WIDTH-1:0]            sel_col1;
    wire [COL_WIDTH-1:0]            sel_col2;
    wire [COL_WIDTH-1:0]            sel_col3;
    reg  [COL_WIDTH-1:0]            sel_col0_r;
    reg  [COL_WIDTH-1:0]            sel_col1_r;
    reg  [COL_WIDTH-1:0]            sel_col2_r;
    reg  [COL_WIDTH-1:0]            sel_col3_r;

    wire [DPTR_WIDTH-1:0]           sel_dptr0;
    wire [DPTR_WIDTH-1:0]           sel_dptr2;

    wire                            sel_inj0;
    wire                            sel_inj2;

    wire [3 : 0] [RNK_WIDTH - 1 : 0]        sel_rank;
    wire [3 : 0] [BG_WIDTH - 1 : 0]         sel_bgroup;
    wire [3 : 0] [BNK_WIDTH - 1 : 0]        sel_bank;
    wire [3 : 0] [ROW_WIDTH - 1 : 0]        sel_row;
    wire [3 : 0] [COL_WIDTH - 1 : 0]        sel_col;
    wire [3 : 0] [(DPTR_WIDTH+1) - 1 : 0]   sel_dptr;
    wire [3 : 0] [CMD_TYPE_WIDTH - 1 : 0]   sel_cmd;


    wire    [NUM_BNK_TOT-1:0]                       dequeue;
    wire    [NUM_BNK_TOT-1:0] [CH_WIDTH-1:0]        q_ch   ;
    wire    [NUM_BNK_TOT-1:0] [RNK_WIDTH-1:0]       q_rank ;
    wire    [NUM_BNK_TOT-1:0] [BG_WIDTH-1:0]        q_bg   ;
    wire    [NUM_BNK_TOT-1:0] [BNK_WIDTH-1:0]       q_bank ;
    wire    [NUM_BNK_TOT-1:0] [ROW_WIDTH-1:0]       q_row  ;
    wire    [NUM_BNK_TOT-1:0] [COL_WIDTH-1:0]       q_col  ;
    wire    [NUM_BNK_TOT-1:0] [(DPTR_WIDTH+1)-1:0]  q_dptr ;
    wire    [NUM_BNK_TOT-1:0] [CMD_TYPE_WIDTH-1:0]  q_cmd  ;
    wire    [NUM_BNK_TOT-1:0]                       q_valid;         
    reg     [4-1:0]                                 q_pattern [NUM_BNK_TOT-1:0];

    (* keep = "TRUE" *) reg rst_nr1;

    always @(posedge clk)
        rst_nr1 <= #(TCQ) rst_n;


    ////////////////////////////////////////////////////////
    //                  Request Scheduler                 //
    ////////////////////////////////////////////////////////

    request_scheduler_wrapper#(

        .CH_WIDTH(CH_WIDTH),
        .RNK_WIDTH(RNK_WIDTH),
        .BG_WIDTH(BG_WIDTH),
        .BNK_WIDTH(BNK_WIDTH),
        .COL_WIDTH(COL_WIDTH),
        .ROW_WIDTH(ROW_WIDTH),

        .NUM_CH(NUM_CH),
        .NUM_RNK(NUM_RNK),
        .NUM_BG(NUM_BG),
        .NUM_BNK(NUM_BNK),
        .NUM_BNK_TOT(NUM_BNK_TOT),

        .REQ_WIDTH(REQ_WIDTH),
        .CMD_TYPE_WIDTH(CMD_TYPE_WIDTH),
        .DPTR_WIDTH(DPTR_WIDTH),

        .QUEUE_SIZE(QUEUE_SIZE),
        .QUEUE_SIZE_WIDTH(QUEUE_SIZE_WIDTH),
        .GFIFO_SIZE(GFIFO_SIZE)

        ) request_scheduler_wrapper_inst (

        .rst_n(rst_nr1),
        .clk(clk),

        .group              (group),
        .rank               (rank),
        .bank               (bank),
        .col                (col),
        .row                (row),
        .req_type           (req_type),
        .use_addr           (useAdr),
        .ap                 (ap),
        .dptr_ni2rq         (dBufAdr),
        .accept             (mc_accept),

        // .per_rd_req             (per_rd_req),
        .per_rd_req             (1'b0),
        .block_from_mc_refresh  (refReq),
        .per_rd_accept          (per_rd_accept),

        // page table interface
        .idle_flag              (~idle_flag),
        .open_row               (row_bnk),

        // CAL TOP
        .init_data_rd           (init_data_rd),
        .init_data_wr           (init_data_wr),
        .done_rd_dptr           (done_rd_dptr),
        .done_wr_dptr           (done_wr_dptr),

        // command queue interface
        .o_channel                  (o_channel),
        .o_rank                     (o_rank),  
        .o_group                    (o_bgroup), 
        .o_bank                     (o_bank),  
        .o_row                      (o_row),  
        .o_column                   (o_column), 
        .o_ptr                      (o_ptr),
        .pre_bundle_valid           (pre_bundle_valid),
        .pre_bundle_cmd             (pre_bundle_cmd), 
        .act_bundle_valid           (act_bundle_valid),
        .act_bundle_cmd             (act_bundle_cmd),
        .cas_bundle_valid           (cas_bundle_valid),
        .cas_bundle_cmd             (cas_bundle_cmd),
        .open_request_allowed       (open_request_allowed),
        .close_request_allowed      (close_request_allowed)
    );


    ////////////////////////////////////////////////////////
    ////                Command Queue                   ////
    ////////////////////////////////////////////////////////

    command_queue_wrapper#(

        .CMD_TYPE_WIDTH         (CMD_TYPE_WIDTH),
        .CH_WIDTH               (CH_WIDTH),
        .RNK_WIDTH              (RNK_WIDTH),
        .BG_WIDTH               (BG_WIDTH),
        .BNK_WIDTH              (BNK_WIDTH),
        .ROW_WIDTH              (ROW_WIDTH),
        .COL_WIDTH              (COL_WIDTH),
        .DATA_PTR_WIDTH         (DPTR_WIDTH+1),
        .NUM_BNK_TOT            (NUM_BNK_TOT)

        ) command_queue_wrapper_inst (

        .clk(clk),
        .rstn(rst_nr1),

        // request scheduler interface
        .i_channel      (o_channel),
        .i_rank         (o_rank),
        .i_bgroup       (o_bgroup),
        .i_bank         (o_bank),
        .i_row          (o_row),
        .i_column       (o_column),
        .i_data_ptr     (o_ptr),
        .i_pre_valid    (pre_bundle_valid),
        .i_pre_cmd      (pre_bundle_cmd),
        .i_act_valid    (act_bundle_valid),
        .i_act_cmd      (act_bundle_cmd),
        .i_cas_valid    (cas_bundle_valid),
        .i_cas_cmd      (cas_bundle_cmd),
        .o_open_request_allowed     (open_request_allowed),
        .o_close_request_allowed    (close_request_allowed),

        // command scheduler interface
        .i_dequeue          (dequeue),
        .o_valid            (q_valid),
        .o_channel          (q_ch),
        .o_rank             (q_rank),
        .o_bgroup           (q_bg),
        .o_bank             (q_bank),
        .o_row              (q_row),
        .o_column           (q_col),
        .o_data_ptr         (q_dptr),
        .o_cmd              (q_cmd)  
    );


    ////////////////////////////////////////////////////////
    ////                    Page Table                  ////
    ////////////////////////////////////////////////////////

    page_table#(

        .NUM_RNK(NUM_RNK),
        .NUM_BG(NUM_BG),
        .NUM_BNK(NUM_BNK),
        .RNK_WIDTH(RNK_WIDTH),
        .BG_WIDTH(BG_WIDTH),
        .BNK_WIDTH(BNK_WIDTH),
        .ROW_WIDTH(ROW_WIDTH),
        .COL_WIDTH(COL_WIDTH),
        .CMD_TYPE_WIDTH(CMD_TYPE_WIDTH)

        ) page_table_inst (

        .rst_n(rst_nr1),
        .clk(clk),

        .sel_cmd0(sel_cmd0),
        .sel_cmd1(sel_cmd1),
        .sel_cmd2(sel_cmd2),
        .sel_cmd3(sel_cmd3),

        .sel_rnk0(sel_rnk0),
        .sel_rnk1(sel_rnk1),
        .sel_rnk2(sel_rnk2),
        .sel_rnk3(sel_rnk3),

        .sel_bg0(sel_bg0),
        .sel_bg1(sel_bg1),
        .sel_bg2(sel_bg2),
        .sel_bg3(sel_bg3),

        .sel_bnk0(sel_bnk0),
        .sel_bnk1(sel_bnk1),
        .sel_bnk2(sel_bnk2),
        .sel_bnk3(sel_bnk3),

        .sel_row0(sel_row0),
        .sel_row1(sel_row1),
        .sel_row2(sel_row2),
        .sel_row3(sel_row3),

        .ref_rnk_flag(refReq),
        .ref_rnk_rnk(2'b0),

        .idle_flag(idle_flag),
        .row_bnk(row_bnk)
    );


    ////////////////////////////////////////////////////////
    ////                 Command Scheduler              ////
    ////////////////////////////////////////////////////////

    command_scheduler#(	

        .NUM_CH         (NUM_CH),
        .NUM_RNK        (NUM_RNK),
        .NUM_BG         (NUM_BG),
        .NUM_BNK        (NUM_BNK),
        .CH_SEL_WIDTH   (CH_WIDTH),
        .RNK_SEL_WIDTH  (RNK_WIDTH),
        .BG_SEL_WIDTH   (BG_WIDTH),
        .BNK_SEL_WIDTH  (BNK_WIDTH),
        .ROW_SEL_WIDTH  (ROW_WIDTH),
        .COL_SEL_WIDTH  (COL_WIDTH),
        .CMD_TYPE_WIDTH (CMD_TYPE_WIDTH),
        .DATA_PTR_WIDTH (DPTR_WIDTH+1)

        ) command_scheduler_inst (

        .i_clk(clk),
        .i_rstn(rst_nr1),

        .i_block_cas(per_cas_block_req),
        .i_channel(q_ch),
        .i_rank(q_rank),
        .i_bgroup(q_bg),
        .i_bank(q_bank),
        .i_row(q_row),
        .i_column(q_col),
        .i_data_ptr(q_dptr),
        .i_cmd(q_cmd),
        .i_valid(q_valid),

        .o_channel      (),
        .o_rank         (sel_rank),
        .o_bgroup       (sel_bgroup),
        .o_bank         (sel_bank),
        .o_row          (sel_row),
        .o_column       (sel_col),
        .o_data_ptr     (sel_dptr),
        .o_cmd          (sel_cmd),
        .o_dequeue      (dequeue)
    );

    assign sel_cmd0     = sel_cmd[0];
    assign sel_cmd1     = sel_cmd[1];
    assign sel_cmd2     = sel_cmd[2];
    assign sel_cmd3     = sel_cmd[3];
    assign sel_rnk0     = sel_rank[0];
    assign sel_rnk1     = sel_rank[1];
    assign sel_rnk2     = sel_rank[2];
    assign sel_rnk3     = sel_rank[3];
    assign sel_bg0      = sel_bgroup[0];
    assign sel_bg1      = sel_bgroup[1];
    assign sel_bg2      = sel_bgroup[2];
    assign sel_bg3      = sel_bgroup[3];
    assign sel_bnk0     = sel_bank[0];
    assign sel_bnk1     = sel_bank[1];
    assign sel_bnk2     = sel_bank[2];
    assign sel_bnk3     = sel_bank[3];
    assign sel_row0     = sel_row[0];
    assign sel_row1     = sel_row[1];
    assign sel_row2     = sel_row[2];
    assign sel_row3     = sel_row[3];
    assign sel_col0     = sel_col[0];
    assign sel_col1     = sel_col[1];
    assign sel_col2     = sel_col[2];
    assign sel_col3     = sel_col[3];
    assign sel_dptr0    = sel_dptr[0][DPTR_WIDTH:1];
    assign sel_dptr2    = sel_dptr[2][DPTR_WIDTH:1];
    assign sel_inj0     = sel_dptr[0][0];
    assign sel_inj2     = sel_dptr[2][0];


    ////////////////////////////////////////////////////////
    //                    MC Control                      //
    ////////////////////////////////////////////////////////

    ddr4_v2_2_16_mc_ctl #(

         .RKBITS(RKBITS)  
        ,.ABITS(ABITS)  
        ,.BABITS(BNK_WIDTH)  
        ,.BGBITS(BG_WIDTH)  
        ,.LR_WIDTH(1)  
        ,.CKEBITS(CKE_WIDTH)  
        ,.COLBITS(COL_WIDTH)  
        ,.CSBITS(CS_WIDTH)  
        ,.ODTBITS(ODTBITS)  
        // ,.MR6 (MR6)       
        ,.NOP_ADD_LOW (1'b0)  
        ,.tCK (tCK)          

        ,.ODTWR (ODTWR)
        ,.ODTWRDEL (ODTWRDEL)
        ,.ODTRD (ODTRD) 
        ,.ODTRDDEL (ODTRDDEL)
        ,.ODTWRDUR (ODTWRDUR)
        ,.ODTWRODEL (ODTWRODEL)
        ,.ODTWRODUR (ODTWRODUR)
        ,.ODTRDDUR (ODTRDDUR)
        ,.ODTRDODEL (ODTRDODEL)
        ,.ODTRDODUR (ODTRDODUR)

        ,.CMD_WIDTH(CMD_TYPE_WIDTH)
        ,.CH_WIDTH(CH_WIDTH)
        ,.RNK_WIDTH(RNK_WIDTH)
        ,.BG_WIDTH(BG_WIDTH)
        ,.BNK_WIDTH(BNK_WIDTH)
        ,.ROW_WIDTH(ROW_WIDTH)
        ,.COL_WIDTH(COL_WIDTH)  

        ) u_ddr_mc_ctl (

         .clk(clk)
        ,.rst(~rst_nr1)

        ,.mc_ACT_n      (mc_ACT_n)
        ,.mc_CAS_n      (mc_CAS_n)
        ,.mc_RAS_n      (mc_RAS_n)
        ,.mc_WE_n       (mc_WE_n)
        ,.mc_ADR        (mc_ADR)
        ,.mc_BA         (mc_BA)
        ,.mc_BG         (mc_BG)
        ,.mc_C          (mc_C)
        ,.mc_CKE        (mc_CKE)
        ,.mc_CS_n       (mc_CS_n)
        ,.mc_ODT        (mc_ODT)

        ,.casSlot2          (casSlot2)
        ,.tranSentC         (tranSentC)
        ,.prevCmdAP         (prevCmdAP)
        ,.winRead           (winRead)
        ,.winWrite          (winWrite)
        ,.preIss            (preIss)
        ,.refIss            (refIss)
        ,.zqIss             (zqIss)
        ,.zqIssAll          (zqIssAll)
        ,.refRank           (refRank)
        ,.refLRank          (refLRank)
        ,.per_cas_block_req (per_cas_block_req)
        ,.int_sreIss        (int_sreIss)
        ,.int_sreCkeDis     (int_sreCkeDis)
        ,.int_srxIss        (int_srxIss)

        ,.sel_cmd0      (sel_cmd0)
        ,.sel_cmd1      (sel_cmd1)
        ,.sel_cmd2      (sel_cmd2)
        ,.sel_cmd3      (sel_cmd3)

    	,.sel_rnk0      (sel_rnk0)
    	,.sel_rnk1      (sel_rnk1)
    	,.sel_rnk2      (sel_rnk2)
    	,.sel_rnk3      (sel_rnk3)

    	,.sel_ch0       (1'b0)
    	,.sel_ch1       (1'b0)
    	,.sel_ch2       (1'b0)
    	,.sel_ch3       (1'b0)

        ,.sel_lrnk0     (1'b0)
    	,.sel_lrnk1     (1'b0)
    	,.sel_lrnk2     (1'b0)
    	,.sel_lrnk3     (1'b0)

    	,.sel_bg0       (sel_bg0)
    	,.sel_bg1       (sel_bg1)
    	,.sel_bg2       (sel_bg2)
    	,.sel_bg3       (sel_bg3)

    	,.sel_bnk0      (sel_bnk0)
    	,.sel_bnk1      (sel_bnk1)
    	,.sel_bnk2      (sel_bnk2)
    	,.sel_bnk3      (sel_bnk3)

    	,.sel_row0      (sel_row0)
    	,.sel_row1      (sel_row1)
    	,.sel_row2      (sel_row2)
    	,.sel_row3      (sel_row3)

    	,.sel_col0      (sel_col0)
    	,.sel_col1      (sel_col1)
    	,.sel_col2      (sel_col2)
    	,.sel_col3      (sel_col3)
    );


    ////////////////////////////////////////////////////////
    //      Register Slice Command Scheduler Output       //
    ////////////////////////////////////////////////////////

    always @(posedge clk) begin

        sel_cmd0_r <= sel_cmd0;
        sel_cmd1_r <= sel_cmd1;
        sel_cmd2_r <= sel_cmd2;
        sel_cmd3_r <= sel_cmd3;

        sel_ch0_r <= sel_ch0;
        sel_ch1_r <= sel_ch1;
        sel_ch2_r <= sel_ch2;
        sel_ch3_r <= sel_ch3;

        sel_rnk0_r <= sel_rnk0;
        sel_rnk1_r <= sel_rnk1;
        sel_rnk2_r <= sel_rnk2;
        sel_rnk3_r <= sel_rnk3;

        sel_bg0_r <= sel_bg0;
        sel_bg1_r <= sel_bg1;
        sel_bg2_r <= sel_bg2;
        sel_bg3_r <= sel_bg3;

        sel_bnk0_r <= sel_bnk0;
        sel_bnk1_r <= sel_bnk1;
        sel_bnk2_r <= sel_bnk2;
        sel_bnk3_r <= sel_bnk3;

        sel_row0_r <= sel_row0;
        sel_row1_r <= sel_row1;
        sel_row2_r <= sel_row2;
        sel_row3_r <= sel_row3;

        sel_col0_r <= sel_col0;
        sel_col1_r <= sel_col1;
        sel_col2_r <= sel_col2;
        sel_col3_r <= sel_col3;
    end


    ////////////////////////////////////////////////////////
    //                    MC Periodic                     //
    ////////////////////////////////////////////////////////

    wire non_per_rd_cas;
    assign non_per_rd_cas = rdCAS & ~winInjTxn;

    ddr4_v2_2_16_mc_periodic #(
        ) u_ddr_mc_periodic (

        .clk                (clk)
        ,.rst               (~rst_nr1)

        ,.per_rd_req        (per_rd_req)
        ,.per_cas_block_req (per_cas_block_req)
        ,.per_block_ref     (per_block_ref)
        ,.gt_data_ready     (gt_data_ready)

        ,.periodic_config           (periodic_config)
        ,.periodic_interval_config  (periodic_interval_config)

        ,.rdCAS                     (non_per_rd_cas)
        ,.refReq                    (refReq)
        ,.per_rd_done               (per_rd_done)
        ,.per_rd_accept             (per_rd_accept)
    );


    ////////////////////////////////////////////////////////
    //                    MC Refresh                      //
    ////////////////////////////////////////////////////////

    assign refOK = {refReq & (~(|q_valid)), refReq & (~(|q_valid)), refReq & (~(|q_valid)), refReq & (~(|q_valid))};

    always_ff @( posedge clk ) begin
        refOK_r     <= #(TCQ) refOK;
        refReq_r    <= #(TCQ) refReq;
    end

    ddr4_v2_2_16_mc_ref #(

       .S_HEIGHT    (S_HEIGHT)
       ,.LR_WIDTH   (1)
       ,.tREFI      (tREFI)
       ,.tRFC       (tRFC)
       ,.tRP        (tRP)
       ,.tWR        (tWR)
       ,.ZQINTVL    (ZQINTVL)
       ,.PARTIAL_RECONFIG (PARTIAL_RECONFIG)

        ) u_ddr_mc_ref (

        .clk                     (clk)
        ,.rst                    (~rst_nr1)

        // CAL TOP
        ,.mcCKt                  (mcCKt)
        ,.mcCKc                  (mcCKc)
        ,.calDone                (calDone)
        ,.tCWL                   (tCWL)
        ,.stop_gate_tracking_ack (stop_gate_tracking_ack)
        ,.stop_gate_tracking_req (stop_gate_tracking_req)
    
        // NI
        ,.ref_req                (ref_req)
        ,.zq_req                 (zq_req)
        ,.sre_req                (sre_req)
        ,.sre_ack                (sre_ack)
        ,.ui_busy                (ui_busy)
        ,.mc_block_req           (mc_block_req)
        ,.cmd_complete           (cmd_complete)
    
        // MC
        ,.refOK                  (refOK & refOK_r)
        ,.per_block_ref          (per_block_ref)
        ,.txn_fifo_empty         ('0)
        ,.cas_fifo_empty         ('0)
        ,.sreIss                 (int_sreIss)
        ,.sreCkeDis              (int_sreCkeDis)
        ,.srx_cke0_release       (1'b0)
        ,.srx_req                (1'b0)
        ,.int_srxIss             (int_srxIss)
        ,.dbg_sre_sm_ps          (dbg_sre_sm_ps)
        ,.dbg_refSt              (dbg_refSt)
    
        ,.preIss                 (preIss)
        ,.refIss                 (refIss)
        ,.zqIss                  (zqIss)
        ,.zqIssAll               (zqIssAll)
        ,.refRank                (refRank)
        ,.refLRank               (refLRank)  
        ,.refReq                 (refReq)
        ,.ref_ack                (ref_ack)
        ,.zq_ack                 (zq_ack)
        ,.prevCmdAP              (prevCmdAP)
    );


    ////////////////////////////////////////////////////////
    ////                      MC ECC                    ////
    ////////////////////////////////////////////////////////

    ddr4_v2_2_16_mc_ecc #(

        .PAYLOAD_WIDTH       (PAYLOAD_WIDTH)
       ,.PAYLOAD_DM_WIDTH    (PAYLOAD_DM_WIDTH)
       ,.ECC_WIDTH           (ECC_WIDTH)
       ,.ADDR_FIFO_WIDTH     (ADDR_FIFO_WIDTH)
       ,.S_HEIGHT            (S_HEIGHT)
       ,.LR_WIDTH            (LR_WIDTH)
       ,.DQ_WIDTH            (DQ_WIDTH)
       ,.DQS_WIDTH           (DQ_WIDTH/8)
       ,.DM_WIDTH            (DM_WIDTH)
       ,.nCK_PER_CLK         (nCK_PER_CLK)
       ,.DATA_BUF_ADDR_WIDTH (DPTR_WIDTH)
       ,.ECC                 (ECC)
       ,.MEM                 (MEM)
       ,.ABITS               (ABITS)
       ,.COLBITS             (COL_WIDTH)
       ,.RKBITS              (RKBITS)
       ,.TCQ                 (TCQ)

        ) u_ddr_mc_ecc (

        .clk                 (clk)
       ,.rst                 (~rst_nr1)

       ,.winPortEncC         () // winPortEncC
       ,.non_per_rd_cas      () // non_per_rd_cas
       ,.cmdRmw              () // cmdRmw
       ,.cmdRank             () // cmd_rank_cas
       ,.cmdLRank            () // cmd_l_rank_cas
       ,.cmdRow              () // cmd_row_cas
       ,.cmdCol              () // cmdCol
       ,.cmdBank             () // cmd_bank_cas
       ,.cmdGroup            () // cmd_group_cas
       ,.wr_data_ni2mc       (wr_data_ni2mc)
       ,.wr_data_mask_ni2mc  (wr_data_mask_ni2mc)
       ,.wr_data_addr_phy2mc (wr_data_addr_phy2mc)
       ,.raw_not_ecc         () // raw_not_ecc
       ,.correct_en          () // correct_en
       ,.rmw_rd_done         () // rmw_rd_done
       ,.rd_data_phy2mc_xif  (rd_data_phy2mc_xif)
       ,.rd_data_addr_phy2mc (rd_data_addr_phy2mc)
       ,.rd_data_en_phy2mc   (rd_data_en_phy2mc)
       ,.rd_data_end_phy2mc  (rd_data_end_phy2mc)
       ,.wr_data_mc2phy      (wr_data_mc2phy)
       ,.wr_data_mask_mc2phy (wr_data_mask_mc2phy)
       ,.rd_data_mc2ni       (rd_data_mc2ni)
       ,.rd_data_addr_mc2ni  (rd_data_addr_mc2ni)
       ,.rd_data_en_mc2ni    (rd_data_en_mc2ni)
       ,.rd_data_end_mc2ni   (rd_data_end_mc2ni)
       ,.ecc_err_addr        ()
       ,.eccSingle           () // eccSingle
       ,.eccMultiple         () // eccMultiple
       ,.rd_data_phy2mc_cw_order (rd_data_phy2mc)
       ,.fi_xor_we           () // fi_xor_we
       ,.fi_xor_wrdata       () // fi_xor_wrdata
       ,.fi_xor_wrdata_en    () // fi_xor_wrdata_en
    );


    ////////////////////////////////////////////////////////
    ////              Generating Signals                ////
    ////////////////////////////////////////////////////////

    assign casSlot          = casSlot2 ? 2'b10 : 2'b00;
    assign rdCAS            = winRead & tranSentC;
    assign wrCAS            = winWrite & tranSentC;
    assign win_data_ptr     = casSlot2 ? sel_dptr2 : sel_dptr0;
    assign winInjTxn        = casSlot2 ? sel_inj2 : sel_inj0;
    assign win_rank_cas     = 2'b00;

    task automatic cmd2str(input logic [CMD_TYPE_WIDTH-1:0] cmd, output string cmd_str);
        case (cmd)
            `CASRD      : cmd_str = "CASRD";
            `CASRDA     : cmd_str = "CASRDA";
            `CASWR      : cmd_str = "CASWR";
            `CASWRA     : cmd_str = "CASWRA";
            `PRE        : cmd_str = "PRE";
            `ACT        : cmd_str = "ACT";
            default: cmd_str = "NOP";
        endcase
    endtask
endmodule
