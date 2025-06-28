# OpenDRAM: A Modular, High-performance Soft Memory Controller for DDR4 DRAM
This repository contains source files related to the proposed memory controller.

## Directories

```
./benchmarks/ -> directory to hold memory traces
./gen/ -> folder in which Vivado project is generated
./patches/ -> patch files used to update AMD MIG files in-place to instantiate OpenDRAM as the controller
./results/ -> holding the simulation log files.
./src/ -> source files for the OpenDRAM and the simulation infrastructure
```

## Requirements
- AMD Vivado Design Suite 2022.1

## Generating OpenDRAM on Ubuntu

There are three scripts that must be executed as follows in three steps.

### Step 1: Updating Source Files

```
./01_update_sources_linux.sh -cs [command_scheduler_version] -part [memory_part]
```

This script updates the source files for the indicated command scheduler version. It also updates the timing constraints files based on the desired memory part.

**Supported values for [command_scheduler_version]:** a number between 1 to 5 (the version index)
    
**Supported values for [memory_part]:** the current version of the repo provides timing constraints for memory parts "mt40a256m16ge083e", and "mt40a512m8rh075e".

### Step 2: Creating Vivado Project, Importing Sources, Generating IPs

```
./02_gen_opendram_linux.sh
```

The script in step 2 creates a Vivado project, imports OpenDRAM sources, and generate AMD MIG and AMD AXI VIP. The Vivado project will open at the end of this script.

### Step 3: Apply Patches to AMD MIG Files to Use OpenDRAM

```
./03_run_patches_linux.sh
```

By using this script, MIG files get updated to instantiate OpenDRAM as the controller.

## Generating OpenDRAM on Windows

Although our script are written for Ubuntu and do not directly work on Windows, users can execute the following three PowerShell scripts to generate OpenDRAM using provided Ubuntu scripts through Windows Subsystem for Linux (WSL).

** Unlike the Ubuntu scripts, the first PowerShell script does not accept any command-line arguments. Therefore, users should change the arguments as desired inside the file, where it calls the Ubuntu script.

Please note that in order to use these scripts, user must:
1. Ensure that the WSL is enabled and the command "wsl" works on their PowerShell
2. Ensure that Vivado can be executed through PowerShell using command "vivado"

## Running Simulationations

Users are able to run simulations using either the synthesizable MIG traffic generator or the non-synthesizable custom infrastructor. The custom simulation infrastructure is developed using AMD AXI VIP, which reads memory access traces in a particular format and generates corresponding requests to the memory controller. Our infrustructure is able to mimic a multi-kernel system in which the arbitration is done in a round-robin fashion. Users can also define the size of stream buffer for kernels. Both type of simulations can be simply run through Vivado ISIM.

Setup parameters for the simulation infrastructure are accessible in the file below.

```
./src/sim_macros.svh
```

Macros in the file (For more clarity, please also read the comments in the file for each macro):
1. *USE_AXI_VIP:* Flag to enable custom simulation infrastructure. Traffic generator is enabled if this macro is not defined.
2. *LINUX_OS:* Flag to indicate the use of Linux OS.
3. *NUM_CORES:* Number of accelerator kernels generating traffic.
4. *CORE_INDEX_WIDTH:* Number of bits required to differenciate between kernels. Should be log2(NUM_CORES).
5. *XACT_GEN_ORDER_PATH:* Path to generate the simulation report.
6. *MEM_TRACE_BASE_PATH:* Base address for the memory traces.
7. *BENCHMARK_NAME:* Name of the benchmark to run.
8. *INPUT_TRC_FORMAT:* The infrastructure supports two trace formats. Select the desired one here.
9. *ADDR_OFFSET_LENGTH:* Number of bits to mask from address LSB
10. *MANIPULATE_ADDR_WITH_TRACE_ID:* Kernel ID is appeneded to the address MSB if defined.
11. *OUT_OF_ORDER_STAGES:* Size of the stream buffer, defined for all kernels.
12. *WRITE:* Character in the trace file that indicates a write request.
13. *READ:* Character in the trace file that indicates a read request.
14. *AXI_ID_WIDTH:* Width of the AXI ID. Must match the memory controller user interface.
15. *AXI_ADDR_WIDTH:* Width of the AXI address. Must match the memory controller user interface.
16. *AXI_DATA_WIDTH:* Width of the AXI data bus. Must match the memory controller user interface.
17. *WSTRB_WIDTH:* Width of the write strobe signal. Calculated automatically based on the value of AXI_DATA_WIDTH
18. *AXI_BURST_LENGTH:* Length of the AXI burst.

## License

This HDL design is licensed under the SolderPad Hardware License, Version 0.51. See the [LICENSE](LICENSE) file for details.
