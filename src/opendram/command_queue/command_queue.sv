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


module command_queue#(
    
    parameter CMD_TYPE_WIDTH    = 3,
    
    parameter CH_SEL_WIDTH      = 1,
    parameter RNK_SEL_WIDTH     = 1,
    parameter BG_SEL_WIDTH      = 2,
    parameter BNK_SEL_WIDTH     = 3,
    parameter ROW_SEL_WIDTH     = 3,
    parameter COL_SEL_WIDTH     = 6,
    
    parameter DATA_PTR_WIDTH    = 4
    )(
    
    // module working on the posedge of the clock
    input i_clk,
    // synchronous active-low reset
    input i_rstn,
    
    // address of the commands, shared between all three enqueueing commands
    // NOTE: it is assumed that the PRE command holds the same address as other commands that are enqueuing with it
    input [CH_SEL_WIDTH - 1 : 0] i_channel,
    input [RNK_SEL_WIDTH - 1 : 0] i_rank,
    input [BG_SEL_WIDTH - 1 : 0] i_bgroup,
    input [BNK_SEL_WIDTH - 1 : 0] i_bank,
    input [ROW_SEL_WIDTH - 1 : 0] i_row,
    input [COL_SEL_WIDTH - 1 : 0] i_column,
    
    // data pointer of the commands, shared between all three enqueueing commands
    input [DATA_PTR_WIDTH - 1 : 0] i_data_ptr,
    
    // three command inputs and their valid signal
    // as a command can be of different types (CAS vs. CAS+APRE), the command itself is also passed
    input i_pre_valid,
    input [CMD_TYPE_WIDTH - 1 : 0] i_pre_cmd,
    input i_act_valid,
    input [CMD_TYPE_WIDTH - 1 : 0] i_act_cmd,
    input i_cas_valid,
    input [CMD_TYPE_WIDTH - 1 : 0] i_cas_cmd,
    
    // this signal must be high during the negedge of the clock to dequeue happen
    input i_dequeue,
    
    // indicating if the queue is not empty and the command in front can be dequeued
    output o_valid,
    
    // address of the dequeued command
    output [CH_SEL_WIDTH - 1 : 0] o_channel,
    output [RNK_SEL_WIDTH - 1 : 0] o_rank,
    output [BG_SEL_WIDTH - 1 : 0] o_bgroup,
    output [BNK_SEL_WIDTH - 1 : 0] o_bank,
    output [ROW_SEL_WIDTH - 1 : 0] o_row,
    output [COL_SEL_WIDTH - 1 : 0] o_column,
    
    // data pointer of the dequeued command
    output [DATA_PTR_WIDTH - 1 : 0] o_data_ptr,
    
    // dequeued command
    output [CMD_TYPE_WIDTH - 1 : 0] o_cmd,
    
    // indicating if an open/close request is allowed
    // combinational, not clocked
    output o_open_request_allowed,
    output o_close_request_allowed
    );
    
    //---------------------------------------------------
    //----------------- Local Parameter -----------------
    //---------------------------------------------------
    
    // DO NOT MODIFY THE QUEUE_SIZE
    localparam QUEUE_SIZE = 3;
    
    // width of address field in a command
    localparam CMD_ADDR_WDITH = CH_SEL_WIDTH
                              + RNK_SEL_WIDTH
                              + BG_SEL_WIDTH
                              + BNK_SEL_WIDTH
                              + ROW_SEL_WIDTH
                              + COL_SEL_WIDTH;    
    
    // width of counters for the number of ACT/CAS/PRE
    localparam COUNTER_WIDTH = $clog2(QUEUE_SIZE + 1);
    
    // width of queue read and write pointers
    localparam PTR_WIDTH = $clog2(QUEUE_SIZE + 1);
    
    // width of each element in the queue
    localparam QUEUE_ELEMENT_WIDTH = CMD_TYPE_WIDTH + CMD_ADDR_WDITH + PTR_WIDTH;
    
    // request mode encoded based on the i_xxx_valid inputs
    localparam  REQ_MODE_OPEN    = 3'b001,
                REQ_MODE_FRESH   = 3'b011,
                REQ_MODE_CLOSE   = 3'b111;
    
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
    
    // command queue definition
    // as the size of queue is not a power of two,
    // the wrap-around logic for read and write pointers cannot be used,
    // therefore, queue must have an additional cell
    // (the total number of valid commands in the queue will never exceed QUEUE_SIZE)
    cmd_packet_t cmd_queue_reg[QUEUE_SIZE + 1];
    
    // recording the number of valid commands in the queue based on enqueue/dequeue signals
    reg [COUNTER_WIDTH - 1 : 0] queue_count_reg;
    wire [COUNTER_WIDTH - 1 : 0] queue_count_next_comb;
    
    // write and read pointers of the queue
    // read comments in the cmd_queue_reg definition section for _aligned_comb/_aligned_next_comb logic
    reg [PTR_WIDTH - 1 : 0] w_ptr_reg;
    reg [PTR_WIDTH - 1 : 0] r_ptr_reg;
    
    // to avoid using mod operator while incrementing w_ptr_reg and r_ptr_reg
    // the required additions are always calculated combinationaly with conditional statements
    wire [PTR_WIDTH - 1 : 0] w_ptr_plus1_comb;
    wire [PTR_WIDTH - 1 : 0] w_ptr_plus2_comb;
    wire [PTR_WIDTH - 1 : 0] w_ptr_plus3_comb;
    wire [PTR_WIDTH - 1 : 0] r_ptr_plus1_comb;
    
    // used for enqueue logic
    wire [2:0] req_mode_comb;
    
    // holding input CAS command of an open request
    cmd_packet_t cas_cmd_input_comb;
    
    // signals telling command generator which kind of request is allowed
    wire open_request_allowed_comb;
    wire close_request_allowed_comb;
    
    // queue full/empty flags
    wire queue_full_current_cycle_comb;
    wire queue_empty_current_cycle_comb;
    wire queue_full_next_cycle_comb;
    wire queue_empty_next_cycle_comb;
    
    //---------------------------------------------------
    //------------ Combinational Assignments ------------
    //---------------------------------------------------
    
    // continuously assign front of the queue to the outputs
    assign {o_cmd, {o_channel, o_rank, o_bgroup, o_bank, o_row, o_column}, o_data_ptr} = cmd_queue_reg[r_ptr_reg];
    
    // assign o_open_request_allowed and o_close_request_allowed ports
    assign o_open_request_allowed = queue_empty_next_cycle_comb;     
    assign o_close_request_allowed = queue_empty_next_cycle_comb;
    
    // check for the queue being full or empty in the current cycle
    // assign queue_full_current_cycle_comb = (r_ptr_reg - w_ptr_reg == 1) || (r_ptr_reg == 0 && w_ptr_reg == 5);
    // assign queue_empty_current_cycle_comb = (w_ptr_reg == r_ptr_reg); 
  
    // check for the queue being full or empty in the next cycle   
    // assign queue_full_next_cycle_comb = (queue_count_next_no_dequeue_comb >= 3'd5);
    assign queue_empty_next_cycle_comb = (queue_count_next_comb == 3'd0);
        
    // assign the validity of the front command in the queue to be dequeued
    assign o_valid = (w_ptr_reg != r_ptr_reg);
    
    // assign i_xxx_valid inputs to the req_mode_comb
    assign req_mode_comb = {i_pre_valid, i_act_valid, i_cas_valid};
                          
    // calculate w_ptr and r_ptr required additions  
    assign w_ptr_plus1_comb = (w_ptr_reg == 5) ? 0 : w_ptr_reg + 1;
    assign w_ptr_plus2_comb = (w_ptr_plus1_comb == 5) ? 0 : w_ptr_plus1_comb + 1;
    assign w_ptr_plus3_comb = (w_ptr_plus2_comb == 5) ? 0 : w_ptr_plus2_comb + 1;
    assign r_ptr_plus1_comb = (r_ptr_reg == 5) ? 0 : r_ptr_reg + 1;
     
    //---------------------------------------------------
    //------------------ Queue Counter ------------------
    //---------------------------------------------------
    
    // calculate the number of elements in the queue in the next cycle
    assign queue_count_next_comb = (req_mode_comb == REQ_MODE_OPEN && i_dequeue == 1'b0) ? queue_count_reg + 'd1 :
                                   (req_mode_comb == REQ_MODE_FRESH && i_dequeue == 1'b0) ? queue_count_reg + 'd2 :
                                   (req_mode_comb == REQ_MODE_CLOSE && i_dequeue == 1'b0) ? queue_count_reg + 'd3 :
                                   (req_mode_comb == REQ_MODE_OPEN && i_dequeue == 1'b1) ? queue_count_reg :
                                   (req_mode_comb == REQ_MODE_FRESH && i_dequeue == 1'b1) ? queue_count_reg + 'd1 :
                                   (req_mode_comb == REQ_MODE_CLOSE && i_dequeue == 1'b1) ? queue_count_reg + 'd2 :
                                   (req_mode_comb == 3'b000 && i_dequeue == 1'b1) ? queue_count_reg - 'd1 :
                                   queue_count_reg;
    
    // assign the next combinational value of queue_count to the register                             
    always_ff @(posedge i_clk) begin
        // synchronous active-low reset logic
        if(!i_rstn) begin
            queue_count_reg <= {COUNTER_WIDTH{1'b0}};
        end
        else begin
            queue_count_reg <= queue_count_next_comb;
        end
    end
     
    //---------------------------------------------------
    //-------------- Enqueue/Dequeue Logic --------------
    //---------------------------------------------------
    // insertion is performed based on the req_mode_comb = {i_pre_valid, i_act_valid, i_cas_valid}
    //
    // table 1.
    //                      req_mode_comb
    //                      (PRE, ACT, CAS)  
    // ------------------------------------
    // REQ_MODE_OPEN            3'b001     
    // REQ_MODE_FRESH           3'b011     
    // REQ_MODE_CLOSE           3'b111     
    // 
    always_ff @(posedge i_clk) begin
        
        // synchronous active-low reset logic
        if(!i_rstn) begin
            r_ptr_reg <= {PTR_WIDTH{1'b0}};
            w_ptr_reg <= {PTR_WIDTH{1'b0}};
            cmd_queue_reg <= '{{QUEUE_ELEMENT_WIDTH{1'b0}}, {QUEUE_ELEMENT_WIDTH{1'b0}}, {QUEUE_ELEMENT_WIDTH{1'b0}}, {QUEUE_ELEMENT_WIDTH{1'b0}}};
        end
    
        else begin
            case(req_mode_comb)
                
                REQ_MODE_OPEN: begin
                    
                    // enqueue CAS command
                    cmd_queue_reg[w_ptr_reg] <= {i_cas_cmd, {i_channel, i_rank, i_bgroup, i_bank, i_row, i_column}, i_data_ptr};
                    
                    // increment write pointer
                    w_ptr_reg <= w_ptr_plus1_comb;
                    
                    // if dequeuing at the same time
                    if(i_dequeue) begin
                        r_ptr_reg <= r_ptr_plus1_comb;
                    end
                end
                
                REQ_MODE_FRESH: begin
                
                    // enqueue ACT command
                    cmd_queue_reg[w_ptr_reg] <= {i_act_cmd, {i_channel, i_rank, i_bgroup, i_bank, i_row, i_column}, i_data_ptr};
                    
                    // enqueue CAS command
                    cmd_queue_reg[w_ptr_plus1_comb] <= {i_cas_cmd, {i_channel, i_rank, i_bgroup, i_bank, i_row, i_column}, i_data_ptr};
                    
                    // increment write pointer
                    w_ptr_reg <= w_ptr_plus2_comb;
                    
                    // if dequeuing at the same time
                    if(i_dequeue) begin
                        r_ptr_reg <= r_ptr_plus1_comb;
                    end
                end
                
                REQ_MODE_CLOSE: begin
                
                    // enqueue PRE command
                    cmd_queue_reg[w_ptr_reg] <= {i_pre_cmd, {i_channel, i_rank, i_bgroup, i_bank, i_row, i_column}, i_data_ptr};
                    
                    // enqueue ACT command
                    cmd_queue_reg[w_ptr_plus1_comb] <= {i_act_cmd, {i_channel, i_rank, i_bgroup, i_bank, i_row, i_column}, i_data_ptr};
                    
                    // enqueue CAS command
                    cmd_queue_reg[w_ptr_plus2_comb] <= {i_cas_cmd, {i_channel, i_rank, i_bgroup, i_bank, i_row, i_column}, i_data_ptr};
                    
                    // increment write pointer
                    w_ptr_reg <= w_ptr_plus3_comb;
                    
                    // if dequeuing at the same time
                    if(i_dequeue) begin
                        r_ptr_reg <= r_ptr_plus1_comb;
                    end
                end
                
                // the code reaches the default case when there is no enqueue of any type at that cycle
                default: begin
                    if(i_dequeue) begin
                        r_ptr_reg <= r_ptr_plus1_comb;
                    end
                end
            endcase
        end
    end
                                                    
endmodule
