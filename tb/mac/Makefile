# defaults
SIM ?= icarus
WAVES = 1
TOPLEVEL_LANG ?= verilog
SOURCE_FOLDER=../../rtl

ifeq ($(SIM), verilator)
COMPILE_ARGS += -y /home/bawj/lscc/diamond/3.14/cae_library/simulation/verilog/ecp5u/
EXTRA_ARGS += --trace --trace-fst
COMPILE_ARGS += -I$(SOURCE_FOLDER)/
endif

ifeq ($(SIM), icarus)
COMPILE_ARGS += -y/home/bawj/lscc/diamond/3.14/cae_library/simulation/verilog/ecp5u/
COMPILE_ARGS += -I$(SOURCE_FOLDER)/
PLUSARGS += -fst
ifeq ($(WAVES), 1)
		VERILOG_SOURCES += iverilog_dump.v
		COMPILE_ARGS += -s iverilog_dump
endif
endif

VERILOG_SOURCES += $(SOURCE_FOLDER)/mac.sv 
VERILOG_SOURCES += $(SOURCE_FOLDER)/mac_encode.sv 
VERILOG_SOURCES += $(SOURCE_FOLDER)/oddr.sv 
VERILOG_SOURCES += $(SOURCE_FOLDER)/clk_gen.sv 
VERILOG_SOURCES += $(SOURCE_FOLDER)/rgmii_rcv.sv
VERILOG_SOURCES += $(SOURCE_FOLDER)/rgmii_tx.sv
VERILOG_SOURCES += $(SOURCE_FOLDER)/arp_encode.sv
VERILOG_SOURCES += $(SOURCE_FOLDER)/arp_decode.sv
VERILOG_SOURCES += $(SOURCE_FOLDER)/crc32.sv
VERILOG_SOURCES += $(SOURCE_FOLDER)/iddr.sv

# use VHDL_SOURCES for VHDL files

# TOPLEVEL is the name of the toplevel module in your Verilog or VHDL file
TOPLEVEL = mac

# MODULE is the basename of the Python test file
MODULE = test_mac

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
