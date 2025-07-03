# defaults
SIM ?= icarus
WAVES = 1
TOPLEVEL_LANG ?= verilog

ifeq ($(SIM), verilator)
EXTRA_ARGS += --trace --trace-fst
endif

ifeq ($(SIM), icarus)
COMPILE_ARGS += -y/home/bawj/lscc/diamond/3.14/cae_library/simulation/verilog/ecp5u/
PLUSARGS += -fst
ifeq ($(WAVES), 1)
		VERILOG_SOURCES += iverilog_dump.v
		COMPILE_ARGS += -s iverilog_dump
endif
endif

VERILOG_SOURCES += ../../crc32.sv 

# use VHDL_SOURCES for VHDL files

# TOPLEVEL is the name of the toplevel module in your Verilog or VHDL file
TOPLEVEL = crc32

# MODULE is the basename of the Python test file
MODULE = test_crc

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
