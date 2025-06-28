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
`endif // `ifdef USE_RELATIVE_PATH_INCLUDES

`define TIME_WIDTH  8
`define CMD_TYPE_WIDTH	3


task calculate_constraints;
input  [`CMD_TYPE_WIDTH-1:0]    cur_cmd;
input                      same_bnk;
input                      same_bg;
input                      same_rnk;
output [`TIME_WIDTH-1:0]   PRE_const;
output [`TIME_WIDTH-1:0]   ACT_const;
output [`TIME_WIDTH-1:0]   RD_const;
output [`TIME_WIDTH-1:0]   WR_const;
begin
    if (cur_cmd == `NOP)
    begin
        PRE_const = 0;
        ACT_const = 0;
        RD_const = 0;
        WR_const = 0;
    end
    if (same_bnk) // same bank constraints
    begin
        case (cur_cmd)
        `PRE:
        begin
            PRE_const = `tRC;
            ACT_const = `tRP;
            RD_const  = `tRP + `tRCD;
            WR_const  = `tRP + `tRCD;
         end
        `ACT:
        begin
            PRE_const = `tRAS;
            ACT_const = `tRC;
            RD_const  = `tRCD - `tAL;
            WR_const  = `tRCD - `tAL;
        end
        `CASRD:
        begin
            PRE_const = `tRTP; // tAL + BL + tRTP - tCCD_S
            ACT_const = `tRTP + `tRP;
            RD_const  = `tCCD_L;
            WR_const  = `tCL + `tCCD_L + 2 - `tCWL; 
         end
        `CASWR:
        begin
            PRE_const = `tAL + `tCWL + `BL + `tWR; 
            ACT_const = `tCWL + `BL + `tWR + `tRP;
            RD_const  = `tCWL + `BL + `tWTR_L;
            WR_const  = `tCCD_L;
         end
        `CASRDA:
        begin
            PRE_const = `tRTP;
            ACT_const = `tRTP + `tRP;
            RD_const = `tCCD_L;
            WR_const = `tCL + `tCCD_L + 2 - `tCWL;
        end
        `CASWRA:
        begin
            PRE_const = `tAL + `tCWL + `BL + `tWR;
            ACT_const = `tCWL + `BL + `tWR + `tRP;  
            RD_const = `tCWL + `BL + `tWTR_L;
            WR_const = `tCCD_L;
        end
        default:
        begin
            PRE_const = 0;
            ACT_const = 0;
            RD_const = 0;
            WR_const = 0;
        end
        endcase
    end
    else 
    begin
        if (same_rnk)
        begin
            case (cur_cmd)
            `PRE:
            begin
                PRE_const = 0;
                ACT_const = 0;
                RD_const = 0;
                WR_const = 0;
            end
            `ACT:
            begin
                PRE_const = 0;
                if (same_bg)
                    ACT_const = `tRRD_L; 
                else
                    ACT_const = `tRRD_S;
                RD_const = 0;
                WR_const = 0;
            end
            `CASRD:
            begin
                if (same_bg)
                begin
                    PRE_const = 0;
                    ACT_const = 0; 
                    RD_const = `tCCD_L;
                    WR_const = `tCL + `tCCD_L + 2 - `tCWL;
                end
                else
                begin
                    PRE_const = 0;
                    ACT_const = 0; 
                    RD_const = `tCCD_S;
                    WR_const = `tCL + `tCCD_S + 2 - `tCWL;
                end
             end
            `CASWR:
            begin
                if(same_bg)
                begin
                    PRE_const = 0;
                    ACT_const = 0; 
                    RD_const = `tCWL + `BL + `tWTR_L;
                    WR_const = `tCCD_L;
                end
                else
                begin
                    PRE_const = 0;
                    ACT_const = 0; 
                    RD_const = `tCWL + `BL + `tWTR_S;
                    WR_const = `tCCD_S;
                end
            end
            `CASRDA:
            begin
                if(same_bg)
                begin
                    PRE_const = 0;
                    ACT_const = 0; 
                    RD_const = `tCCD_L;
                    WR_const = `tCL + `tCCD_L + 2 - `tCWL;
                end
                else
                begin
                    PRE_const = 0;
                    ACT_const = 0; 
                    RD_const = `tCCD_S;
                    WR_const = `tCL + `tCCD_S + 2 - `tCWL;
                end
            end
            `CASWRA:
            begin
                if(same_bg)
                begin
                    PRE_const = 0;
                    ACT_const = 0; 
                    RD_const = `tCWL + `BL + `tWTR_L;
                    WR_const = `tCCD_L;
                end
                else
                begin
                    PRE_const = 0;
                    ACT_const = 0; 
                    RD_const = `tCWL + `BL + `tWTR_S;
                    WR_const = `tCCD_S;
                end
            end
            default:
            begin
                PRE_const = 0;
                ACT_const = 0; 
                RD_const = 0;
                WR_const = 0;
            end
               
        endcase
    end
    else
    begin // if sibling rnk
        case (cur_cmd)
        `PRE:
        begin
            PRE_const = 0;
            ACT_const = 0; 
            RD_const = 0;
            WR_const = 0;
        end
        `ACT:
        begin
            PRE_const = 0;
            ACT_const = 0; 
            RD_const = 0;
            WR_const = 0;
        end
        `CASRD:
        begin
            PRE_const = 0;
            ACT_const = 0; 
            RD_const = `BL + `tRTRS;
            WR_const = `tCL + `BL + `tRTRS - `tCWL;
        end
        `CASWR:
        begin
            PRE_const = 0;
            ACT_const = 0; 
            RD_const = `tCWL + `BL + `tRTRS - `tCL;
            WR_const = `BL + `tRTRS;
        end
        `CASRDA:
        begin
            PRE_const = 0;
            ACT_const = 0; 
            RD_const = `BL + `tRTRS;
            WR_const = `tCL + `BL + `tRTRS - `tCWL;
        end
        `CASWRA:
        begin
            PRE_const = 0;
            ACT_const = 0; 
            RD_const = `tCWL + `BL + `tRTRS - `tCL;
            WR_const = `BL + `tRTRS;
        end
        default:
        begin
            PRE_const = 0;
            ACT_const = 0; 
            RD_const = 0;
            WR_const = 0;
        end
        endcase
    end
    end
end
endtask
