import os
import cocotb
from cocotb_tools.runner import get_runner
from cocotb.clock import Clock, Timer
from cocotb.utils import get_sim_steps
from cocotb.triggers import RisingEdge, FallingEdge, with_timeout, First
from cocotbext.spi import SpiSlaveBase, SpiBus, SpiConfig, SpiFrameError


class TB:
    def __init__(self, dut):
        self.dut = dut

        cocotb.start_soon(self._run_clocks(dut.clk, 0, 8))
        cocotb.start_soon(self._run_clocks(dut.sclk, 90, 8))

    async def reset(self):
        self.dut.rst.setimmediatevalue(1)
        await RisingEdge(self.dut.clk)
        await RisingEdge(self.dut.clk)
        self.dut.rst.value = 1
        self.dut.rst.value = 1
        await RisingEdge(self.dut.clk)
        await RisingEdge(self.dut.clk)
        self.dut.rst.value = 0
        self.dut.rst.value = 0
        await RisingEdge(self.dut.clk)
        await RisingEdge(self.dut.clk)

    async def _run_clocks(self, port, phase, period, en_sig=None):
        half_period = get_sim_steps(period / 2.0, 'ns')
        t = Timer(half_period)

        if phase > 0:
            await Timer(phase/360.0 * period, 'ns')
        while True:
            if (en_sig is not None and en_sig.value == 0):
                await t
                await t
            else:
                port.value = cocotb.handle.Immediate(1)
                await t
                port.value = cocotb.handle.Immediate(0)
                await t


class WinbondRAM(SpiSlaveBase):
    _config = SpiConfig(
        word_width=8,     # all parameters optional
        sclk_freq=125e6,   # these are the defaults
        cpol=False,
        cpha=False,
        msb_first=True,
        data_output_idle=0,
        cs_active_low=True  # optional (assumed True)
    )

    def __init__(self, bus, mem=None):
        self.values = {"inst": 0, "addr": 0}
        self.mem = mem
        super().__init__(bus)

    async def get_values(self):
        await self.idle.wait()
        return self.values

    async def _byte_2_bit(self, frame_end, b):
        for i in range(self._config.word_width):
            self._miso.value = bool(
                b & (1 << (self._config.word_width - 1 - i)))
            s = First(await First(FallingEdge(self._sclk), frame_end))
            t = First(await Timer(1.5, unit="ns"), frame_end)
            assert frame_end not in (
                s, t), "SPI ended in the middle of transaction"

    async def _transaction(self, frame_start, frame_end) -> None:
        await frame_start
        self.idle.clear()
        if bool(self._sclk.value):
            raise SpiFrameError(
                "sclk should be low at chip select edge")

        self.values["inst"] = int(await self._shift(8))
        if (self.values["inst"] != 0x9f):
            self.values["addr"] = int(await self._shift(24))
            starting_val = self.mem[self.values["addr"]]
        # FIXME: the behavior does not match the data sheet. MISO only changes
        # 1 cycle after the last MOSI bit. workaround here:
        await FallingEdge(self._sclk)

        counter = 0
        if (self.values["inst"] != 0x9f):
            while await First(cocotb.start_soon(self._byte_2_bit(frame_end, starting_val+counter)), frame_end) != frame_end:
                counter += 1
                pass
        else:
            await self._byte_2_bit(frame_end, 0xDE)
            await frame_end


@cocotb.test()
async def spi_meta(dut):
    tb = TB(dut)
    await tb.reset()
    spi_bus = SpiBus.from_entity(dut, cs_name="cs")
    spi_slave = WinbondRAM(spi_bus)
    await RisingEdge(dut.clk)
    dut.i_en.value = 1
    dut.i_inst.value = 0x9f
    dut.i_addr.value = 0
    dut.i_addr_en.value = 0
    dut.i_size.value = 1
    await RisingEdge(dut.clk)
    dut.i_en.value = 0
    await RisingEdge(dut.clk)
    await RisingEdge(dut.clk)
    trans = cocotb.start_soon(spi_slave.get_values())
    while True:
        vals = await First(RisingEdge(dut.o_valid), trans.complete)
        print(vals)
        if isinstance(vals, RisingEdge):
            assert int(dut.o_data.value) == 0xDE
        else:
            assert trans.result()["inst"] == 0x9f
            assert trans.result()["addr"] == dut.i_addr.value
            break


@cocotb.test()
async def spi_read(dut):
    inst = 0x03
    addr = 0

    tb = TB(dut)
    await tb.reset()
    spi_bus = SpiBus.from_entity(dut, cs_name="cs")
    mem = {0: 0xDE}
    spi_slave = WinbondRAM(spi_bus, mem)
    await RisingEdge(dut.clk)
    dut.i_en.value = 1
    dut.i_inst.value = inst
    dut.i_addr.value = addr
    dut.i_addr_en.value = 1
    dut.i_size.value = 10
    await RisingEdge(dut.clk)
    dut.i_en.value = 0
    await RisingEdge(dut.clk)
    await RisingEdge(dut.clk)
    trans = cocotb.start_soon(spi_slave.get_values())
    counter = 0
    while True:
        vals = await First(RisingEdge(dut.o_valid), trans.complete)
        if isinstance(vals, RisingEdge):
            assert int(dut.o_data.value) == mem[0] + counter
            counter += 1
        else:
            assert trans.result()["inst"] == inst
            assert trans.result()["addr"] == addr
            assert counter == 10
            break


def test_simple_dff_runner():
    sim = os.getenv("SIM", "verilator")

    source_folder = "../../rtl"
    sources = [
        f"./test_spi.sv",
        f"{source_folder}/spi_master.sv",
    ]

    # if sim == "verilator":
    #     sources.append("../../config.vlt")

    runner = get_runner(sim)
    runner.build(
        sources=sources,
        hdl_toplevel="test_spi",
        waves=True,
        verbose=True,
        includes=[f"{source_folder}/"],
        build_args=["--threads", "8", "--trace-fst",
                    "--trace-structs", "--bbox-unsup",
                    ] if sim == "verilator" else [
            "-y/home/bawj/lscc/diamond/3.14/cae_library/simulation/verilog/ecp5u/"],
        timescale=("1ns", "1ps"),
    )

    runner.test(waves=True,
                verbose=True,
                hdl_toplevel="test_spi", test_module="test_spi")
