# defaults
SIM ?= icarus
WAVES = 1
TOPLEVEL_LANG ?= verilog
SOURCE_FOLDER=../../rtl

COMPILE_ARGS += -DSPEED_100M=1

ifeq ($(SIM), verilator)
EXTRA_ARGS += --trace --trace-fst
endif

ifeq ($(SIM), icarus)
#COMPILE_ARGS += -y/home/bawj/lscc/diamond/3.14/cae_library/simulation/verilog/ecp5u/
ifeq ($(WAVES), 1)
		VERILOG_SOURCES += iverilog_dump.v
		COMPILE_ARGS += -s iverilog_dump
endif
endif

VERILOG_SOURCES += t_rgmii_rcv.sv 
VERILOG_SOURCES += $(SOURCE_FOLDER)/mac_decode.sv 
VERILOG_SOURCES += $(SOURCE_FOLDER)/clk_div.sv 
VERILOG_SOURCES += $(SOURCE_FOLDER)/rgmii_rcv.sv 
VERILOG_SOURCES += $(SOURCE_FOLDER)/crc32.sv 
VERILOG_SOURCES += $(SOURCE_FOLDER)/iddr.sv 

# use VHDL_SOURCES for VHDL files

# TOPLEVEL is the name of the toplevel module in your Verilog or VHDL file
TOPLEVEL = t_rgmii_rcv

# MODULE is the basename of the Python test file
MODULE = test_rgmii_rcv

# include cocotb's make rules to take care of the simulator setup
include $(shell cocotb-config --makefiles)/Makefile.sim

iverilog_dump.v:
	echo 'module iverilog_dump();' > $@
	echo 'initial begin' >> $@
	echo '    $$dumpfile("$(TOPLEVEL).fst");' >> $@
	echo '    $$dumpvars(0, $(TOPLEVEL));' >> $@
	echo 'end' >> $@
	echo 'endmodule' >> $@

clean::
	@rm -rf iverilog_dump.v
	@rm -rf dump.fst $(TOPLEVEL).fst
