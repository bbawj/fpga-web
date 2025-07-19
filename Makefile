TOOLPATH=~/oss-cad-suite/bin
YOSYS=$(TOOLPATH)/yosys
PNR=$(TOOLPATH)/nextpnr-ecp5
PACK=$(TOOLPATH)/ecppack
LOADER=$(TOOLPATH)/openocd
MODULE=mac

synth: $(MODULE).sv clk_gen.sv rgmii_tx.sv rgmii_rcv.sv crc32.sv arp_encode.sv arp_decode.sv
	$(YOSYS) -p "synth_ecp5 -top $(MODULE) -json $(MODULE).json" $^
	$(PNR) --25k --package CABGA256 --json $(MODULE).json \
			--lpf pinout.lpf --textcfg $(MODULE).config
	$(PACK) --svf $(MODULE).svf $(MODULE).config $(MODULE).bit

flash: $(MODULE).svf
	$(LOADER) -f colorlight.cfg -c "svf -quiet -progress $@; exit"


clean:
	rm *.bit
	rm *.svf
