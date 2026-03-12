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


module command_generator_b#(

    parameter CH_SEL_WIDTH      = 1,
    parameter RNK_SEL_WIDTH     = 1,
    parameter BG_SEL_WIDTH      = 2,
    parameter BNK_SEL_WIDTH     = 2,
    parameter ROW_SEL_WIDTH     = 18,
    parameter COL_SEL_WIDTH     = 10,
    parameter ADDR_WIDTH        = (RNK_SEL_WIDTH + BG_SEL_WIDTH + BNK_SEL_WIDTH + COL_SEL_WIDTH + ROW_SEL_WIDTH),

    parameter DATA_PTR_WIDTH    = 5,
    parameter CMD_TYPE_WIDTH    = 3,

    parameter PTR_WIDTH         = DATA_PTR_WIDTH + 1,

    parameter CURRENT_BANK_ID   = 0,

    parameter TCQ               = 100

    )(
    
    input wire                      i_clk,
    input wire                      i_rstn,

    input wire [ADDR_WIDTH-1:0]     i_won_addr,
    input wire                      i_won_ap,
    input wire [DATA_PTR_WIDTH-1:0] i_won_dptr,
    input wire [2-1:0]              i_won_req,
    input wire                      i_won_open,
    input wire                      i_won_inject,
    input wire                      i_won_valid,

    output wire                     o_block_frfcfs, 
    input  wire                     i_block_from_mc_refresh,

    // Periodic Read
    input   wire                        i_inject_select,
    input   wire                        i_inject_open,
    input   wire                        i_per_rd_req,
    input   wire [ROW_SEL_WIDTH-1:0]    i_inject_row,
    output  wire                        o_per_rd_accept,

    // Command Queue Interface
    output reg [CH_SEL_WIDTH-1:0]   o_channel,
    output reg [RNK_SEL_WIDTH-1:0]  o_rank,  
    output reg [BG_SEL_WIDTH-1:0]   o_group, 
    output reg [BNK_SEL_WIDTH-1:0]  o_bank,  
    output reg [ROW_SEL_WIDTH-1:0]  o_row,  
    output reg [COL_SEL_WIDTH-1:0]  o_column, 
    output reg [PTR_WIDTH-1:0]      o_ptr,

    output reg                      o_pre_bundle_valid,
    output reg [CMD_TYPE_WIDTH-1:0] o_pre_bundle_cmd, 
    
    output reg                      o_act_bundle_valid,
    output reg [CMD_TYPE_WIDTH-1:0] o_act_bundle_cmd,
    
    output reg                      o_cas_bundle_valid,
    output reg [CMD_TYPE_WIDTH-1:0] o_cas_bundle_cmd,

    input wire                      i_open_request_allowed,
    input wire                      i_close_request_allowed
    );

    localparam ADDR_COL_LSB = 0;
    localparam ADDR_COL_MSB = ADDR_COL_LSB + COL_SEL_WIDTH - 1;

    localparam ADDR_ROW_LSB = ADDR_COL_MSB + 1;
    localparam ADDR_ROW_MSB = ADDR_ROW_LSB + ROW_SEL_WIDTH - 1;
    
    localparam ADDR_BNK_LSB = ADDR_ROW_MSB + 1;
    localparam ADDR_BNK_MSB = ADDR_BNK_LSB + BNK_SEL_WIDTH - 1;

    localparam ADDR_BG_LSB = ADDR_BNK_MSB + 1;
    localparam ADDR_BG_MSB = ADDR_BG_LSB + BG_SEL_WIDTH - 1;

    localparam ADDR_RNK_LSB = ADDR_BG_MSB + 1;
    localparam ADDR_RNK_MSB = ADDR_RNK_LSB + RNK_SEL_WIDTH - 1;

    typedef logic                       ap_t;
    typedef logic [1:0]                 req_type_t;
    typedef logic                       open_t;
    typedef logic [DATA_PTR_WIDTH-1:0]  data_ptr_t;
    typedef logic                       inject_t;

    typedef struct packed {
        logic [RNK_SEL_WIDTH-1:0]                   rank;
        logic [(BG_SEL_WIDTH+BNK_SEL_WIDTH)-1:0]    bank;
        logic [ROW_SEL_WIDTH-1:0]                   row;
        logic [COL_SEL_WIDTH-1:0]                   column;
    } addr_s;

    typedef struct packed {
        data_ptr_t  data_ptr;
        inject_t    inject;
    } ptr_s;

    typedef struct packed {
        addr_s      addr;
        req_type_t  req_type;
        ap_t        ap;
        open_t      open;
        ptr_s       pointer;
    } packet_s;

    wire [CH_SEL_WIDTH-1:0]     o_channel_comb;
    wire [RNK_SEL_WIDTH-1:0]    o_rank_comb;
    wire [BG_SEL_WIDTH-1:0]     o_group_comb;
    wire [BNK_SEL_WIDTH-1:0]    o_bank_comb;
    wire [ROW_SEL_WIDTH-1:0]    o_row_comb;
    wire [COL_SEL_WIDTH-1:0]    o_column_comb;
    wire [PTR_WIDTH-1:0]        o_ptr_comb;

    wire                        pre_bundle_valid_comb;
    wire [CMD_TYPE_WIDTH-1:0]   pre_bundle_cmd_comb;
    wire                        act_bundle_valid_comb;
    wire [CMD_TYPE_WIDTH-1:0]   act_bundle_cmd_comb;
    wire                        cas_bundle_valid_comb;
    wire [CMD_TYPE_WIDTH-1:0]   cas_bundle_cmd_comb;
    
    wire    selected_packet_valid;
    wire    is_won_accepted;

    packet_s    inject_packet;
    packet_s    won_packet;
    packet_s    selected_packet;

    assign inject_packet.addr.rank          = 1'b0;
    assign inject_packet.addr.bank          = CURRENT_BANK_ID;
    assign inject_packet.addr.row           = i_inject_open ? i_inject_row : i_won_addr[ADDR_ROW_MSB:ADDR_ROW_LSB];
    assign inject_packet.addr.column        = 'b0;
    assign inject_packet.req_type           = 2'b01;
    assign inject_packet.ap                 = 1'b0;
    assign inject_packet.open            = i_inject_open;
    assign inject_packet.pointer.data_ptr   = 'b0;
    assign inject_packet.pointer.inject  = 1'b1; 
    
    assign won_packet.addr              = i_won_addr;
    assign won_packet.req_type          = i_won_req;
    assign won_packet.ap                = i_won_ap;
    assign won_packet.open           = i_won_open;
    assign won_packet.pointer.data_ptr  = i_won_dptr;
    assign won_packet.pointer.inject = i_won_inject; 

    assign selected_packet = pick_per_rd ? inject_packet : won_packet;
    assign selected_packet_valid = pick_per_rd ? 1'b1 : i_won_valid;

    assign pre_bundle_cmd_comb = `PRE;
    assign act_bundle_cmd_comb = `ACT;

    assign o_channel_comb   = 1'b0;
    assign o_rank_comb      = selected_packet.addr.rank;
    assign o_group_comb     = selected_packet.addr.bank[BNK_SEL_WIDTH +: BG_SEL_WIDTH];
    assign o_bank_comb      = selected_packet.addr.bank[0 +: BNK_SEL_WIDTH];
    assign o_row_comb       = selected_packet.addr.row;
    assign o_column_comb    = selected_packet.addr.column;
    assign o_ptr_comb       = {selected_packet.pointer.data_ptr, selected_packet.pointer.inject};

    assign is_won_accepted = won_packet.open ? i_open_request_allowed : i_close_request_allowed;
    assign o_block_frfcfs = ~is_won_accepted | pick_per_rd;


    assign cas_bundle_cmd_comb = ({selected_packet.req_type[1:0], selected_packet.ap} == 3'b000) ? `CASWR :
                                 ({selected_packet.req_type[1:0], selected_packet.ap} == 3'b001) ? `CASWRA :
                                 ({selected_packet.req_type[1:0], selected_packet.ap} == 3'b010) ? `CASRD :
                                 ({selected_packet.req_type[1:0], selected_packet.ap} == 3'b011) ? `CASRDA :
                                 `NOP;

    assign pre_bundle_valid_comb = (~selected_packet.open & selected_packet_valid) ? (~i_block_from_mc_refresh & i_close_request_allowed) : 1'b0;
    assign act_bundle_valid_comb = (~selected_packet.open & selected_packet_valid) ? (~i_block_from_mc_refresh & i_close_request_allowed) : 1'b0;
    assign cas_bundle_valid_comb = selected_packet_valid  & ~i_block_from_mc_refresh & is_won_accepted;

    always_ff @(posedge i_clk) begin

        // synchronous active-low reset logic
        if(!i_rstn) begin
            o_channel           <= #TCQ {CH_SEL_WIDTH{1'b0}};
            o_rank              <= #TCQ {RNK_SEL_WIDTH{1'b0}};
            o_group             <= #TCQ {BG_SEL_WIDTH{1'b0}};
            o_bank              <= #TCQ {BNK_SEL_WIDTH{1'b0}};
            o_row               <= #TCQ {ROW_SEL_WIDTH{1'b0}};
            o_column            <= #TCQ {COL_SEL_WIDTH{1'b0}};
            o_ptr               <= #TCQ {PTR_WIDTH{1'b0}};
            o_pre_bundle_valid  <= #TCQ 1'b0;
            o_pre_bundle_cmd    <= #TCQ {CMD_TYPE_WIDTH{1'b0}};
            o_act_bundle_valid  <= #TCQ 1'b0;
            o_act_bundle_cmd    <= #TCQ {CMD_TYPE_WIDTH{1'b0}};
            o_cas_bundle_valid  <= #TCQ 1'b0;
            o_cas_bundle_cmd    <= #TCQ {CMD_TYPE_WIDTH{1'b0}};
        end

        else begin
            o_channel           <= #TCQ o_channel_comb;
            o_rank              <= #TCQ o_rank_comb;
            o_group             <= #TCQ o_group_comb;
            o_bank              <= #TCQ o_bank_comb;
            o_row               <= #TCQ o_row_comb;
            o_column            <= #TCQ o_column_comb;
            o_ptr               <= #TCQ o_ptr_comb;
            o_pre_bundle_valid  <= #TCQ pre_bundle_valid_comb;
            o_pre_bundle_cmd    <= #TCQ pre_bundle_cmd_comb;
            o_act_bundle_valid  <= #TCQ act_bundle_valid_comb;
            o_act_bundle_cmd    <= #TCQ act_bundle_cmd_comb;
            o_cas_bundle_valid  <= #TCQ cas_bundle_valid_comb;
            o_cas_bundle_cmd    <= #TCQ cas_bundle_cmd_comb;
        end
    end
    
    // ---------------------------------------------------------
    // --------------- Periodic Read Issue Logic ---------------
    // ---------------------------------------------------------
    
    // FSM states
    localparam IDLE           = 1'b0;
    localparam READ_INJ_DELAY = 1'b1;
    
    // tracking the current state and the next state of the fsm 
    reg [0:0] periodic_state_reg;
    logic [0:0] periodic_state_next_comb;
    
    // periodic read request from the
    // external source: periodic read module
    logic per_rd_req_external_comb;
    assign per_rd_req_external_comb = i_per_rd_req;
    
    // acceptance of a periodic read request
    reg per_rd_accept_reg;
    logic per_rd_accept_next_comb;
    assign o_per_rd_accept = per_rd_accept_reg;
    
    // internal periodic read request
    reg per_rd_req_internal_reg;
    logic per_rd_req_internal_next_comb;

    // indicate whether to select the periodic read packet or the won packet
    logic pick_per_rd;

    // indicate if the command queue allows the injected read
    wire inject_issue_allowed;
    
    // combinational logic to calculate outputs and the next states
    always @(*) begin
    
        casez (periodic_state_reg)
        
            // state meaning: no outstanding internal/external requests exists
            IDLE: begin
            
                // do not select periodic read packet
                // in the last multiplexer between inject_packet and won_packet 
                pick_per_rd <= 1'b0;
                
                // if a request is received from the external source
                // and is targeting the current command generator bank
                if (per_rd_req_external_comb == 1'b1 && i_inject_select == 1'b1) begin
                    // select periodic read packet
                    // in the last multiplexer between inject_packet and won_packet 
                    pick_per_rd <= 1'b1;
                    // generate an internal request for it
                    per_rd_req_internal_next_comb <= 1'b1;
                    // move to the state READ_INJ_DELAY
                    periodic_state_next_comb <= READ_INJ_DELAY;
                end
                
                // remain in the same state if no external request received
                else begin
                    per_rd_req_internal_next_comb <= 1'b0;
                    periodic_state_next_comb <= periodic_state_reg;
                end
            end
           
            // state meaning: an outstanding request exists
            READ_INJ_DELAY: begin
                
                // select periodic read packet
                // in the last multiplexer between inject_packet and won_packet 
                pick_per_rd <= 1'b1;
                
                // if the request is accepted, move to the IDLE state
                if (per_rd_accept_reg == 1'b1) begin
                    per_rd_req_internal_next_comb <= 1'b0;
                    periodic_state_next_comb <= IDLE;
                end
                
                // stay on the same state until the request is accepted
                else begin
                    per_rd_req_internal_next_comb <= 1'b1;
                    periodic_state_next_comb <= periodic_state_reg;
                end
            end
           
            // default state to avoid latches
            default: begin
                per_rd_req_internal_next_comb <= 1'b0;
                periodic_state_next_comb <= IDLE;
            end
            
        endcase
    end
    
    // assign the next combinational value to registers                           
    always_ff @(posedge i_clk) begin
        // synchronous active-low reset logic
        if(!i_rstn) begin
            periodic_state_reg <= #TCQ IDLE;
            per_rd_req_internal_reg <= #TCQ 1'b0;
            per_rd_accept_reg <= #TCQ 1'b0;
        end
        else begin
            periodic_state_reg <= #TCQ periodic_state_next_comb;
            per_rd_req_internal_reg <= #TCQ per_rd_req_internal_next_comb;
            per_rd_accept_reg <= #TCQ per_rd_accept_next_comb;
        end
    end
  
    // based on whether going to inject an open read or close read,
    // check if the command queue allows a request of that type
    assign inject_issue_allowed = i_inject_open ? i_open_request_allowed : i_close_request_allowed;
    
    // accept a periodic read request if:
    // 1- a request exists (per_rd_req_internal_reg | per_rd_req_internal_next_comb)
    // 2- command queue allows to enqueue (inject_issue_allowed)
    // 3- was not already accepted in the previous cycle (~per_rd_accept_reg)
    assign per_rd_accept_next_comb = (per_rd_req_internal_reg | per_rd_req_internal_next_comb)
                                   & inject_issue_allowed
                                   & ~per_rd_accept_reg;
   
endmodule
