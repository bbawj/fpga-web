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
	$(SOURCEDIR)/http_decode.sv \
	$(SOURCEDIR)/http_entry.sv \
	$(SOURCEDIR)/ram_sp.sv \
	$(SOURCEDIR)/ram_wrap.sv \
	$(SOURCEDIR)/flash2sdram.sv \
	$(SOURCEDIR)/top_spi_debug.sv \
	top.sv \
	$(SOURCEDIR)/var_int_decoder.sv \
	$(EXTRA_SOURCES)

ROOT=${CURDIR}
DEF_HTTP_ADDR_FILE="$(ROOT)/tools/addrs.mem"
DEF_HTTP_SIZE_FILE="$(ROOT)/tools/lengths.mem"
DEF_TCP_ECHO_EN ?= 0

TOP ?= top

.PHONY: sdram
sdram:
	$(MAKE) TOP=top_sdram_debug EXTRA_SOURCES="$(SOURCEDIR)/top_sdram_debug.sv" synth route program

.PHONY: ebr
ebr:
	$(MAKE) TOP=top_ebr_debug EXTRA_SOURCES="$(SOURCEDIR)/top_ebr_debug.sv tb/ebr/test_ebr_debug.sv" synth route program

.PHONY: spi
spi:
	$(MAKE) TOP=top_spi_debug EXTRA_SOURCES="$(SOURCEDIR)/top_spi_debug.sv" synth route flash

.PHONY: spi_sdram
spi_sdram:
	$(MAKE) TOP=top_flash_sdram_debug EXTRA_SOURCES="$(SOURCEDIR)/top_flash_sdram_debug.sv" synth route flash

.PHONY: diag
diag:
	$(MAKE) SHOW_CMD="; select -list; select '$$paramod*\top/mac_instance.http_dec.cam.cam_addr*'; show" synth
	xdot ~/.yosys_show.dot

synth: $(SOURCES)
	$(YOSYS) -D SYNTHESIS=1 -DDEBUG=1 -p 'synth_ecp5 -top $(TOP) -json top.json$(SHOW_CMD)' $^

.PHONY: top
top: $(SOURCES)
	$(YOSYS) -D SYNTHESIS=1 -DDEBUG=1 -p \
		'chparam -set TCP_ECHO_EN $(DEF_TCP_ECHO_EN) $(TOP); chparam -set HTTP_ADDR_FILE $(DEF_HTTP_ADDR_FILE) $(TOP); chparam -set HTTP_SIZE_FILE $(DEF_HTTP_SIZE_FILE) $(TOP); synth_ecp5 -top $(TOP) -json top.json$(SHOW_CMD)' $^

route:
	$(PNR) --25k --package CABGA256 --json top.json \
			--lpf pinout.lpf --textcfg top.config --freq 125 --detailed-timing-report
	$(PACK) --compress --svf top.svf top.config top.bit

program: top.svf
	$(LOADER) -f colorlight.cfg -c "svf -quiet -progress top.svf; exit"

flash: top.bit
	openFPGALoader -c digilent_hs2 -f --unprotect-flash top.bit --verbose-level 2

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

.PHONY: http
http:
	curl -vv --http1.0 http://105.105.105.105:8080/0
