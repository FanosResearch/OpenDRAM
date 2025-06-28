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

/***************************************************************************************************
 * Abstract:
 * This stimulus is used to generate directed AXI transactions from multiple memory traces,
 * mimicking a multi-master system. The stimulus issues multiple transactions from each core in an
 * out-of-order manner.
 * The system is configured to connect to the Oprecomp DDR4 Memory Controller.
 * Engineer: Ali Abbasi
 * Company: McMaster University, Ontario, Canada
 * Date: 2 January 2025
***************************************************************************************************/

import axi_vip_pkg::*;
import axi_vip_0_pkg::*;

  /*************************************************************************************************
  * <component_name>_mst_t for master agent
  * <component_name> can be easily found in vivado bd design: click on the instance, 
  * Then click CONFIG under Properties window and Component_Name will be shown
  * More details please refer PG267 section about "Useful Coding Guidelines and Examples"
  * for more details.
  *************************************************************************************************/
  axi_vip_0_mst_t                               mst_agent;

  /*************************************************************************************************
  * Declare variables which will be used in API and parital randomization for transaction generation
  * and data read back from driver.
  *************************************************************************************************/
  axi_transaction                                          wr_trans;            // Write transaction
  axi_transaction                                          rd_trans;            // Read transaction
  
  // Error count to check how many comparison failed
  xil_axi_uint                                            error_cnt = 0;
 
  /** Variables for response storage */
  axi_transaction                                          wr_resp;
  axi_transaction                                          rd_resp;
  
  /** Variables for cycle management */
  bit aclk;
  bit[127 : 0] current_cycle;
  longint simulation_start_cycle;
 
  /** Variables for file operations */
  bit [`AXI_ID_WIDTH-1:0] trace_index_binary = {`AXI_ID_WIDTH{1'b0}};
  bit [`NUM_CORES-1:0] slot_active = {`NUM_CORES{1'b0}};
  bit [`NUM_CORES-1:0] slot_vacant = {`NUM_CORES{1'b0}};
  int selected_slot_index;
  string trace_paths [];
  string report_path;
  int fd_r [];
  int fd_w;
  int code;
  string line;
  longint commented_lines_count [];
  longint empty_lines_count [];

  /** Variables to define transactions */
  bit [`AXI_ID_WIDTH-1:0] transaction_id [];
  bit [`AXI_ID_WIDTH-1:0] real_transaction_id;
  bit [`AXI_ADDR_WIDTH-1:0] transaction_addr [];
  longint temp_addr_decimal;
  longint transaction_place_holder [];
  string transaction_type [];
  longint transaction_arrival_cycle [];
  longint transaction_arrival_cycle_previous [];
  longint transaction_send_cycle [];
  longint transaction_response_cycle [];
  longint calculated_send_cycle;
  
  /** Variables to process transaction issuance */
  int rr_ptr = 0;
  int num_outstanding_xact [];
  int first_round_counter [];
  bit [`NUM_CORES-1:0] first_round_flag = {`NUM_CORES{1'b1}};
  bit [`AXI_ID_WIDTH-1:0] received_wr_rsp_id;
  // bit [`AXI_ID_WIDTH-1:0] received_wr_rsp_core_id;
  int received_wr_rsp_core_id;
  bit [`AXI_ID_WIDTH-1:0] received_wr_rsp_xact_id;
  bit [`AXI_ID_WIDTH-1:0] received_rd_rsp_id;
  // bit [`AXI_ID_WIDTH-1:0] received_rd_rsp_core_id;
  int received_rd_rsp_core_id;
  bit [`AXI_ID_WIDTH-1:0] received_rd_rsp_xact_id;
  
  /** Variables for write transactions */
  bit [`AXI_ID_WIDTH-1:0] w_id;
  bit [`AXI_ADDR_WIDTH-1:0] w_addr;
  bit [`AXI_BURST_LENGTH-1:0] [`AXI_DATA_WIDTH-1:0] w_data;
  bit [`AXI_DATA_WIDTH-1:0] write_beat_data = 1;
    
  /** Variables for read transactions */
  bit [`AXI_ID_WIDTH-1:0] r_id;    
  bit [`AXI_ADDR_WIDTH-1:0] r_addr;
 
  task mst_start_stimulus();
    /***********************************************************************************************
    * Before agent is newed, user has to run simulation with an empty testbench to find the hierarchy
    * path of the AXI VIP's instance.Message like
    * "Xilinx AXI VIP Found at Path: my_ip_exdes_tb.DUT.ex_design.axi_vip_mst.inst" will be printed 
    * out. Pass this path to the new function. 
    ***********************************************************************************************/
    mst_agent = new("master vip agent",example_top.axi_vip_0_inst.inst.IF);
    mst_agent.start_master();               // mst_agent start to run
    
    received_wr_rsp_core_id = -1;
    received_rd_rsp_core_id = -1;
    
    /** Initialize write handle for the log file and write the csv header */
    if(`XACT_GEN_REPORT_ENABLE) begin
        $display("[FanosLab] [file_report] Transaction order report is enable.");
        `ifndef LINUX_OS
          report_path = $sformatf("%0s\\%0s.csv", `XACT_GEN_ORDER_PATH, `BENCHMARK_NAME);
        `else
          report_path = $sformatf("%0s/%0s.csv", `XACT_GEN_ORDER_PATH, `BENCHMARK_NAME);
        `endif
        fd_w = $fopen(report_path, "w");
    	if(!fd_w) begin
		  $error("[FanosLab] [file_report] Could not create/open log file!");
		  $finish;
    	end
    	else begin
		  $display("[FanosLab] [file_report] Log file created/opened successfully!");
    	end
        $fdisplay(fd_w, "requester_id,type,core_id,id_hex,addr,place_holder,xact_type,arrival_cycle,resp_cycle,send_cycle,current_cycle");
    end
    else begin
        $display("[FanosLab] [file_report] Transaction order report is disable.");
    end
    
    /** Report the value of the NUM_CORES */
    $display("[FanosLab] NUM_CORES is %0d.", `NUM_CORES);
    
    /** Set the trace_paths array based on the MEM_TRACE_BASE_PATH definition */
    trace_paths = new [`NUM_CORES];
    for(int i = 0; i < `NUM_CORES; i++) begin
     `ifndef LINUX_OS
	      trace_paths[i] = $sformatf("%0s\\%0s\\trace_C%0d.txt", `MEM_TRACE_BASE_PATH, `BENCHMARK_NAME, i);
     `else
	      trace_paths[i] = $sformatf("%0s/%0s/trace_C%0d.txt", `MEM_TRACE_BASE_PATH, `BENCHMARK_NAME, i);
     `endif
	   $display("[FanosLab] Expected path for trace_%0d: %0s", i, trace_paths[i]);
    end
    
    /** Initialize dynamic arrays */
    commented_lines_count               = new [`NUM_CORES];
    empty_lines_count                   = new [`NUM_CORES];
    transaction_id                      = new [`NUM_CORES];
    transaction_addr                    = new [`NUM_CORES];
    transaction_place_holder            = new [`NUM_CORES];
    transaction_type                    = new [`NUM_CORES];
    transaction_arrival_cycle           = new [`NUM_CORES];
    transaction_arrival_cycle_previous  = new [`NUM_CORES];
    transaction_send_cycle              = new [`NUM_CORES];
    transaction_response_cycle          = new [`NUM_CORES];
    num_outstanding_xact                = new [`NUM_CORES];
    first_round_counter                 = new [`NUM_CORES];
    for(int i = 0; i < `NUM_CORES; i++) begin
        commented_lines_count[i] = 0;
        empty_lines_count[i] = 0;
        transaction_id[i] = 0;
        num_outstanding_xact[i] = 0;
        first_round_counter[i] = 0;
    end
    
    /** Assume all slots are vacant in the beginning */
    for(int i = 0; i < `NUM_CORES; i++) begin
	   slot_vacant[i] = 1'b1;
    end
    
    /** Initialize a read handle for each file */
    fd_r = new [`NUM_CORES];
    for(int i = 0; i < $size(trace_paths); i++) begin
    	fd_r[i] = $fopen(trace_paths[i], "r");
    	if(!fd_r[i]) begin
		  $error("[FanosLab] [file_report] Could not open trace[%0d] file!", i);
		  //$finish;
    	end
    	else begin
		  $display("[FanosLab] [file_report] File trace_%0d opened successfully!", i);
    	end
    end
    
    /** Set slots as active based on EOF */
    for(int i = 0; i < $size(fd_r); i++) begin
    	slot_active[i] = ~$feof(fd_r[i]);
    end
    
    fork
    
      /** A separate thread to keep aclk value up-to-data */
      forever begin
        @ (example_top.axi_vip_0_inst.aclk)
        aclk = example_top.axi_vip_0_inst.aclk;
      end
      
      /** A separate thread to keep current_cycle value up-to-data */
      forever begin
        @ (example_top.current_cycle)
        current_cycle = example_top.current_cycle;
      end
      
      /** A separate thread to get write responses in a non-blocking manner */
      forever begin
      
        /** Wait for a write response */
        mst_agent.wr_driver.wait_rsp(wr_resp);
        
        /** Store the id of the received write response */
		received_wr_rsp_id = wr_resp.id;
		received_wr_rsp_core_id = received_wr_rsp_id >> (`AXI_ID_WIDTH - `CORE_INDEX_WIDTH);
		received_wr_rsp_xact_id = received_wr_rsp_id & {(`AXI_ID_WIDTH - `CORE_INDEX_WIDTH){1'b1}};
        
        if(`CUSTUM_DEBUG_MESSAGE_ENABLE) begin
			$display("[FanosLab] [wr_response_received] Response for id %0h with core_id %0h and xact_id %0h received at cycle %0d!", received_wr_rsp_id, received_wr_rsp_core_id, received_wr_rsp_xact_id, current_cycle);
        end
        
        /** Add response to the log file */
		if(`XACT_GEN_REPORT_ENABLE) begin
			$fdisplay(fd_w, "%0d,resp,'d%0d,'h%0h,'h%0h,,%0s,,%0d,,%0d", received_wr_rsp_core_id, received_wr_rsp_core_id, received_wr_rsp_id, wr_resp.addr, "W", current_cycle, current_cycle);
		end
        
        if (received_rd_rsp_core_id != received_wr_rsp_core_id) begin     
            /** Store the cycle in which the write response was received */
		  transaction_response_cycle[received_wr_rsp_core_id] = current_cycle;
		  /** Decrement the num_outstanding_xact for the core that a write response for it was received */
		  num_outstanding_xact[received_wr_rsp_core_id]--;
		end
		received_wr_rsp_core_id = -1;
		
      end
      
      /** A separate thread to get read responses in a non-blocking manner */
      forever begin
      
        /** Wait for a read response */
        mst_agent.rd_driver.wait_rsp(rd_resp);
        
        /** Store the id of the received read response */
		received_rd_rsp_id = rd_resp.id;
		received_rd_rsp_core_id = received_rd_rsp_id >> (`AXI_ID_WIDTH - `CORE_INDEX_WIDTH);
		received_rd_rsp_xact_id = received_rd_rsp_id & {(`AXI_ID_WIDTH - `CORE_INDEX_WIDTH){1'b1}};
        
        if(`CUSTUM_DEBUG_MESSAGE_ENABLE) begin
			$display("[FanosLab] [rd_response_received] Response for id %0h with core_id %0h and xact_id %0h received at cycle %0d!", received_rd_rsp_id, received_rd_rsp_core_id, received_rd_rsp_xact_id, current_cycle);
        end
        
        /** Add response to the log file */
		if(`XACT_GEN_REPORT_ENABLE) begin
			$fdisplay(fd_w, "%0d,resp,'d%0d,'h%0h,'h%0h,,%0s,,%0d,,%0d", received_rd_rsp_core_id, received_rd_rsp_core_id, received_rd_rsp_id, rd_resp.addr, "R", current_cycle, current_cycle);
		end
        
        if (received_rd_rsp_core_id != received_wr_rsp_core_id) begin  
          /** Store the cycle in which the read response was received */
		  transaction_response_cycle[received_rd_rsp_core_id] = current_cycle;
		  /** Decrement the num_outstanding_xact for the core that a read response for it was received */
		  num_outstanding_xact[received_rd_rsp_core_id]--;
		end
		received_rd_rsp_core_id = -1;
		
      end
    join_none
    
    /** Store the cycle in which the simulation was started */
    /** Used when sending the first transaction of each core */
    simulation_start_cycle = current_cycle;
    if(`CUSTUM_DEBUG_MESSAGE_ENABLE) begin
		$display("[FanosLab] [clock_report] Simulation started at cycle %0d!", simulation_start_cycle);
    end
    
    /** Run the algorithm until slot[0] gets deactivated (trace_0 reaches EOF) */
    while(slot_active[0] != 0) begin
	
		/** Traverse traces/files in a RR fashion */
		for(int i = 0; i < `NUM_CORES; i++) begin

			if(`CUSTUM_DEBUG_MESSAGE_ENABLE) begin
				$display("[FanosLab] [file_report] Traversing trace_%0d with slot_active = %0b, slot_vacant = %0b", i, slot_active, slot_vacant);		
			end

			/** Check if the slot is active and vacant before reading from file */
			if(slot_active[i] == 1'b1 && slot_vacant[i] == 1'b1) begin

				if(`CUSTUM_DEBUG_MESSAGE_ENABLE) begin
					$display("[FanosLab] [file_report] Reading from trace_%0d", i);
				end

				/** Read lines of a trace until a valid line is found or the file reaches EOF */
				while(!$feof(fd_r[i])) begin
				
					code = $fgets(line, fd_r[i]);
	
					/** Skip commented lines */
					if((line[0] == "/" && line[1] == "/") || line[0] == "$") begin
					
						/* Generate a message if a commented line is read */
						if(`CUSTUM_DEBUG_MESSAGE_ENABLE) begin
							$display("[FanosLab] [file_report] Commented line in trace[%0d]: %0s", i, line.substr(0, line.len()-2));
						end
			
						/** Increment the commented lines counter */
						/** If it reaches its maximum value, start again from one to avoid overflow */
						if(commented_lines_count[i] == 2**$bits(commented_lines_count[i]) - 1) begin
							commented_lines_count[i] = 1;
						end
						else begin
							commented_lines_count[i]++;
						end
	
						continue;
					end

					/** Skip empty lines */
					if(line.len() < 'd2) begin

						/* Generate a message if an empty line is read */
						if(`CUSTUM_DEBUG_MESSAGE_ENABLE) begin
							$display("[FanosLab] [file_report] Empty line in trace[%0d] ignored.", i);
						end

						/** Increment the empty lines counter */
						/** If it reaches its maximum value, start again from one to avoid overflow */
						if(empty_lines_count[i] == 2**$bits(empty_lines_count[i]) - 1) begin
							empty_lines_count[i] = 1;
						end
						else begin
							empty_lines_count[i]++;
						end

						continue;
					end

					/* Generate a message if the read line is valid and not either commented or empty */
					if(`CUSTUM_DEBUG_MESSAGE_ENABLE) begin
						$display("[FanosLab] [file_report] Valid line in trace[%0d]: %0s", i, line.substr(0, line.len()-2));
					end

					/** Store the arrival cycle of the previous transaction before replacing */
					/** To be used when calculating the send_cycle */
					transaction_arrival_cycle_previous[i] = transaction_arrival_cycle[i];

					/** Read the formated data from the line */
					if (`INPUT_TRC_FORMAT == "FORMAT1") begin
					   code = $sscanf(line, "%d %s %d\n", temp_addr_decimal, transaction_type[i], transaction_arrival_cycle[i]);
                       transaction_addr[i] = temp_addr_decimal;
					end
					else if (`INPUT_TRC_FORMAT == "FORMAT2") begin
					   code = $sscanf(line, "%h %d %s %d\n", transaction_addr[i], transaction_place_holder[i], transaction_type[i], transaction_arrival_cycle[i]);
					end

					/** Manipulate transaction ID with trace ID */
					trace_index_binary = {`AXI_ID_WIDTH{1'b0}} | i;
					transaction_id[i] = transaction_id[i] | (trace_index_binary << ($size(transaction_id[i]) - `CORE_INDEX_WIDTH));

					/** Mask transaction_addr offset to avoid "exceeding 4K boundary" */
					transaction_addr[i] = transaction_addr[i] & {{(`AXI_ADDR_WIDTH - `ADDR_OFFSET_LENGTH){1'b1}}, {`ADDR_OFFSET_LENGTH{1'b0}}};
				
					/** Manipulate transaction address with trace ID */
					/** Must be enabled when plan to compare with a multi-core/multi-trace simulation */
					if(`MANIPULATE_ADDR_WITH_TRACE_ID) begin
						transaction_addr[i] = transaction_addr[i] & ~({`CORE_INDEX_WIDTH{1'b1}} << ($size(transaction_addr[i]) - `CORE_INDEX_WIDTH));
						transaction_addr[i] = transaction_addr[i] | (trace_index_binary << ($size(transaction_addr[i]) - `CORE_INDEX_WIDTH));
					end

					/** As a valid transaction assigned to the slot i, change the vacant bit to zero */
					slot_vacant[i] = 1'b0;

					break;	
				end
			end
		
			/** Break the for loop if there is no vacant slot */
			if(slot_vacant == 0) begin
				break;
			end
		end

    	/** Set slot_active bits based on EOF */
    	for(int i = 0; i < $size(fd_r); i++) begin
			if($feof(fd_r[i])) begin
    			slot_active[i] = 1'b0;
    			slot_vacant[i] = 1'b0;
			end
   		end

		/** Caclculate transaction_send_cycle for each active non-vacant slot */
		for(int i = 0; i < `NUM_CORES; i++) begin

			if(slot_active[i] == 1'b1 && slot_vacant[i] == 1'b0) begin

				/** If it is the first OUT_OF_ORDER_STAGES transactions of each core, */
				/** Set the transaction_send_cycle based on the simulation_start_cycle */
				if(first_round_flag[i] == 1'b1) begin
					transaction_send_cycle[i] = simulation_start_cycle + transaction_arrival_cycle[i];
				end

				/** If any response is received, making num_outstanding_xact[i] less than OUT_OF_ORDER_STAGES, */
				/** Set the transaction_send_cycle based on the latest reponse receive cycle */
				else if(num_outstanding_xact[i] < `OUT_OF_ORDER_STAGES) begin
					calculated_send_cycle = transaction_response_cycle[i] + (transaction_arrival_cycle[i] - transaction_arrival_cycle_previous[i]);
					transaction_send_cycle[i] = get_max_value(calculated_send_cycle, transaction_arrival_cycle[i] + simulation_start_cycle);
				end
			end
		end

		if(`CUSTUM_DEBUG_MESSAGE_ENABLE) begin
			$display("[FanosLab] [file_report] Flags are updated to: slot_active = %0b, slot_vacant = %0b", slot_active, slot_vacant);
			/** Report transactions in the slots */
			$display("[FanosLab] [file_report] Showing candidate of each slot @ cycle %0d...", current_cycle);
			for(int i = 0; i < `NUM_CORES; i++) begin
				$display("[FanosLab] [file_report] Candidate from trace_%0d -> type = %0s, addr = %0h, arrival_cycle = %0d, num_outstanding_xact = %0d, response_cycle = %0d, send_cycle = %0d, active_bit = %0b", i, transaction_type[i], transaction_addr[i], transaction_arrival_cycle[i], num_outstanding_xact[i], transaction_response_cycle[i], transaction_send_cycle[i], slot_active[i]);
			end
		end

		/** Find index of the transaction that is ready to get issued */
		/** If no transaction is ready, -1 will be returned */
		selected_slot_index = get_ready_xact_index_ooo(transaction_send_cycle, num_outstanding_xact, slot_active, slot_vacant, current_cycle);

		/** If no transaction is ready, wait for one cycle */
		if(selected_slot_index == -1) begin
			@ (posedge aclk);
		end

		/** Issue the transaction from the selected index */
		if(selected_slot_index != -1) begin

			/** Report selected candidate */
			if(`CUSTUM_DEBUG_MESSAGE_ENABLE) begin
				$display("[FanosLab] [file_report] Selected candidate -> trace = %0d, id = %0h, addr = %0h, place_holder = %0d, type = %0s, arrival_cycle = %0d, resp_cycle = %0d, send_cycle = %0d, current_cycle = %0d", selected_slot_index, transaction_id[selected_slot_index], transaction_addr[selected_slot_index], transaction_place_holder[selected_slot_index], transaction_type[selected_slot_index], transaction_arrival_cycle[selected_slot_index], transaction_response_cycle[selected_slot_index], transaction_send_cycle[selected_slot_index], current_cycle);
			end

			/** Add selected candidate to the log file */
			if(`XACT_GEN_REPORT_ENABLE) begin
				$fdisplay(fd_w, "%0d,req,'d%0d,'h%0h,'h%0h,%0d,%0s,%0d,%0d,%0d,%0d", selected_slot_index, selected_slot_index, transaction_id[selected_slot_index], transaction_addr[selected_slot_index], transaction_place_holder[selected_slot_index], transaction_type[selected_slot_index], transaction_arrival_cycle[selected_slot_index], transaction_response_cycle[selected_slot_index], transaction_send_cycle[selected_slot_index], current_cycle);
			end

			/** Generate a write transaction */
			if(transaction_type[selected_slot_index] == `WRITE) begin

				w_id = transaction_id[selected_slot_index];
				w_addr = transaction_addr[selected_slot_index];

				/** Fill the beats data incrementally, starting from one */
				for(int i = 0; i < `AXI_BURST_LENGTH; i++) begin

					w_data[i] = write_beat_data;

					/** Increment the data value for the next beat */
					/** If it reaches its maximum value, start again from one to avoid overflow */
					if(write_beat_data == 2**`AXI_DATA_WIDTH - 1) begin
						write_beat_data = 1;
					end
						else begin
						write_beat_data++;
					end
				end

				/** Generate a message once a write transaction is read from benchmark and is about to send */
				if(`CUSTUM_DEBUG_MESSAGE_ENABLE) begin
					$display("[FanosLab] [send_write_transaction_from_trace%0d] WRITE_TRANSACTION @ cycle %0d -> trace = %0d, id = %0h, w_addr = %0h, arrival_cycle = %0d", selected_slot_index, current_cycle, selected_slot_index, w_id, w_addr, transaction_arrival_cycle[selected_slot_index]);
				end

				/** Call the function to generate the directed write transaction */	         
                single_write_transaction_api("single write with api",
                                 .id(w_id),
                                 .addr(w_addr),
                                 .len(`AXI_BURST_LENGTH - 1), 
                                 .burst(XIL_AXI_BURST_TYPE_INCR),
                                 .data(w_data)
                                 );
				
			end

			/** Generate a read transaction */
			else if(transaction_type[selected_slot_index] == `READ) begin

				r_id = transaction_id[selected_slot_index];
				r_addr = transaction_addr[selected_slot_index];

				/** Generate a message once a read transaction is read from benchmark and is about to send */
				if(`CUSTUM_DEBUG_MESSAGE_ENABLE) begin
					$display("[FanosLab] [send_read_transaction_from_trace%0d] READ_TRANSACTION @ cycle %0d -> trace = %0d, id = %0h, r_addr = %0h, arrival_cycle = %0d", selected_slot_index, current_cycle, selected_slot_index, r_id, r_addr, transaction_arrival_cycle[selected_slot_index]);
				end

				/** Call the function to generate the directed read transaction */
                single_read_transaction_api("single read with api",
                                 .id(r_id),
                                 .addr(r_addr),
                                 .len(`AXI_BURST_LENGTH - 1), 
                                 .burst(XIL_AXI_BURST_TYPE_INCR)
                                 );
                                 
			end

			/** Increment the transaction ID for the next transaction of the same trace */
			/** If it reaches its maximum value, start again from one to avoid overflow */
			real_transaction_id = transaction_id[selected_slot_index] & ~({`CORE_INDEX_WIDTH{1'b1}} << ($size(transaction_id[selected_slot_index]) - `CORE_INDEX_WIDTH));
			if(real_transaction_id == 2**(`AXI_ID_WIDTH - `CORE_INDEX_WIDTH) - 1) begin
				transaction_id[selected_slot_index] = 0;
			end
			else begin
				transaction_id[selected_slot_index]++;
			end

			/** Increment the num_outstanding_xact for this core */
			num_outstanding_xact[selected_slot_index]++;

			/** Inceremnt the first_round_counter only for the first OUT_OF_ORDER_STAGES transactions for each core*/
			if(first_round_flag[selected_slot_index] == 1'b1) begin

				first_round_counter[selected_slot_index]++;

				if(first_round_counter[selected_slot_index] == `OUT_OF_ORDER_STAGES) begin
					first_round_flag[selected_slot_index] = 1'b0;
				end
			end

			/** Set the slot as vacant when the transaction in it is sent */
			slot_vacant[selected_slot_index] = 1'b1;
		end
    end
    
    /** Wait until core[0] has no outstanding transactions */
    /** i.e. all responses for its requests are received */
    while (num_outstanding_xact[0] != 0) begin
        @ (posedge aclk);
    end
    
    /** Store the cycle in which the simulation was ended */
    if(`CUSTUM_DEBUG_MESSAGE_ENABLE) begin
		$display("[FanosLab] [clock_report] Simulation ended at cycle %0d!", current_cycle);
    end
    
    /** Close all files */
    for(int i = 0; i < $size(fd_r); i++) begin
	   $display("[FanosLab] [file_report] EOF Reached in trace[%0d], %0d commented lines and %0d empty lines ignored, closing file.", i, commented_lines_count[i], empty_lines_count[i]-1);
	   $fclose(fd_r[i]);
	   $display("[FanosLab] [file_report] File trace[%0d] closed!", i);
    end
    if(`XACT_GEN_REPORT_ENABLE) begin
    	$fclose(fd_w);
    end

    $display("[FanosLab] [file_report] All files closed!");
                                                       
    mst_agent.wait_drivers_idle();           // Wait driver is idle then stop the simulation
        
    if(error_cnt ==0) begin
      $display("[FanosLab] EXAMPLE TEST DONE : Test Completed Successfully");
    end else begin  
      $display("[FanosLab] EXAMPLE TEST DONE ",$sformatf("Test Failed: %d Comparison Failed", error_cnt));
    end 
    $finish;
  endtask
    
  
  /********************************************************
  * function to find the maximum value between two numbers
  ********************************************************/
  function longint get_max_value(longint value_a, longint value_b);
	 if(value_a >= value_b) begin
		return value_a;
	 end
	 else begin
		return value_b;
	 end
  endfunction: get_max_value  
  
  
  /***********************************************************************************************************************************
  * function to find the ready transaction among all slots with respect to their arrival cycle and number of outstanding transactions 
  ***********************************************************************************************************************************/
  function int get_ready_xact_index_ooo(longint transaction_send_cycle [], int num_outstanding_xact [], bit [2**`AXI_ID_WIDTH-1:0] slot_active, bit [2**`AXI_ID_WIDTH-1:0] slot_vacant, longint current_cycle);
	 /** Assume that there is no ready transaction */
	 automatic int ready_slot_index = -1;
	 
	 /** Traverse all cores in a round-robin fashion */
	 /** i counter makes sure that we check each core only and only once */
	 for(int i = 0; i < `NUM_CORES; i++) begin
	   	/** First check if that core is active, its slot is not vacant, and has not reached the maximum number of outstanding transactions */
		if(slot_active[rr_ptr] == 1'b1 && slot_vacant[rr_ptr] == 1'b0 && num_outstanding_xact[rr_ptr] < `OUT_OF_ORDER_STAGES) begin
			/** Check if it is ready to be issued */
			if(transaction_send_cycle[rr_ptr] <= current_cycle) begin
				ready_slot_index = rr_ptr;
 		        /** increment round-robin pointer */
 		        rr_ptr = (rr_ptr + 1)%`NUM_CORES;
				break;
 			end
 		end
 		/** increment round-robin pointer */
 		rr_ptr = (rr_ptr + 1)%`NUM_CORES;
	 end
	 
//	 /** Traverse all cores */
//	 for(int i = 0; i < `NUM_CORES; i++) begin
//		/** First check if that core is active, its slot is not vacant, and has not reached the maximum number of outstanding transactions */
//		if(slot_active[i] == 1'b1 && slot_vacant[i] == 1'b0 && num_outstanding_xact[i] < `OUT_OF_ORDER_STAGES) begin
//			/** Check if it is ready to be issued */
//			if(transaction_send_cycle[i] <= current_cycle) begin
//				ready_slot_index = i;
//				break;
// 			end
// 		end
//	 end

     return ready_slot_index;
  endfunction: get_ready_xact_index_ooo


  /************************************************************************************************
  *  task single_write_transaction_api is to create a single write transaction, fill in transaction 
  *  by using APIs and send it to write driver.
  *   1. declare write transction
  *   2. Create the write transaction
  *   3. set addr, burst,ID,length,size by calling set_write_cmd(addr, burst,ID,length,size), 
  *   4. set prot.lock, cache,region and qos
  *   5. set beats
  *   6. set AWUSER if AWUSER_WIDH is bigger than 0
  *   7. set WUSER if WUSR_WIDTH is bigger than 0
  *************************************************************************************************/
  task automatic single_write_transaction_api ( 
                                input string                     name ="single_write",
                                input xil_axi_uint               id =0, 
                                input xil_axi_ulong              addr =0,
                                input xil_axi_len_t              len =0, 
                                input xil_axi_size_t             size =xil_axi_size_t'(xil_clog2((`AXI_DATA_WIDTH)/8)),
                                input xil_axi_burst_t            burst =XIL_AXI_BURST_TYPE_INCR,
                                input xil_axi_lock_t             lock = XIL_AXI_ALOCK_NOLOCK,
                                input xil_axi_cache_t            cache =3,
                                input xil_axi_prot_t             prot =0,
                                input xil_axi_region_t           region =0,
                                input xil_axi_qos_t              qos =0,
                                input xil_axi_data_beat [255:0]  wuser =0, 
                                input xil_axi_data_beat          awuser =0,
                                input bit [32767:0]              data =0
                                                );
    axi_transaction                               wr_trans;
    wr_trans = mst_agent.wr_driver.create_transaction(name);
    wr_trans.set_driver_return_item_policy(XIL_AXI_PAYLOAD_RETURN);
    wr_trans.set_write_cmd(addr,burst,id,len,size);
    wr_trans.set_prot(prot);
    wr_trans.set_lock(lock);
    wr_trans.set_cache(cache);
    wr_trans.set_region(region);
    wr_trans.set_qos(qos);
    wr_trans.set_data_block(data);
    for (xil_axi_uint i = 0; i <= len; i++) begin
        wr_trans.set_strb_beat(i, {XIL_AXI_MAX_DATA_WIDTH/8{1'b1}});
    end
    mst_agent.wr_driver.send(wr_trans);   
    if(`CUSTUM_DEBUG_MESSAGE_ENABLE) begin
    	$display("[FanosLab] AXI WRITE transaction with id %0h issued at cycle %0d", wr_trans.id, current_cycle);
    end
  endtask  : single_write_transaction_api


  /************************************************************************************************
  *  task single_read_transaction_api is to create a single read transaction, fill in command with user
  *  inputs and send it to read driver.
  *   1. declare read transction
  *   2. Create the read transaction
  *   3. set addr, burst,ID,length,size by calling set_read_cmd(addr, burst,ID,length,size), 
  *   4. set prot.lock, cache,region and qos
  *   5. set ARUSER if ARUSER_WIDH is bigger than 0
  *************************************************************************************************/
  task automatic single_read_transaction_api ( 
                                    input string                     name ="single_read",
                                    input xil_axi_uint               id =0, 
                                    input xil_axi_ulong              addr =0,
                                    input xil_axi_len_t              len =0, 
                                    input xil_axi_size_t             size =xil_axi_size_t'(xil_clog2((`AXI_DATA_WIDTH)/8)),
                                    input xil_axi_burst_t            burst =XIL_AXI_BURST_TYPE_INCR,
                                    input xil_axi_lock_t             lock =XIL_AXI_ALOCK_NOLOCK ,
                                    input xil_axi_cache_t            cache =3,
                                    input xil_axi_prot_t             prot =0,
                                    input xil_axi_region_t           region =0,
                                    input xil_axi_qos_t              qos =0,
                                    input xil_axi_data_beat          aruser =0
                                                );
    axi_transaction                               rd_trans;
    rd_trans = mst_agent.rd_driver.create_transaction(name);
    rd_trans.set_driver_return_item_policy(XIL_AXI_PAYLOAD_RETURN);
    rd_trans.set_read_cmd(addr,burst,id,len,size);
    rd_trans.set_prot(prot);
    rd_trans.set_lock(lock);
    rd_trans.set_cache(cache);
    rd_trans.set_region(region);
    rd_trans.set_qos(qos);
    mst_agent.rd_driver.send(rd_trans);   
    if(`CUSTUM_DEBUG_MESSAGE_ENABLE) begin
    	$display("[FanosLab] AXI READ transaction with id %0h issued at cycle %0d", rd_trans.id, current_cycle);
    end
  endtask  : single_read_transaction_api
