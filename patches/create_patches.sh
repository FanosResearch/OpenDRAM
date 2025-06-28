# -----------------------------------------------------------------------------
# Copyright 2025 McMaster University, University of Waterloo
# 
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
# 
#     http://www.apache.org/licenses/LICENSE-2.0
# 
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
# -----------------------------------------------------------------------------

#!/bin/bash

diff -u ../gen/ddr4_0_ex/ddr4_0_ex.srcs/sources_1/ip/ddr4_0/rtl/ip_top/ddr4_0_ddr4_mem_intfc.sv ./ddr4_0_ddr4_mem_intfc.sv > ddr4_0_ddr4_mem_intfc.patch
diff -u ../gen/ddr4_0_ex/ddr4_0_ex.srcs/sources_1/ip/ddr4_0/rtl/controller/ddr4_v2_2_mc_ctl.sv ./ddr4_v2_2_mc_ctl.sv > ddr4_v2_2_mc_ctl.patch
diff -u ../gen/ddr4_0_ex/imports/example_top.sv ./example_top.sv > example_top.patch
