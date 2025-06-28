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


module frfcfs_b#(

    parameter       CH_WIDTH    = 1,
    parameter       RNK_WIDTH   = 1,
    parameter       BG_WIDTH    = 2,
    parameter       BNK_WIDTH   = 2,
    parameter       COL_WIDTH   = 10,
    parameter       ROW_WIDTH   = 18,
    parameter       ADDR_WIDTH  = (RNK_WIDTH + BG_WIDTH + BNK_WIDTH + COL_WIDTH + ROW_WIDTH),

    parameter       GFIFO_SIZE  = 8,
    parameter       DPTR_WIDTH  = 5,
    parameter       REQ_WIDTH   = 2,
    
    parameter       TCQ         = 100

    )(

    input wire                          rst_n,
    input wire                          clk,
    
    input wire [CH_WIDTH-1:0]           channel,
    input wire [RNK_WIDTH-1:0]          rank,
    input wire [BG_WIDTH-1:0]           bg,
    input wire [BNK_WIDTH-1:0]          bank,
    input wire [COL_WIDTH-1:0]          col,
    input wire [ROW_WIDTH-1:0]          row,
    input wire [DPTR_WIDTH-1:0]         dptr,
    input wire                          ap, 
    input wire [REQ_WIDTH-1:0]          req_type, // RD:01, WR:00

    input wire                          idle_flag,
    input wire [ROW_WIDTH-1:0]          open_row,
    input wire                          use_addr,

    input wire                          init_data_rd,
    input wire                          init_data_wr,
    input wire  [DPTR_WIDTH-1:0]        done_rd_dptr,
    input wire  [DPTR_WIDTH-1:0]        done_wr_dptr,

    output  wire [DPTR_WIDTH-1:0]       won_dptr,
    output  wire                        won_open,
    output  wire                        won,
    output  wire [ADDR_WIDTH-1:0]       won_addr,
    output  wire                        won_ap,
    output  wire [2-1:0]                won_cmd,
    output  wire                        won_inject,
    input   wire                        block_from_command_generator, // this signal is coming from command generator or downstream
    input   wire                        block_from_mc_refresh,
    
    output wire                         is_full

    );
    
    localparam PACKET_WDITH = (ADDR_WIDTH + 1 /*(1 bit for ap)*/  + 1 /*(1 bit for inject)*/ + 2 /*(2 bits for cmd)*/);

    typedef logic [CH_WIDTH-1:0]            channel_t;
    typedef logic [RNK_WIDTH-1:0]           rank_t;
    typedef logic [BG_WIDTH-1:0]            group_t;
    typedef logic [BNK_WIDTH-1:0]           bank_t;
    typedef logic [ROW_WIDTH-1:0]           row_t;
    typedef logic [COL_WIDTH-1:0]           col_t;
    typedef logic [(DPTR_WIDTH-1):0]        dptr_t;
    typedef logic [(2-1):0]                 cmd_t;
    typedef logic                           ap_t;
    typedef logic                           inject_t;
    typedef logic                           type_t;

    typedef struct packed {
        channel_t   channel;
        rank_t      rank;
        group_t     group;
        bank_t      bank;
        row_t       row;
        col_t       col;
    } addr_t;

    typedef struct packed {
        bit     valid;
        type_t  req_type;
        dptr_t  dptr;
    } dptr_fifo_t;
    
    typedef struct packed {
        addr_t          addr;
        ap_t            ap;
        inject_t        inject;
        cmd_t           cmd;
    } request_t;

    request_t arrived_request;
    request_t won_request;

    // global fifo 
    request_t gfifo     [GFIFO_SIZE-1:0];
    request_t gfifo_r   [GFIFO_SIZE-1:0];

    // global fifo next state
    request_t gfifo_ns  [GFIFO_SIZE-1:0];

    dptr_fifo_t  dptr_fifo     [GFIFO_SIZE-1:0];
    dptr_fifo_t  dptr_fifo_nxt [GFIFO_SIZE-1:0];

    // wires to extract a request from the fifo
    wire [PACKET_WDITH-1:0] request_extract_1 [GFIFO_SIZE-1:0];
    wire [GFIFO_SIZE-1:0] request_extract_2 [PACKET_WDITH-1:0];

    wire [DPTR_WIDTH-1:0] dptr_extract_1 [GFIFO_SIZE-1:0];
    wire [GFIFO_SIZE-1:0] dptr_extract_2 [DPTR_WIDTH-1:0];

    wire [GFIFO_SIZE-1:0] hit;
    wire [GFIFO_SIZE-1:0] sel_idx;
    wire [GFIFO_SIZE-1:0] hit_and_schedulable;
    reg  [GFIFO_SIZE-1:0] done_request_idx;
    wire [GFIFO_SIZE-1:0] done_request_idx_rd;
    wire [GFIFO_SIZE-1:0] done_request_idx_wr;
    reg  [GFIFO_SIZE-1:0] done_request_idx_wr_d1;
    wire [GFIFO_SIZE-1:0] done_request_idx_wr_d1_comb;
    wire [GFIFO_SIZE-1:0] shift_enable;
    wire [GFIFO_SIZE-1:0] final_flag;

    // schedulable bit, 1: is schedulable
    wire    [GFIFO_SIZE-1:0] last_enqueued_index;
    reg     [GFIFO_SIZE-1:0] schedulable;
    reg     [GFIFO_SIZE-1:0] schedulable_comb;

    reg [(GFIFO_SIZE+1)-1:0] first_empty_index; // one extra bit in MSB, meaning fullness if it's one
    reg [(GFIFO_SIZE+1)-1:0] first_empty_index_comb;
    
    
    reg [(GFIFO_SIZE+1)-1:0] last_occupied_index; // one extra bit in LSB, meaning emptyness if it's one
    reg [(GFIFO_SIZE+1)-1:0] last_occupied_index_comb;

    wire [GFIFO_SIZE-1:0] wr_en;
    reg  [GFIFO_SIZE-1:0] dptr_wr_en;

    reg req_type_d1;
    wire is_there_any_ready;

    wire    accept;
    wire    stall = block_from_command_generator | block_from_mc_refresh;
    reg     init_data_d1;

    addr_t  new_req_addr;
    wire    done_valid;
    reg     is_full_r;

    genvar gfifo_idx, packet_idx, i, j;
    
    generate
        for(i = 0; i<GFIFO_SIZE; i++) begin
            if(i < GFIFO_SIZE-1)
                assign done_request_idx_wr_d1_comb[i] = (shift_enable[i]) ?  done_request_idx_wr[i+1] : done_request_idx_wr[i];
            else
                assign done_request_idx_wr_d1_comb[GFIFO_SIZE-1] = (shift_enable[GFIFO_SIZE-1]) ?  1'b0 : done_request_idx_wr[i];            
        end
    endgenerate
   
    always @(posedge clk) begin
        done_request_idx_wr_d1  <= #TCQ done_request_idx_wr_d1_comb;
        req_type_d1             <= #TCQ req_type[0];
        init_data_d1            <= #TCQ init_data_rd & init_data_wr;
    end

    // updating data pointer fifo
    assign accept = ~is_full_r;
    assign dptr_wr_en = (done_valid) ?  last_occupied_index[GFIFO_SIZE:1] : first_empty_index[GFIFO_SIZE-1:0];
    generate
        for (i=0; i<GFIFO_SIZE; i++) begin
            if(i<GFIFO_SIZE-1) begin
                assign dptr_fifo_nxt[i] = (dptr_wr_en[i] & use_addr & accept ) ? {1'b1, req_type_d1, dptr} : ((shift_enable[i]) ? dptr_fifo[i+1] : dptr_fifo[i]);
            end else begin
                assign dptr_fifo_nxt[GFIFO_SIZE-1] = (dptr_wr_en[GFIFO_SIZE-1] & use_addr & accept) ? {1'b1, req_type_d1, dptr} : {1'b0, 1'b0, dptr_fifo[GFIFO_SIZE-1][DPTR_WIDTH-1:0]};
            end
            always@(posedge clk) begin
                if(~rst_n)
                    dptr_fifo[i] <= #TCQ 1'b0;
                else    
                    dptr_fifo[i] <= #TCQ dptr_fifo_nxt[i];
            end
        end  
    endgenerate

    assign new_req_addr.channel         = channel;    
    assign new_req_addr.rank            = rank;
    assign new_req_addr.group           = bg;
    assign new_req_addr.bank            = bank;
    assign new_req_addr.row             = row;
    assign new_req_addr.col             = col;
    assign arrived_request.addr         = new_req_addr;
    assign arrived_request.ap           = ap;
    assign arrived_request.inject       = 1'b0;
    assign arrived_request.cmd          = req_type[1:0];

    // comparator module
    // 1: is hit
    for (i=0; i<GFIFO_SIZE; i++) begin : HIT_IDX
        assign hit[i] = gfifo[i].addr.row == open_row;
    end

    // determinig hit request one-hot index
    assign hit_and_schedulable = hit & schedulable;
    assign is_there_any_ready = (|hit_and_schedulable) & (~idle_flag);
    assign final_flag = (is_there_any_ready) ? hit_and_schedulable : schedulable;
    for (i=0; i<GFIFO_SIZE; i++) begin : SEL_IDX
        if(i==0) begin
            assign sel_idx[0] = final_flag[0];    
        end
        else begin
            assign sel_idx[i] = ~(|{(~final_flag[i]), final_flag[i-1:0]});
        end
    end

    // updating schedulable bit, 1: is schedulable
    assign last_enqueued_index = last_occupied_index_comb[GFIFO_SIZE:1]; 
    generate
        for (i=0; i<GFIFO_SIZE; i++) begin : SCH_IDX
            
            if(i<GFIFO_SIZE-1) begin
                always @(*) begin
                    if(last_enqueued_index[i] & use_addr) begin
                        schedulable_comb[i] = 1'b1;
                    end else begin
                        case({shift_enable[i], stall})
                            2'b00: schedulable_comb[i] = schedulable[i] ^ sel_idx[i];
                            2'b01: schedulable_comb[i] = schedulable[i];
                            2'b10: schedulable_comb[i] = schedulable[i+1] ^ sel_idx[i+1];
                            2'b11: schedulable_comb[i] = schedulable[i+1];
                        endcase 
                    end
                end
            end else begin
                always @(*) begin
                    if(last_enqueued_index[GFIFO_SIZE-1] & use_addr) begin
                        schedulable_comb[GFIFO_SIZE-1] = 1'b1;
                    end else begin
                        case({shift_enable[GFIFO_SIZE-1], stall})
                            2'b00: schedulable_comb[GFIFO_SIZE-1] = schedulable[GFIFO_SIZE-1] ^ sel_idx[GFIFO_SIZE-1];
                            2'b01: schedulable_comb[GFIFO_SIZE-1] = schedulable[GFIFO_SIZE-1];
                            default: schedulable_comb[GFIFO_SIZE-1] = 1'b0;
                        endcase 
                    end
                end
            end

            always@(posedge clk) begin
                if(~rst_n)
                    schedulable[i] <= #TCQ 1'b0;
                else
                    schedulable[i] <= #TCQ schedulable_comb[i];
            end
        end    
    endgenerate
    
    // extracting the selected request and its corresponding data pointer

    for (gfifo_idx=0; gfifo_idx<GFIFO_SIZE; gfifo_idx++) begin : REQ_IDX
        for (packet_idx=0; packet_idx<PACKET_WDITH; packet_idx++) begin : PCKT_IDX
            assign request_extract_1[gfifo_idx][packet_idx] = (gfifo[gfifo_idx][packet_idx] & sel_idx[gfifo_idx]);
            assign request_extract_2[packet_idx][gfifo_idx] = request_extract_1[gfifo_idx][packet_idx];
            assign won_request[packet_idx] = |request_extract_2[packet_idx];
        end
    end

    for (gfifo_idx=0; gfifo_idx<GFIFO_SIZE; gfifo_idx++) begin
        for (packet_idx=0; packet_idx<DPTR_WIDTH; packet_idx++) begin
            assign dptr_extract_1[gfifo_idx][packet_idx]    = (dptr_fifo[gfifo_idx][packet_idx] & sel_idx[gfifo_idx]);
            assign dptr_extract_2[packet_idx][gfifo_idx]    = dptr_extract_1[gfifo_idx][packet_idx];
            assign won_dptr[packet_idx]                     = |dptr_extract_2[packet_idx];
        end
    end
    
    assign won_open     = is_there_any_ready;
    assign won          = |sel_idx;
    assign won_addr     = won_request.addr;
    assign won_ap       = won_request.ap;
    assign won_cmd      = won_request.cmd;
    assign won_inject   = won_request.inject;

    // finding the one-hot index of a completed request
    for (i=0; i<GFIFO_SIZE; i++) begin : DONE_IDX
        assign done_request_idx_rd[i] = ({dptr_fifo[i].req_type, dptr_fifo[i].dptr}   == {1'b1, done_rd_dptr}) & dptr_fifo[i].valid;
        assign done_request_idx_wr[i] = ({dptr_fifo[i].req_type, dptr_fifo[i].dptr}   == {1'b0, done_wr_dptr}) & dptr_fifo[i].valid;
    end

    always@(*) begin
        case({init_data_rd, init_data_wr, init_data_d1})
            3'b000:
                    done_request_idx = 'b0;
            3'b100:
                    done_request_idx = done_request_idx_rd;
            3'b010:
                    done_request_idx = done_request_idx_wr;
            3'b110:
                    done_request_idx = done_request_idx_rd;
            3'b001:
                    done_request_idx = done_request_idx_wr_d1;
            3'b101:
                    done_request_idx = done_request_idx_wr_d1 | done_request_idx_rd;
            3'b011:
                    done_request_idx = done_request_idx_wr_d1 | done_request_idx_wr;
            3'b111:
                    done_request_idx = done_request_idx_wr_d1 | done_request_idx_rd;
            default:
                    done_request_idx = 'b0;      
        endcase
    end

    // assigning outputs
    assign done_valid       = |done_request_idx;
    
    // creating the pattern to know which indices should be shifted
    // for instance if done_request_idx = 8'b0010_0000
    //                 shift_enable     = 8'b1110_0000
    // OPTIMIZATION: THIS TECHNIQUE MAY AFFECT TO CRITICAL PATH, LARGE OR GATE
    for (i=0; i<GFIFO_SIZE; i++) begin : SHIFT_IDX
        if(i==0) begin
            assign shift_enable[0] = done_request_idx[0];    
        end
        else begin
            assign shift_enable[i] = |done_request_idx[i:0];
        end
    end


    /////////////////////////////////////////////////////////////////////////////////////
    /////                               gfifo updating                              /////                       
    /////////////////////////////////////////////////////////////////////////////////////
    
    generate
        for (i=0; i<GFIFO_SIZE; i++) begin : GFIFO_IDX
            if(i<GFIFO_SIZE-1) begin
                assign gfifo_ns[i] = (wr_en[i]) ? arrived_request : ((shift_enable[i]) ? gfifo[i+1] : gfifo[i]);
            
            end else begin
                assign gfifo_ns[GFIFO_SIZE-1] = (wr_en[GFIFO_SIZE-1]) ? arrived_request : gfifo[GFIFO_SIZE-1];
            end
            always@(posedge clk) begin
                if(~rst_n)
                    gfifo_r[i] <= #TCQ 'b0;
                else
                    gfifo_r[i] <= #TCQ gfifo_ns[i];
            end
            assign gfifo[i] = gfifo_r[i];  
        end  
    endgenerate

    // updating write pointer
    // wr_en pointer is used for global fifo which indicates the location new request is written
    assign wr_en = first_empty_index_comb[GFIFO_SIZE-1:0];
    
    
    /////////////////////////////////////////////////////////////////////////////////////
    /////                       last_occupied_index updating                        /////                       
    /////////////////////////////////////////////////////////////////////////////////////
    
    // last_occupied_index is an one-hot writer pointer pointing to the last written (last occupied) index
    // within data pointer fifo. Sometimes instead of using first_empty_index pointer we need last_occupied_index
    // pointer to write a dptr in the fifo

    always @(posedge clk) begin
        if(~rst_n)
            last_occupied_index <= #TCQ {{(GFIFO_SIZE){1'b0}}, 1'b1};
        else begin 
            last_occupied_index <= #TCQ last_occupied_index_comb;
        end
    end    

    always @(*) begin
        case ({use_addr, done_valid})
            2'b10: last_occupied_index_comb = {last_occupied_index[GFIFO_SIZE-1:0], 1'b0};
            2'b01: last_occupied_index_comb = {1'b0, last_occupied_index[GFIFO_SIZE:1]};
            default: last_occupied_index_comb = last_occupied_index;
        endcase
    end
    
    
    /////////////////////////////////////////////////////////////////////////////////////
    /////                       first_empty_index updating                          /////                       
    /////////////////////////////////////////////////////////////////////////////////////

    // first_empty_index is an one-hot writer pointer pointing to the first empty index of global fifo  
    // scenarios:
    //              1- when new request arrives, the pointer is shifted to right by 1 bit
    //              2- when a request finishes, the pointer is shifted to left by 1 bit

    always @(posedge clk) begin
        if(~rst_n)
            first_empty_index <= #TCQ {{(GFIFO_SIZE){1'b0}}, 1'b1};
        else begin 
            first_empty_index <= #TCQ first_empty_index_comb;
        end
    end    

    always @(*) begin
        case ({use_addr, done_valid})
            2'b10: first_empty_index_comb = is_full_r ? first_empty_index : {first_empty_index[GFIFO_SIZE-1:0], 1'b0};
            2'b01: first_empty_index_comb = {1'b0, first_empty_index[GFIFO_SIZE:1]};
            default: first_empty_index_comb = first_empty_index;
        endcase
    end

    // determining when the queue is full
    assign is_full = first_empty_index_comb[GFIFO_SIZE-1];

    always @(posedge clk) begin
        is_full_r <= #TCQ is_full;
    end

endmodule