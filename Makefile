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


clean:
	rm *.bit
	rm *.svf
