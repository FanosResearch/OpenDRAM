# -----------------------------------------------------------------------------
#  Copyright (C) 2025 McMaster University, University of Waterloo
#  Copyright and related rights are licensed under the Solderpad Hardware
#  License, Version 0.51 (the "License"); you may not use this file except in
#  compliance with the License. You may obtain a copy of the License at
#  http://solderpad.org/licenses/SHL-0.51. Unless required by applicable law
#  or agreed to in writing, software, hardware and materials distributed under
#  this License is distributed on an "AS IS" BASIS, WITHOUT WARRANTIES OR
#  CONDITIONS OF ANY KIND, either express or implied. See the License for the
#  specific language governing permissions and limitations under the License.
# -----------------------------------------------------------------------------

# create a project to instantiate MIG IP
create_project mig_ip -force ./gen/mig_ip/ -part xcvu9p-flga2104-2L-e

# set board part
set_property board_part xilinx.com:vcu118:part0:2.4 [current_project]

# instantiate MIG IP
create_ip -name ddr4 -vendor xilinx.com -library ip -version 2.2 -module_name ddr4_0
set_property -dict [list \
    CONFIG.RESET_BOARD_INTERFACE {reset} \
    CONFIG.C0_CLOCK_BOARD_INTERFACE {default_250mhz_clk1} \
    CONFIG.C0_DDR4_BOARD_INTERFACE {ddr4_sdram_c1_083} \
    CONFIG.C0.DDR4_TimePeriod {833} \
    CONFIG.C0.DDR4_InputClockPeriod {4000} \
    CONFIG.C0.DDR4_CLKOUT0_DIVIDE {5} \
    CONFIG.C0.DDR4_MemoryPart {MT40A256M16GE-083E} \
    CONFIG.C0.DDR4_DataWidth {64} \
    CONFIG.C0.DDR4_AxiSelection {true} \
    CONFIG.C0.DDR4_CasWriteLatency {12} \
    CONFIG.C0.DDR4_AxiDataWidth {512} \
    CONFIG.C0.DDR4_AxiAddressWidth {31} \
    CONFIG.C0.DDR4_AxiIDWidth {16} \
    CONFIG.ADDN_UI_CLKOUT1_FREQ_HZ {100} \
    CONFIG.Debug_Signal {Disable} \
    CONFIG.C0.BANK_GROUP_WIDTH {1}] \
    [get_ips ddr4_0]
set_property generate_synth_checkpoint false [get_files ddr4_0.xci]
generate_target all [get_files ddr4_0.xci]

# change the current directory to the MIG project folder
cd [get_property DIRECTORY [current_project]]

# open MIG example design
open_example_project -force -dir .. [get_ips ddr4_0]
close_project
open_project ../ddr4_0_ex/ddr4_0_ex.xpr

# change the current directory to the MIG example design folder
cd [get_property DIRECTORY [current_project]]

# take control of the MIG IP from Vivado and make it user-managed by locking it
set_property IS_LOCKED true [get_files ddr4_0.xci]

# instantiate AXI VIP
create_ip -name axi_vip -vendor xilinx.com -library ip -version 1.1 -module_name axi_vip_0
set_property -dict [list \
    CONFIG.INTERFACE_MODE {MASTER} \
    CONFIG.ADDR_WIDTH {31} \
    CONFIG.DATA_WIDTH {512} \
    CONFIG.ID_WIDTH {16} \
    CONFIG.SUPPORTS_NARROW {0} \
    CONFIG.HAS_BURST {1} \
    CONFIG.HAS_LOCK {0} \
    CONFIG.HAS_CACHE {1} \
    CONFIG.HAS_SIZE {1} \
    CONFIG.HAS_REGION {0} \
    CONFIG.HAS_QOS {0} \
    CONFIG.HAS_PROT {1} \
    CONFIG.HAS_ACLKEN {1} \
    ] [get_ips axi_vip_0]
generate_target all [get_files axi_vip_0.xci]

# copy the provided ddr4_0_ex folder to the example design project directory (replace files)
proc copy_directory_recursive {src dst} {
    if {![file exists $dst]} {
        file mkdir $dst
    }
    foreach item [glob -nocomplain -directory $src *] {
        set base [file tail $item]
        set target "$dst/$base"
        if {[file isdirectory $item]} {
            copy_directory_recursive $item $target
        } else {
            file copy -force $item $target
        }
    }
}
set cwd [pwd]
copy_directory_recursive $cwd/../../src/ddr4_0_ex/ $cwd

# add the following folder to the project as design sources
# [repository_path]\src\opendram
# ** adding these sources may disrupt the hierarchy window. However, this step is mandatory in order to modify sub-modules of a secured Xilinx IP **
# ** you can check the elaborated design, simulation scope, or netlist after completing all of the steps to make sure the integration is done successfully **
set relative_import_path "src/opendram"
set full_import_path "$cwd/../../$relative_import_path"
set file_list [glob -nocomplain -directory $full_import_path *]
foreach file $file_list { add_files -norecurse -fileset sources_1 $file }

# import AXI VIP files as simulation source
# [repository_path]\src\axi_vip
set relative_import_path "src/axi_vip"
set full_import_path "$cwd/../../$relative_import_path"
set file_list [glob -nocomplain -directory $full_import_path *]
foreach file $file_list { add_files -norecurse -fileset sim_1  $file }

# include directories for re-used Xilinx modules
set current_includes [get_property include_dirs [current_fileset]]
set_property include_dirs "$current_includes \
    ./ddr4_0_ex.srcs/sources_1/ip/ddr4_0/rtl/controller \
    ./ddr4_0_ex.srcs/sources_1/ip/ddr4_0/rtl/cal" \
    [current_fileset]

# open Vivado GUI
start_gui
