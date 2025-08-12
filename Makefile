TOOLPATH=~/oss-cad-suite/bin
YOSYS=$(TOOLPATH)/yosys
PNR=$(TOOLPATH)/nextpnr-ecp5
PACK=$(TOOLPATH)/ecppack
LOADER=$(TOOLPATH)/openocd
SOURCEDIR=rtl
SOURCES := $(shell find $(SOURCEDIR) -name '*.sv')
MODULE=top

synth: $(MODULE).sv $(SOURCES)
	$(YOSYS) -D SYNTHESIS=1 -p "synth_ecp5 -top $(MODULE) -json $(MODULE).json" $^
	$(PNR) --25k --package CABGA256 --json $(MODULE).json \
			--lpf pinout.lpf --textcfg $(MODULE).config
	$(PACK) --svf $(MODULE).svf $(MODULE).config $(MODULE).bit

flash: $(MODULE).svf
	$(LOADER) -f colorlight.cfg -c "svf -quiet -progress $@; exit"


.PHONY: clean
clean:
	rm *.bit
	rm *.svf

.PHONY: arp
arp:
	sudo arping -c 1 -i enp61s0 -t DE:AD:BE:EF:CA:FE -S 192.168.69.100 105.105.105.105
