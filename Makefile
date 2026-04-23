TOOLPATH=~/oss-cad-suite/bin
YOSYS=yosys
PNR=$(TOOLPATH)/nextpnr-ecp5
PACK=$(TOOLPATH)/ecppack
LOADER=$(TOOLPATH)/openocd
SOURCEDIR=rtl
SOURCES = $(SOURCEDIR)/areset.sv \
	$(SOURCEDIR)/async_fifo_2deep.sv \
	$(SOURCEDIR)/tcp.sv \
	$(SOURCEDIR)/tcb.sv \
	$(SOURCEDIR)/delay.sv \
	$(SOURCEDIR)/arp_decode.sv \
	$(SOURCEDIR)/arp_encode.sv \
	$(SOURCEDIR)/blinky.sv \
	$(SOURCEDIR)/clk_divider.sv \
	$(SOURCEDIR)/clk_gen.sv \
	$(SOURCEDIR)/crc32.sv \
	$(SOURCEDIR)/fifo.sv \
	$(SOURCEDIR)/fifo_sdram.sv \
	$(SOURCEDIR)/iddr.sv \
	$(SOURCEDIR)/ip_decode.sv \
	$(SOURCEDIR)/ip_encode.sv \
	$(SOURCEDIR)/mac.sv \
	$(SOURCEDIR)/mac_tx.sv \
	$(SOURCEDIR)/mac_decode.sv \
	$(SOURCEDIR)/mac_encode.sv \
	$(SOURCEDIR)/mdio.sv \
	$(SOURCEDIR)/sdram_ctrl.sv \
	$(SOURCEDIR)/oddr.sv \
	$(SOURCEDIR)/pulse_stretcher.sv \
	$(SOURCEDIR)/pulse_gen.sv \
	$(SOURCEDIR)/rgmii_rcv.sv \
	$(SOURCEDIR)/rgmii_tx.sv \
	$(SOURCEDIR)/synchronizer.sv \
	$(SOURCEDIR)/tcp_decode.sv \
	$(SOURCEDIR)/top_sdram_debug.sv \
	$(SOURCEDIR)/top_ebr_debug.sv \
	$(SOURCEDIR)/uart.sv \
	$(SOURCEDIR)/udp_decode.sv \
	$(SOURCEDIR)/lfsr_rng.sv \
	$(SOURCEDIR)/ebr.sv \
	$(SOURCEDIR)/spi_master.sv \
	$(SOURCEDIR)/tcp_sm.sv \
	$(SOURCEDIR)/tcp_arbiter.sv \
	$(SOURCEDIR)/tcp_encode.sv \
	tb/ebr/test_ebr_debug.sv \
	$(SOURCEDIR)/top_spi_debug.sv \
	$(SOURCEDIR)/var_int_decoder.sv

TOP=top

.PHONY: sdram
sdram: TOP=top_sdram_debug
sdram: synth

.PHONY: ebr
ebr: TOP=top_ebr_debug
ebr: SOURCES := $(SOURCES) tb/ebr/test_ebr_debug.sv
ebr: synth route program

.PHONY: spi
spi: TOP=top_spi_debug
spi: SOURCES += rtl/top_spi_debug.sv
spi: synth route flash

diag: SHOW_CMD=; select -list; select top/mac_instance.tcb_sm; select -add top/mac_instance.tx.tcp_enc*; show

.PHONY: diag
diag:
	xdot ~/.yosys_show.dot

synth: $(SOURCES)
	$(YOSYS) -D SYNTHESIS=1 -DDEBUG=1 -p "synth_ecp5 -top $(TOP) -json top.json$(SHOW_CMD)" $^

route: synth
	$(PNR) --25k --package CABGA256 --json top.json \
			--lpf pinout.lpf --textcfg top.config --freq 125 --report timing --detailed-timing-report
	$(PACK) --compress --svf top.svf top.config top.bit

program: top.svf
	$(LOADER) -f colorlight.cfg -c "svf -quiet -progress top.svf; exit"

flash: top.bit
	openFPGALoader -c digilent_hs2 -f --unprotect-flash top.bit

.PHONY: all
all: synth route program
	@echo "Do all"

.PHONY: clean
clean:
	rm *.bit
	rm *.svf

.PHONY: arp
arp:
	sudo arping -c 1 -i enp61s0 -t DE:AD:BE:EF:CA:FE -S 192.168.69.100 105.105.105.105

.PHONY: tcp
tcp:
	nc 105.105.105.105 8080
