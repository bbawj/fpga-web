TOOLPATH=~/oss-cad-suite/bin
YOSYS=$(TOOLPATH)/yosys
PNR=$(TOOLPATH)/nextpnr-ecp5
PACK=$(TOOLPATH)/ecppack
LOADER=$(TOOLPATH)/openocd
SOURCEDIR=rtl
SOURCES = $(SOURCEDIR)/areset.sv \
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
	$(SOURCEDIR)/mac_decode.sv \
	$(SOURCEDIR)/mac_encode.sv \
	$(SOURCEDIR)/mdio.sv \
	$(SOURCEDIR)/mem.sv \
	$(SOURCEDIR)/oddr.sv \
	$(SOURCEDIR)/pulse_stretcher.sv \
	$(SOURCEDIR)/rgmii_rcv.sv \
	$(SOURCEDIR)/rgmii_tx.sv \
	$(SOURCEDIR)/synchronizer.sv \
	$(SOURCEDIR)/tcp_decode.sv \
	$(SOURCEDIR)/top_sdram_debug.sv \
	$(SOURCEDIR)/uart.sv \
	$(SOURCEDIR)/udp_decode.sv \
	$(SOURCEDIR)/lfsr_rng.sv \
	$(SOURCEDIR)/var_int_decoder.sv

MODULE=top
TOP=$(MODULE)
sdram: MODULE="rtl/top_sdram_debug.sv"
sdram: TOP=top_sdram_debug
sdram: synth

synth: $(MODULE).sv $(SOURCES)
	$(YOSYS) -D SYNTHESIS=1 -DSPEED_100M -DDEBUG=1 -p "synth_ecp5 -top $(TOP) -json top.json" $^
	$(PNR) --25k --package CABGA256 --json top.json \
			--lpf pinout.lpf --textcfg top.config
	$(PACK) --svf top.svf top.config top.bit

flash: $(MODULE).svf
	$(LOADER) -f colorlight.cfg -c "svf -quiet -progress $@; exit"

.PHONY: clean
clean:
	rm *.bit
	rm *.svf

.PHONY: arp
arp:
	sudo arping -c 1 -i enp61s0 -t DE:AD:BE:EF:CA:FE -S 192.168.69.100 105.105.105.105makefil
