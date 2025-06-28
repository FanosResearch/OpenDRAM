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
`else
    `include "time_constraints.vh"
`endif // `ifdef USE_RELATIVE_PATH_INCLUDES


module constraints_calculator#(

    parameter CMD_TYPE_WIDTH    = 3,
    parameter TIME_WIDTH        = 6,
    parameter ISSUED_SUB_CYCLE  = 3
    
    )(
    
    input [CMD_TYPE_WIDTH - 1 : 0] i_sel_cmd,
    input i_same_bank,
    input i_same_bgroup,
    input i_same_rank,
    
    output [TIME_WIDTH - 1 : 0] o_pre_const,
    output [TIME_WIDTH - 1 : 0] o_act_const,
    output [TIME_WIDTH - 1 : 0] o_rd_const,
    output [TIME_WIDTH - 1 : 0] o_wr_const
    
    );
    
    //---------------------------------------------------
    //----------------- Local Parameter -----------------
    //---------------------------------------------------
    
    localparam SUB_CYCLE_OFFSET = (ISSUED_SUB_CYCLE == 0) ? 4 :
                                  (ISSUED_SUB_CYCLE == 1) ? 3 :
                                  (ISSUED_SUB_CYCLE == 2) ? 2 :
                                  (ISSUED_SUB_CYCLE == 3) ? 1 :
                                  0;
    
    //---------------------------------------------------
    //------------------- Definitions -------------------
    //---------------------------------------------------
    
    // intermediate signals to hold the results of calculations
    // and get assigned to the output signals
    logic [TIME_WIDTH - 1 : 0] pre_const_comb;
    logic [TIME_WIDTH - 1 : 0] act_const_comb;
    logic [TIME_WIDTH - 1 : 0] rd_const_comb;
    logic [TIME_WIDTH - 1 : 0] wr_const_comb;
    
    //---------------------------------------------------
    //------------- Continuous Assignments --------------
    //---------------------------------------------------
    
    // assign the calculated combinational values to the outputs
    assign o_pre_const = pre_const_comb;
    assign o_act_const = act_const_comb;
    assign o_rd_const = rd_const_comb;
    assign o_wr_const = wr_const_comb;
    
    //---------------------------------------------------
    //-------------- Calculate Constraints --------------
    //---------------------------------------------------
    
    always_comb begin
        
        // if the selected command is targeting the same bank as the bank that this module is intended for
        
        //-------------- Same Banks --------------
        
        if(i_same_bank) begin
        
            case(i_sel_cmd)
            
                `PRE : begin
                    pre_const_comb <= (`tRC > SUB_CYCLE_OFFSET) ? (`tRC - SUB_CYCLE_OFFSET) : {TIME_WIDTH{1'b0}};
                    act_const_comb <= (`tRP > SUB_CYCLE_OFFSET) ? (`tRP - SUB_CYCLE_OFFSET) : {TIME_WIDTH{1'b0}};
                    rd_const_comb  <= ((`tRP + `tRCD) > SUB_CYCLE_OFFSET) ? ((`tRP + `tRCD) - SUB_CYCLE_OFFSET) : {TIME_WIDTH{1'b0}};
                    wr_const_comb  <= ((`tRP + `tRCD) > SUB_CYCLE_OFFSET) ? ((`tRP + `tRCD) - SUB_CYCLE_OFFSET) : {TIME_WIDTH{1'b0}};
                end
                
                `ACT : begin
                    pre_const_comb <= (`tRAS > SUB_CYCLE_OFFSET) ? (`tRAS - SUB_CYCLE_OFFSET) : {TIME_WIDTH{1'b0}};
                    act_const_comb <= (`tRC > SUB_CYCLE_OFFSET) ? (`tRC - SUB_CYCLE_OFFSET) : {TIME_WIDTH{1'b0}};
                    rd_const_comb <= ((`tRCD - `tAL) > SUB_CYCLE_OFFSET) ? ((`tRCD - `tAL) - SUB_CYCLE_OFFSET) : {TIME_WIDTH{1'b0}};
                    wr_const_comb  <= ((`tRCD - `tAL) > SUB_CYCLE_OFFSET) ? ((`tRCD - `tAL) - SUB_CYCLE_OFFSET) : {TIME_WIDTH{1'b0}};
                end
                
                `CASRD : begin
                    pre_const_comb <= (`tRTP > SUB_CYCLE_OFFSET) ? (`tRTP - SUB_CYCLE_OFFSET) : {TIME_WIDTH{1'b0}}; // tAL + BL + tRTP - tCCD_S
                    act_const_comb <= ((`tRTP + `tRP) > SUB_CYCLE_OFFSET) ? ((`tRTP + `tRP) - SUB_CYCLE_OFFSET) : {TIME_WIDTH{1'b0}};
                    rd_const_comb  <= (`tCCD_L > SUB_CYCLE_OFFSET) ? (`tCCD_L - SUB_CYCLE_OFFSET) : {TIME_WIDTH{1'b0}};
                    wr_const_comb  <= ((`tCL + `tCCD_L + 2 - `tCWL) > SUB_CYCLE_OFFSET) ? ((`tCL + `tCCD_L + 2 - `tCWL) - SUB_CYCLE_OFFSET) : {TIME_WIDTH{1'b0}};
                end

                `CASWR : begin
                    pre_const_comb <= ((`tAL + `tCWL + `BL + `tWR) > SUB_CYCLE_OFFSET) ? ((`tAL + `tCWL + `BL + `tWR) - SUB_CYCLE_OFFSET) : {TIME_WIDTH{1'b0}}; 
                    act_const_comb <= ((`tCWL + `BL + `tWR + `tRP) > SUB_CYCLE_OFFSET) ? ((`tCWL + `BL + `tWR + `tRP) - SUB_CYCLE_OFFSET) : {TIME_WIDTH{1'b0}};
                    rd_const_comb  <= ((`tCWL + `BL + `tWTR_L) > SUB_CYCLE_OFFSET) ? ((`tCWL + `BL + `tWTR_L) - SUB_CYCLE_OFFSET) : {TIME_WIDTH{1'b0}};
                    wr_const_comb  <= (`tCCD_L > SUB_CYCLE_OFFSET) ? (`tCCD_L - SUB_CYCLE_OFFSET) : {TIME_WIDTH{1'b0}};
                end
                
                `CASRDA : begin
                    pre_const_comb <= (`tRTP > SUB_CYCLE_OFFSET) ? (`tRTP - SUB_CYCLE_OFFSET) : {TIME_WIDTH{1'b0}};
                    act_const_comb <= ((`tRTP + `tRP) > SUB_CYCLE_OFFSET) ? ((`tRTP + `tRP) - SUB_CYCLE_OFFSET) : {TIME_WIDTH{1'b0}};
                    rd_const_comb <= (`tCCD_L > SUB_CYCLE_OFFSET) ? (`tCCD_L - SUB_CYCLE_OFFSET) : {TIME_WIDTH{1'b0}};
                    wr_const_comb <= ((`tCL + `tCCD_L + 2 - `tCWL) > SUB_CYCLE_OFFSET) ? ((`tCL + `tCCD_L + 2 - `tCWL) - SUB_CYCLE_OFFSET) : {TIME_WIDTH{1'b0}};
                end
                
                `CASWRA : begin
                    pre_const_comb <= ((`tAL + `tCWL + `BL + `tWR) > SUB_CYCLE_OFFSET) ? ((`tAL + `tCWL + `BL + `tWR) - SUB_CYCLE_OFFSET) : {TIME_WIDTH{1'b0}};
                    act_const_comb <= ((`tCWL + `BL + `tWR + `tRP) > SUB_CYCLE_OFFSET) ? ((`tCWL + `BL + `tWR + `tRP) - SUB_CYCLE_OFFSET) : {TIME_WIDTH{1'b0}}; 
                    rd_const_comb <= ((`tCWL + `BL + `tWTR_L) > SUB_CYCLE_OFFSET) ? ((`tCWL + `BL + `tWTR_L) - SUB_CYCLE_OFFSET) : {TIME_WIDTH{1'b0}};
                    wr_const_comb <= (`tCCD_L > SUB_CYCLE_OFFSET) ? (`tCCD_L - SUB_CYCLE_OFFSET) : {TIME_WIDTH{1'b0}};
                end
                
                default : begin
                    pre_const_comb <= {TIME_WIDTH{1'b0}};
                    act_const_comb <= {TIME_WIDTH{1'b0}};
                    rd_const_comb <= {TIME_WIDTH{1'b0}};
                    wr_const_comb <= {TIME_WIDTH{1'b0}};
                end
            endcase
        end
    
        // if the selected command is not targeting the same bank as the bank that this module is intended for
        
        //-------------- Different Banks --------------
        
        else begin
        
            // if the command is tageting a different bank, but the same rank
            
            //-------------- Different Banks, Same Ranks --------------
            
            if(i_same_rank) begin
            
                case(i_sel_cmd)
                
                    `PRE : begin
                        pre_const_comb <= {TIME_WIDTH{1'b0}};
                        act_const_comb <= {TIME_WIDTH{1'b0}};
                        rd_const_comb <= {TIME_WIDTH{1'b0}};
                        wr_const_comb <= {TIME_WIDTH{1'b0}};
                    end
                    
                    `ACT : begin
                        pre_const_comb <= {TIME_WIDTH{1'b0}};
                        if (i_same_bgroup)
                            act_const_comb <= (`tRRD_L > SUB_CYCLE_OFFSET) ? (`tRRD_L - SUB_CYCLE_OFFSET) : {TIME_WIDTH{1'b0}};
                        else
                            act_const_comb <= (`tRRD_S > SUB_CYCLE_OFFSET) ? (`tRRD_S - SUB_CYCLE_OFFSET) : {TIME_WIDTH{1'b0}};
                        rd_const_comb <= {TIME_WIDTH{1'b0}};
                        wr_const_comb <= {TIME_WIDTH{1'b0}};
                    end
                    
                    `CASRD : begin
                        if (i_same_bgroup) begin
                            pre_const_comb <= {TIME_WIDTH{1'b0}};
                            act_const_comb <= {TIME_WIDTH{1'b0}}; 
                            rd_const_comb <= (`tCCD_L > SUB_CYCLE_OFFSET) ? (`tCCD_L - SUB_CYCLE_OFFSET) : {TIME_WIDTH{1'b0}};
                            wr_const_comb <= ((`tCL + `tCCD_L + 2 - `tCWL) > SUB_CYCLE_OFFSET) ? ((`tCL + `tCCD_L + 2 - `tCWL) - SUB_CYCLE_OFFSET) : {TIME_WIDTH{1'b0}};
                        end
                        else begin
                            pre_const_comb <= {TIME_WIDTH{1'b0}};
                            act_const_comb <= {TIME_WIDTH{1'b0}}; 
                            rd_const_comb <= (`tCCD_S > SUB_CYCLE_OFFSET) ? (`tCCD_S - SUB_CYCLE_OFFSET) : {TIME_WIDTH{1'b0}};
                            wr_const_comb <= ((`tCL + `tCCD_S + 2 - `tCWL) > SUB_CYCLE_OFFSET) ? ((`tCL + `tCCD_S + 2 - `tCWL) - SUB_CYCLE_OFFSET) : {TIME_WIDTH{1'b0}};
                        end
                    end
                    
                    `CASWR : begin
                        if(i_same_bgroup) begin
                            pre_const_comb <= {TIME_WIDTH{1'b0}};
                            act_const_comb <= {TIME_WIDTH{1'b0}}; 
                            rd_const_comb <= ((`tCWL + `BL + `tWTR_L) > SUB_CYCLE_OFFSET) ? ((`tCWL + `BL + `tWTR_L) - SUB_CYCLE_OFFSET) : {TIME_WIDTH{1'b0}};
                            wr_const_comb <= (`tCCD_L > SUB_CYCLE_OFFSET) ? (`tCCD_L - SUB_CYCLE_OFFSET) : {TIME_WIDTH{1'b0}};
                        end
                        else begin
                            pre_const_comb <= {TIME_WIDTH{1'b0}};
                            act_const_comb <= {TIME_WIDTH{1'b0}}; 
                            rd_const_comb <= ((`tCWL + `BL + `tWTR_S) > SUB_CYCLE_OFFSET) ? ((`tCWL + `BL + `tWTR_S) - SUB_CYCLE_OFFSET) : {TIME_WIDTH{1'b0}};
                            wr_const_comb <= (`tCCD_S > SUB_CYCLE_OFFSET) ? (`tCCD_S - SUB_CYCLE_OFFSET) : {TIME_WIDTH{1'b0}};
                        end
                    end
                    
                    `CASRDA : begin
                        if(i_same_bgroup) begin
                            pre_const_comb <= {TIME_WIDTH{1'b0}};
                            act_const_comb <= {TIME_WIDTH{1'b0}};
                            rd_const_comb <= (`tCCD_L > SUB_CYCLE_OFFSET) ? (`tCCD_L - SUB_CYCLE_OFFSET) : {TIME_WIDTH{1'b0}};
                            wr_const_comb <= ((`tCL + `tCCD_L + 2 - `tCWL) > SUB_CYCLE_OFFSET) ? ((`tCL + `tCCD_L + 2 - `tCWL) - SUB_CYCLE_OFFSET) : {TIME_WIDTH{1'b0}};
                        end
                        else begin
                            pre_const_comb <= {TIME_WIDTH{1'b0}};
                            act_const_comb <= {TIME_WIDTH{1'b0}}; 
                            rd_const_comb <= (`tCCD_S > SUB_CYCLE_OFFSET) ? (`tCCD_S - SUB_CYCLE_OFFSET) : {TIME_WIDTH{1'b0}};
                            wr_const_comb <= ((`tCL + `tCCD_S + 2 - `tCWL) > SUB_CYCLE_OFFSET) ? ((`tCL + `tCCD_S + 2 - `tCWL) - SUB_CYCLE_OFFSET) : {TIME_WIDTH{1'b0}};
                        end
                    end

                    `CASWRA : begin
                        if(i_same_bgroup) begin
                            pre_const_comb <= {TIME_WIDTH{1'b0}};
                            act_const_comb <= {TIME_WIDTH{1'b0}};
                            rd_const_comb <= ((`tCWL + `BL + `tWTR_L) > SUB_CYCLE_OFFSET) ? ((`tCWL + `BL + `tWTR_L) - SUB_CYCLE_OFFSET) : {TIME_WIDTH{1'b0}};
                            wr_const_comb <= (`tCCD_L > SUB_CYCLE_OFFSET) ? (`tCCD_L - SUB_CYCLE_OFFSET) : {TIME_WIDTH{1'b0}};
                        end
                        else begin
                            pre_const_comb <= {TIME_WIDTH{1'b0}};
                            act_const_comb <= {TIME_WIDTH{1'b0}};
                            rd_const_comb <= ((`tCWL + `BL + `tWTR_S) > SUB_CYCLE_OFFSET) ? ((`tCWL + `BL + `tWTR_S) - SUB_CYCLE_OFFSET) : {TIME_WIDTH{1'b0}};
                            wr_const_comb <= (`tCCD_S > SUB_CYCLE_OFFSET) ? (`tCCD_S - SUB_CYCLE_OFFSET) : {TIME_WIDTH{1'b0}};
                        end
                    end
            
                    default : begin
                        pre_const_comb <= {TIME_WIDTH{1'b0}};
                        act_const_comb <= {TIME_WIDTH{1'b0}}; 
                        rd_const_comb <= {TIME_WIDTH{1'b0}};
                        wr_const_comb <= {TIME_WIDTH{1'b0}};
                    end       
                endcase
            end
        
            // if the command is tageting a different bank and a different rank
            
            //-------------- Different Banks, Different Ranks --------------
            
            else begin
            
                case(i_sel_cmd)
                
                    `PRE : begin
                        pre_const_comb <= {TIME_WIDTH{1'b0}};
                        act_const_comb <= {TIME_WIDTH{1'b0}}; 
                        rd_const_comb <= {TIME_WIDTH{1'b0}};
                        wr_const_comb <= {TIME_WIDTH{1'b0}};
                    end
                    
                    `ACT : begin
                        pre_const_comb <= {TIME_WIDTH{1'b0}};
                        act_const_comb <= {TIME_WIDTH{1'b0}};
                        rd_const_comb <= {TIME_WIDTH{1'b0}};
                        wr_const_comb <= {TIME_WIDTH{1'b0}};
                    end
                    
                    `CASRD : begin
                        pre_const_comb <= {TIME_WIDTH{1'b0}};
                        act_const_comb <= {TIME_WIDTH{1'b0}};
                        rd_const_comb <= ((`BL + `tRTRS) > SUB_CYCLE_OFFSET) ? ((`BL + `tRTRS) - SUB_CYCLE_OFFSET) : {TIME_WIDTH{1'b0}};
                        wr_const_comb <= ((`tCL + `BL + `tRTRS - `tCWL) > SUB_CYCLE_OFFSET) ? ((`tCL + `BL + `tRTRS - `tCWL) - SUB_CYCLE_OFFSET) : {TIME_WIDTH{1'b0}};
                    end
                    
                    `CASWR : begin
                        pre_const_comb <= {TIME_WIDTH{1'b0}};
                        act_const_comb <= {TIME_WIDTH{1'b0}};
                        rd_const_comb <= ((`tCWL + `BL + `tRTRS - `tCL) > SUB_CYCLE_OFFSET) ? ((`tCWL + `BL + `tRTRS - `tCL) - SUB_CYCLE_OFFSET) : {TIME_WIDTH{1'b0}};
                        wr_const_comb <= ((`BL + `tRTRS) > SUB_CYCLE_OFFSET) ? ((`BL + `tRTRS) - SUB_CYCLE_OFFSET) : {TIME_WIDTH{1'b0}};
                    end
                    
                    `CASRDA : begin
                        pre_const_comb <= {TIME_WIDTH{1'b0}};
                        act_const_comb <= {TIME_WIDTH{1'b0}}; 
                        rd_const_comb <= ((`BL + `tRTRS) > SUB_CYCLE_OFFSET) ? ((`BL + `tRTRS) - SUB_CYCLE_OFFSET) : {TIME_WIDTH{1'b0}};
                        wr_const_comb <= ((`tCL + `BL + `tRTRS - `tCWL) > SUB_CYCLE_OFFSET) ? ((`tCL + `BL + `tRTRS - `tCWL) - SUB_CYCLE_OFFSET) : {TIME_WIDTH{1'b0}};
                    end
                    
                    `CASWRA : begin
                        pre_const_comb <= {TIME_WIDTH{1'b0}};
                        act_const_comb <= {TIME_WIDTH{1'b0}};
                        rd_const_comb <= ((`tCWL + `BL + `tRTRS - `tCL) > SUB_CYCLE_OFFSET) ? ((`tCWL + `BL + `tRTRS - `tCL) - SUB_CYCLE_OFFSET) : {TIME_WIDTH{1'b0}};
                        wr_const_comb <= ((`BL + `tRTRS) > SUB_CYCLE_OFFSET) ? ((`BL + `tRTRS) - SUB_CYCLE_OFFSET) : {TIME_WIDTH{1'b0}};
                    end
        
                    default : begin
                        pre_const_comb <= {TIME_WIDTH{1'b0}};
                        act_const_comb <= {TIME_WIDTH{1'b0}}; 
                        rd_const_comb <= {TIME_WIDTH{1'b0}};
                        wr_const_comb <= {TIME_WIDTH{1'b0}};
                    end
                endcase
            end
        end
    end
endmodule